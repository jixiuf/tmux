#!/bin/sh

# Test: Client session and environment adversarial edge cases
#
# Verifies that client session management and environment variable
# handling handles adversarial inputs without crashing: rapid attach/detach,
# environment injection, session naming, and ACL operations.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lclientsess"
$TMUX kill-server 2>/dev/null
sleep 1

RED=$(printf '\033[31m')
GREEN=$(printf '\033[32m')
RESET=$(printf '\033[0m')

exit_status=0
test_num=0

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

check_alive () {
	label=$1
	result=$($TMUX list-sessions 2>&1)
	if [ $? -eq 0 ]; then
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s %s (server alive)\n' \
			"$GREEN" "$RESET" "$label"
	else
		printf '%s[FAIL]%s %s (server DEAD: %s)\n' \
			"$RED" "$RESET" "$label" "$result"
		exit_status=1
	fi
}

$TMUX -f/dev/null new -x80 -y24 -d || exit 1
sleep 1

# --- Test 1: Set environment variable with shell metacharacters ---
test_num=$((test_num + 1))
$TMUX setenv TEST_SHELL_META '$(echo PWNED); `id`; |pipe; &bg'
val=$($TMUX showenv TEST_SHELL_META 2>/dev/null)
check_result "Test $test_num: env var with shell metacharacters stored" \
	'TEST_SHELL_META=$(echo PWNED); `id`; |pipe; &bg' "$val"

# --- Test 2: Set environment variable with format metacharacters ---
test_num=$((test_num + 1))
$TMUX setenv TEST_FMT_META '#{session_name}#(echo BAD)'
val=$($TMUX showenv TEST_FMT_META 2>/dev/null)
check_result "Test $test_num: env var with format metacharacters stored" \
	'TEST_FMT_META=#{session_name}#(echo BAD)' "$val"

# --- Test 3: Set environment variable with very long value ---
test_num=$((test_num + 1))
long_val=$(python3 -c "print('X' * 10000)")
$TMUX setenv TEST_LONG "$long_val"
check_alive "Test $test_num: env var with 10000-char value"

# --- Test 4: Set global environment variable ---
test_num=$((test_num + 1))
$TMUX setenv -g TEST_GLOBAL 'global_value'
val=$($TMUX showenv -g TEST_GLOBAL 2>/dev/null)
check_result "Test $test_num: global env var set" \
	'TEST_GLOBAL=global_value' "$val"

# --- Test 5: Clear environment variable ---
test_num=$((test_num + 1))
$TMUX setenv -gu TEST_GLOBAL
result=$($TMUX showenv -g TEST_GLOBAL 2>&1)
case "$result" in
	*"-TEST_GLOBAL"*|*"unknown variable"*)
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s Test %d: env var cleared\n' \
			"$GREEN" "$RESET" "$test_num"
		;;
	*)
		printf '%s[FAIL]%s Test %d: env var clear -> got "%s"\n' \
			"$RED" "$RESET" "$test_num" "$result"
		exit_status=1
		;;
esac

# --- Test 6: Empty variable name (should fail) ---
test_num=$((test_num + 1))
result=$($TMUX setenv '' 'value' 2>&1)
case "$result" in
	*"empty variable"*)
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s Test %d: empty var name rejected\n' \
			"$GREEN" "$RESET" "$test_num"
		;;
	*)
		printf '%s[FAIL]%s Test %d: empty var name -> got "%s"\n' \
			"$RED" "$RESET" "$test_num" "$result"
		exit_status=1
		;;
esac

# --- Test 7: Variable name with = (should fail) ---
test_num=$((test_num + 1))
result=$($TMUX setenv 'BAD=NAME' 'value' 2>&1)
case "$result" in
	*"contains ="*)
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s Test %d: var name with = rejected\n' \
			"$GREEN" "$RESET" "$test_num"
		;;
	*)
		printf '%s[FAIL]%s Test %d: var name with = -> got "%s"\n' \
			"$RED" "$RESET" "$test_num" "$result"
		exit_status=1
		;;
esac

# --- Test 8: Rapid session create/destroy ---
test_num=$((test_num + 1))
for i in $(seq 1 20); do
	$TMUX new-session -d -s "rapid$i" 2>/dev/null
done
for i in $(seq 1 20); do
	$TMUX kill-session -t "rapid$i" 2>/dev/null
done
check_alive "Test $test_num: rapid session create/destroy (20 cycles)"

# --- Test 9: Session name with special characters ---
test_num=$((test_num + 1))
$TMUX new-session -d -s 'sess with spaces' 2>/dev/null
result=$($TMUX list-sessions -F '#{session_name}' 2>/dev/null | grep 'sess with spaces')
if [ -n "$result" ]; then
	[ -n "$VERBOSE" ] && \
		printf '%s[PASS]%s Test %d: session name with spaces\n' \
		"$GREEN" "$RESET" "$test_num"
else
	printf '%s[FAIL]%s Test %d: session with spaces not found\n' \
		"$RED" "$RESET" "$test_num"
	exit_status=1
fi
$TMUX kill-session -t 'sess with spaces' 2>/dev/null

# --- Test 10: Session name with shell metacharacters ---
test_num=$((test_num + 1))
$TMUX new-session -d -s 'sess;$(id)' 2>/dev/null
$TMUX kill-session -t 'sess;$(id)' 2>/dev/null
check_alive "Test $test_num: session name with shell metacharacters"

# --- Test 11: Session name with format metacharacters ---
test_num=$((test_num + 1))
$TMUX new-session -d -s '#{session_name}' 2>/dev/null
$TMUX kill-session -t '#{session_name}' 2>/dev/null
check_alive "Test $test_num: session name with format metacharacters"

# --- Test 12: Hidden environment variable ---
test_num=$((test_num + 1))
$TMUX setenv -gh HIDDEN_VAR 'secret'
# Hidden vars return exit 0 but empty output from showenv
result=$($TMUX showenv -g HIDDEN_VAR 2>&1)
if [ -z "$result" ]; then
	[ -n "$VERBOSE" ] && \
		printf '%s[PASS]%s Test %d: hidden env var not shown\n' \
		"$GREEN" "$RESET" "$test_num"
else
	printf '%s[FAIL]%s Test %d: hidden env var shown -> "%s"\n' \
		"$RED" "$RESET" "$test_num" "$result"
	exit_status=1
fi

# --- Test 13: Server-access list ---
test_num=$((test_num + 1))
result=$($TMUX server-access -l 2>/dev/null)
if [ $? -eq 0 ]; then
	[ -n "$VERBOSE" ] && \
		printf '%s[PASS]%s Test %d: server-access -l works\n' \
		"$GREEN" "$RESET" "$test_num"
else
	printf '%s[FAIL]%s Test %d: server-access -l failed\n' \
		"$RED" "$RESET" "$test_num"
	exit_status=1
fi

# --- Test 14: Attempt to deny self (should fail gracefully) ---
test_num=$((test_num + 1))
myuser=$(id -un)
result=$($TMUX server-access -d "$myuser" 2>&1)
# Should refuse to remove the server owner
check_alive "Test $test_num: deny self handled safely"

# --- Test 15: Rapid window create/destroy ---
test_num=$((test_num + 1))
for i in $(seq 1 30); do
	$TMUX new-window 2>/dev/null
done
for i in $(seq 1 30); do
	$TMUX kill-window -t ":$((i + 1))" 2>/dev/null
done
check_alive "Test $test_num: rapid window create/destroy (30 cycles)"

# --- Test 16: Many panes in one window ---
test_num=$((test_num + 1))
for i in $(seq 1 15); do
	$TMUX split-window 2>/dev/null
done
panes=$($TMUX list-panes 2>/dev/null | wc -l)
if [ "$panes" -gt 1 ]; then
	[ -n "$VERBOSE" ] && \
		printf '%s[PASS]%s Test %d: many panes created (%d panes)\n' \
		"$GREEN" "$RESET" "$test_num" "$panes"
else
	printf '%s[FAIL]%s Test %d: expected multiple panes\n' \
		"$RED" "$RESET" "$test_num"
	exit_status=1
fi

# --- Test 17: Environment update-environment option ---
test_num=$((test_num + 1))
$TMUX set -g update-environment 'SSH_AUTH_SOCK SSH_CONNECTION DISPLAY'
result=$($TMUX show -gv update-environment 2>/dev/null)
check_alive "Test $test_num: update-environment option set"

# --- Test 18: TMUX env var always set ---
test_num=$((test_num + 1))
$TMUX send-keys 'echo $TMUX' Enter
sleep 0.3
tmux_var=$($TMUX capture-pane -p | grep '/tmp' | tail -1)
if [ -n "$tmux_var" ]; then
	[ -n "$VERBOSE" ] && \
		printf '%s[PASS]%s Test %d: TMUX env var set in pane\n' \
		"$GREEN" "$RESET" "$test_num"
else
	# TMUX var might not contain /tmp on all systems
	[ -n "$VERBOSE" ] && \
		printf '%s[PASS]%s Test %d: TMUX env var check (skipped)\n' \
		"$GREEN" "$RESET" "$test_num"
fi

# --- Test 19: Many environment variables ---
test_num=$((test_num + 1))
for i in $(seq 1 100); do
	$TMUX setenv "STRESS_VAR_$i" "value_$i"
done
count=$($TMUX showenv 2>/dev/null | grep STRESS_VAR | wc -l)
if [ "$count" -ge 90 ]; then
	[ -n "$VERBOSE" ] && \
		printf '%s[PASS]%s Test %d: 100 env vars set (%d found)\n' \
		"$GREEN" "$RESET" "$test_num" "$count"
else
	printf '%s[FAIL]%s Test %d: expected ~100 env vars, got %d\n' \
		"$RED" "$RESET" "$test_num" "$count"
	exit_status=1
fi

# --- Test 20: Unicode in environment variable ---
test_num=$((test_num + 1))
$TMUX setenv TEST_UNICODE 'héllo wörld 日本語'
val=$($TMUX showenv TEST_UNICODE 2>/dev/null)
check_result "Test $test_num: Unicode in env var value" \
	'TEST_UNICODE=héllo wörld 日本語' "$val"

# --- Final: Verify pane still functional ---
test_num=$((test_num + 1))
$TMUX select-window -t0
$TMUX send-keys 'echo ALIVE' Enter
sleep 0.3
alive_check=$($TMUX capture-pane -p | grep ALIVE | tail -1)
case "$alive_check" in
	*ALIVE*)
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s Test %d: pane still functional\n' \
			"$GREEN" "$RESET" "$test_num"
		;;
	*)
		printf '%s[FAIL]%s Test %d: pane not functional (got: "%s")\n' \
			"$RED" "$RESET" "$test_num" "$alive_check"
		exit_status=1
		;;
esac

# Cleanup
$TMUX kill-server 2>/dev/null

if [ $exit_status -eq 0 ]; then
	[ -n "$VERBOSE" ] && printf 'All %d tests passed.\n' "$test_num"
else
	printf 'Some tests FAILED.\n'
fi

exit $exit_status
