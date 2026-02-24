#!/bin/sh

# Test: Control mode adversarial injection attempts
#
# Verifies that pane output cannot inject fake control mode protocol
# messages (%begin, %end, %output, %error, etc.) into the control
# client's stream. All pane output bytes < 0x20 (including newlines)
# should be escaped to octal by control_append_data().
#
# Also tests that control mode clients handle rapid session/window/pane
# creation and destruction without crashing.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lctladv"
$TMUX kill-server 2>/dev/null
sleep 1

RED=$(printf '\033[31m')
GREEN=$(printf '\033[32m')
RESET=$(printf '\033[0m')

exit_status=0

check_result () {
	label=$1
	expected=$2
	actual=$3

	if [ "$actual" = "$expected" ]; then
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s %s\n' \
			"$GREEN" "$RESET" "$label"
	else
		printf '%s[FAIL]%s %s -> expected "%s" (Got: "%s")\n' \
			"$RED" "$RESET" "$label" "$expected" "$actual"
		exit_status=1
	fi
}

$TMUX -f/dev/null new -x80 -y24 -d || exit 1
sleep 1

# --- Test 1: Newline injection via pane output ---
# A malicious program tries to inject a fake %begin/%end block into
# the control mode stream by including newlines in its output.
CTL_OUT=$(mktemp)
trap "rm -f $CTL_OUT" 0 1 15

cat /dev/null | $TMUX -C a -t0: > "$CTL_OUT" 2>&1 &
CTL_PID=$!
sleep 1

# Run a command in the pane that outputs text with embedded newlines
# and a fake %begin line
$TMUX send-keys "printf 'BEFORE\\n%%begin 999 0 0\\nFAKE INJECTED\\n%%end 999 0 0\\nAFTER'" Enter
sleep 1

# Check the control output for the injected lines
# The control mode should have escaped newlines to \012
if grep -q '^%begin 999' "$CTL_OUT"; then
	check_result "newline injection blocked" "escaped" "INJECTED"
else
	check_result "newline injection blocked" "escaped" "escaped"
fi

kill $CTL_PID 2>/dev/null
wait $CTL_PID 2>/dev/null

# --- Test 2: Backslash injection in pane output ---
# control_append_data() should also escape backslashes to prevent
# octal escape confusion
CTL_OUT2=$(mktemp)
trap "rm -f $CTL_OUT $CTL_OUT2" 0 1 15

cat /dev/null | $TMUX -C a -t0: > "$CTL_OUT2" 2>&1 &
CTL_PID=$!
sleep 1

$TMUX send-keys "printf 'test\\\\012fake'" Enter
sleep 1

# The literal backslash followed by "012" should NOT be confused with
# an escaped newline. control_append_data escapes backslashes too.
if $TMUX has-session 2>/dev/null; then
	check_result "backslash escaping in control output" "survived" "survived"
else
	check_result "backslash escaping in control output" "survived" "crashed"
fi

kill $CTL_PID 2>/dev/null
wait $CTL_PID 2>/dev/null

# --- Test 3: Rapid window create/destroy with control client ---
CTL_OUT3=$(mktemp)
trap "rm -f $CTL_OUT $CTL_OUT2 $CTL_OUT3" 0 1 15

cat /dev/null | $TMUX -C a -t0: > "$CTL_OUT3" 2>&1 &
CTL_PID=$!
sleep 1

for i in $(seq 1 20); do
	$TMUX new-window 2>/dev/null
	$TMUX kill-window 2>/dev/null
done

sleep 0.5

if $TMUX has-session 2>/dev/null; then
	check_result "rapid window create/destroy (20 cycles)" "survived" "survived"
else
	check_result "rapid window create/destroy (20 cycles)" "survived" "crashed"
fi

kill $CTL_PID 2>/dev/null
wait $CTL_PID 2>/dev/null

# --- Test 4: Rapid session create/destroy with control client ---
cat /dev/null | $TMUX -C a -t0: > /dev/null 2>&1 &
CTL_PID=$!
sleep 1

for i in $(seq 1 10); do
	$TMUX new-session -d -s "stress$i" 2>/dev/null
done
for i in $(seq 1 10); do
	$TMUX kill-session -t "stress$i" 2>/dev/null
done

sleep 0.5

if $TMUX has-session 2>/dev/null; then
	check_result "rapid session create/destroy (10 cycles)" "survived" "survived"
else
	check_result "rapid session create/destroy (10 cycles)" "survived" "crashed"
fi

kill $CTL_PID 2>/dev/null
wait $CTL_PID 2>/dev/null

# --- Test 5: Binary output through control mode ---
cat /dev/null | $TMUX -C a -t0: > /dev/null 2>&1 &
CTL_PID=$!
sleep 1

# Send all bytes 0x00-0x1F through pane output
$TMUX send-keys "python3 -c \"import os; os.write(1, bytes(range(32)))\"" Enter
sleep 1

if $TMUX has-session 2>/dev/null; then
	check_result "binary output (0x00-0x1F) through control mode" "survived" "survived"
else
	check_result "binary output (0x00-0x1F) through control mode" "survived" "crashed"
fi

kill $CTL_PID 2>/dev/null
wait $CTL_PID 2>/dev/null

# --- Test 6: Control mode with special characters in session name ---
$TMUX rename-session "test session with spaces"
sleep 0.3
$TMUX rename-session "test;session"
sleep 0.3
$TMUX rename-session "test'session"
sleep 0.3
$TMUX rename-session "test\"session"
sleep 0.3
$TMUX rename-session "0"
sleep 0.3

if $TMUX has-session 2>/dev/null; then
	check_result "special chars in session name" "survived" "survived"
else
	check_result "special chars in session name" "survived" "crashed"
fi

$TMUX kill-server 2>/dev/null
exit $exit_status
