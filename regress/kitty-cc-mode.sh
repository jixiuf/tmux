#!/bin/sh

# Test: kitty keyboard protocol interaction with -CC control mode
#
# Verifies that:
# 1. Kitty key encoding works correctly when a -CC client is attached
# 2. Keys sent via send-keys are properly kitty-encoded based on pane flags
# 3. CC client attach/detach doesn't corrupt kitty state
# 4. Panes with different kitty states encode correctly with CC attached
# 5. Kitty pop properly reverts encoding (with kitty-keys on, not always)

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Ltest-kittycc"
$TMUX kill-server 2>/dev/null
sleep 0.5

RC=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"; $TMUX kill-server 2>/dev/null' EXIT

RED=$(printf '\033[31m')
GREEN=$(printf '\033[32m')
RESET=$(printf '\033[0m')

check() {
	label=$1
	expected=$2
	actual=$3
	if [ "$actual" = "$expected" ]; then
		[ -n "$VERBOSE" ] && printf '%s[PASS]%s %s\n' "$GREEN" "$RESET" "$label"
	else
		printf '%s[FAIL]%s %s: expected "%s" got "%s"\n' \
			"$RED" "$RESET" "$label" "$expected" "$actual"
		RC=1
	fi
}

# Start server. Use kitty-keys on (not always) so per-pane state is testable.
$TMUX -f/dev/null new -x80 -y24 -d -s kittycc || exit 1
sleep 0.3
$TMUX set -g kitty-keys on

# --- Test 1: Kitty Escape encoding with -CC client attached ---
# Pane pushes kitty disambiguate mode, then reads via cat -v.
# Escape should be encoded as CSI 27 u → cat -v shows ^[[27u.
$TMUX respawn-window -k -t kittycc:0 -- sh -c \
	'printf "\033[>1u"; stty raw -echo; cat -v'
sleep 0.5

$TMUX -CC attach -t kittycc -d >/dev/null 2>&1 &
CC_PID=$!
sleep 0.3

$TMUX send-keys -t kittycc:0.0 Escape
sleep 0.3

actual=$($TMUX capturep -pt kittycc:0.0 | tr -d '\n' | grep -o '\^\[\[27u' | head -1)
check "kitty-escape-with-cc" "^[[27u" "$actual"

kill $CC_PID 2>/dev/null
wait $CC_PID 2>/dev/null

# --- Test 2: Modified key encoding (Ctrl+a) with -CC client ---
$TMUX respawn-window -k -t kittycc:0 -- sh -c \
	'printf "\033[>1u"; stty raw -echo; cat -v'
sleep 0.5

$TMUX -CC attach -t kittycc -d >/dev/null 2>&1 &
CC_PID=$!
sleep 0.3

$TMUX send-keys -t kittycc:0.0 C-a
sleep 0.3

actual=$($TMUX capturep -pt kittycc:0.0 | tr -d '\n' | grep -o '\^\[\[97;5u' | head -1)
check "kitty-ctrl-a-with-cc" "^[[97;5u" "$actual"

kill $CC_PID 2>/dev/null
wait $CC_PID 2>/dev/null

# --- Test 3: ASCII key pass-through in disambiguate mode ---
# Unmodified 'a' should be sent raw (no CSI encoding).
$TMUX respawn-window -k -t kittycc:0 -- sh -c \
	'printf "\033[>1u"; stty raw -echo; cat -v'
sleep 0.5

$TMUX -CC attach -t kittycc -d >/dev/null 2>&1 &
CC_PID=$!
sleep 0.3

$TMUX send-keys -t kittycc:0.0 -l 'a'
sleep 0.2

# Pane should show 'a', not ^[[97u
has_csi=$($TMUX capturep -pt kittycc:0.0 | tr -d '\n' | grep -c '\^\[\[97u')
check "kitty-ascii-no-csi" "0" "$has_csi"

kill $CC_PID 2>/dev/null
wait $CC_PID 2>/dev/null

# --- Test 4: Legacy encoding after kitty pop (kitty-keys on, not always) ---
# With kitty-keys on, popping should fully disable kitty mode.
$TMUX respawn-window -k -t kittycc:0 -- sh -c \
	'printf "\033[>1u"; sleep 0.3; printf "\033[<u"; stty raw -echo; cat -v'
sleep 1

$TMUX -CC attach -t kittycc -d >/dev/null 2>&1 &
CC_PID=$!
sleep 0.3

$TMUX send-keys -t kittycc:0.0 Escape
sleep 0.3

# After pop with kitty-keys on, Escape should be legacy ^[ not ^[[27u
pane_out=$($TMUX capturep -pt kittycc:0.0 | tr -d '\n')
has_kitty=$(echo "$pane_out" | grep -c '\^\[\[27u')
check "kitty-legacy-after-pop" "0" "$has_kitty"

kill $CC_PID 2>/dev/null
wait $CC_PID 2>/dev/null

# --- Test 5: Two panes, different kitty states, CC attached ---
$TMUX respawn-window -k -t kittycc:0 -- sh -c \
	'printf "\033[>1u"; stty raw -echo; cat -v'
sleep 0.3
$TMUX split-window -t kittycc:0 -- sh -c 'stty raw -echo; cat -v'
sleep 0.3

$TMUX -CC attach -t kittycc -d >/dev/null 2>&1 &
CC_PID=$!
sleep 0.3

# Pane 0 has kitty mode — Escape should be ^[[27u
$TMUX send-keys -t kittycc:0.0 Escape
sleep 0.2
actual=$($TMUX capturep -pt kittycc:0.0 | tr -d '\n' | grep -o '\^\[\[27u' | head -1)
check "kitty-pane0-kitty" "^[[27u" "$actual"

# Pane 1 has NO kitty mode — Escape should be legacy ^[
$TMUX send-keys -t kittycc:0.1 Escape
sleep 0.2
pane1_out=$($TMUX capturep -pt kittycc:0.1 | tr -d '\n')
has_kitty1=$(echo "$pane1_out" | grep -c '\^\[\[27u')
check "kitty-pane1-legacy" "0" "$has_kitty1"

kill $CC_PID 2>/dev/null
wait $CC_PID 2>/dev/null

# --- Test 6: CC client attach/detach cycles don't crash ---
$TMUX respawn-window -k -t kittycc:0 -- sh -c \
	'printf "\033[>1u"; stty raw -echo; cat -v'
sleep 0.5

for i in 1 2 3; do
	$TMUX -CC attach -t kittycc -d >/dev/null 2>&1 &
	PID=$!
	sleep 0.2
	kill $PID 2>/dev/null
	wait $PID 2>/dev/null
done

$TMUX send-keys -t kittycc:0.0 -l 'OK'
sleep 0.2
actual=$($TMUX capturep -pt kittycc:0.0 | grep -o 'OK' | head -1)
check "kitty-alive-after-cc-cycles" "OK" "$actual"

# --- Test 7: Kitty encoding via send-keys from control mode command ---
# Verify that a control mode client can send kitty-encoded keys through
# the command protocol.
$TMUX respawn-window -k -t kittycc:0 -- sh -c \
	'printf "\033[>1u"; stty raw -echo; cat -v'
sleep 0.5

# Send command via -C (single-C control mode, stdin/stdout)
echo "send-keys -t kittycc:0.0 Escape" | $TMUX -C attach -t kittycc 2>/dev/null &
C_PID=$!
sleep 0.5
kill $C_PID 2>/dev/null
wait $C_PID 2>/dev/null

actual=$($TMUX capturep -pt kittycc:0.0 | tr -d '\n' | grep -o '\^\[\[27u' | head -1)
check "kitty-escape-via-control-cmd" "^[[27u" "$actual"

# --- Test 8: Server alive after all operations ---
result=$($TMUX list-sessions 2>&1)
if [ $? -eq 0 ]; then
	[ -n "$VERBOSE" ] && printf '%s[PASS]%s server-alive\n' "$GREEN" "$RESET"
else
	printf '%s[FAIL]%s server-alive\n' "$RED" "$RESET"
	RC=1
fi

exit $RC
