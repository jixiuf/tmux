#!/bin/sh

# Test: UTF-8 and layout adversarial edge cases
#
# Verifies that UTF-8 handling, grid operations, and layout management
# handle adversarial inputs without crashing: invalid UTF-8 sequences,
# wide characters, extreme resize, rapid split/unsplit.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lutf8lay"
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

# --- Test 1: Valid UTF-8 multibyte characters ---
test_num=$((test_num + 1))
$TMUX send-keys "echo 'héllo wörld 日本語 🎉'" Enter
sleep 0.3
result=$($TMUX capture-pane -p | grep 'héllo' | head -1)
case "$result" in
	*héllo*)
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s Test %d: valid UTF-8 multibyte displayed\n' \
			"$GREEN" "$RESET" "$test_num"
		;;
	*)
		printf '%s[FAIL]%s Test %d: UTF-8 not displayed correctly (got: "%s")\n' \
			"$RED" "$RESET" "$test_num" "$result"
		exit_status=1
		;;
esac

# --- Test 2: Invalid UTF-8 sequences (truncated) ---
test_num=$((test_num + 1))
# Send a truncated 3-byte UTF-8 sequence (only 2 bytes)
$TMUX send-keys "printf '\\xE0\\x80'" Enter
sleep 0.3
check_alive "Test $test_num: truncated UTF-8 sequence handled"

# --- Test 3: Overlong UTF-8 encoding ---
test_num=$((test_num + 1))
# Overlong encoding of '/' (U+002F): C0 AF
$TMUX send-keys "printf '\\xC0\\xAF'" Enter
sleep 0.3
check_alive "Test $test_num: overlong UTF-8 encoding handled"

# --- Test 4: UTF-8 continuation byte without start ---
test_num=$((test_num + 1))
$TMUX send-keys "printf '\\x80\\x81\\x82'" Enter
sleep 0.3
check_alive "Test $test_num: orphan continuation bytes handled"

# --- Test 5: Maximum valid UTF-8 (U+10FFFF) ---
test_num=$((test_num + 1))
$TMUX send-keys "printf '\\xF4\\x8F\\xBF\\xBF'" Enter
sleep 0.3
check_alive "Test $test_num: max valid UTF-8 codepoint handled"

# --- Test 6: Invalid codepoint above U+10FFFF ---
test_num=$((test_num + 1))
# F4 90 80 80 = U+110000 (invalid)
$TMUX send-keys "printf '\\xF4\\x90\\x80\\x80'" Enter
sleep 0.3
check_alive "Test $test_num: codepoint above U+10FFFF handled"

# --- Test 7: Wide characters (CJK) filling line ---
test_num=$((test_num + 1))
# Fill a line with 40 wide (2-cell) characters
$TMUX send-keys "python3 -c \"print('漢' * 40)\"" Enter
sleep 0.3
check_alive "Test $test_num: line full of wide characters"

# --- Test 8: Mixed narrow and wide characters ---
test_num=$((test_num + 1))
$TMUX send-keys "echo 'A漢B漢C漢D漢E'" Enter
sleep 0.3
result=$($TMUX capture-pane -p | grep 'A漢B' | head -1)
case "$result" in
	*A漢B*)
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s Test %d: mixed narrow/wide chars\n' \
			"$GREEN" "$RESET" "$test_num"
		;;
	*)
		printf '%s[FAIL]%s Test %d: mixed chars not displayed (got: "%s")\n' \
			"$RED" "$RESET" "$test_num" "$result"
		exit_status=1
		;;
esac

# --- Test 9: Rapid resize ---
test_num=$((test_num + 1))
for i in $(seq 1 10); do
	$TMUX resize-window -x 40 -y 12 2>/dev/null
	$TMUX resize-window -x 80 -y 24 2>/dev/null
done
check_alive "Test $test_num: rapid resize (10 cycles)"

# --- Test 10: Minimum window size ---
test_num=$((test_num + 1))
$TMUX resize-window -x 1 -y 1 2>/dev/null
sleep 0.2
$TMUX resize-window -x 80 -y 24
check_alive "Test $test_num: minimum window size (1x1)"

# --- Test 11: Rapid split/unsplit ---
test_num=$((test_num + 1))
for i in $(seq 1 15); do
	$TMUX split-window -h 2>/dev/null
	$TMUX kill-pane -t '{last}' 2>/dev/null
done
check_alive "Test $test_num: rapid split/unsplit (15 cycles)"

# --- Test 12: Many horizontal splits ---
test_num=$((test_num + 1))
for i in $(seq 1 10); do
	$TMUX split-window -v 2>/dev/null
done
panes=$($TMUX list-panes 2>/dev/null | wc -l)
# Kill extra panes
while [ "$($TMUX list-panes 2>/dev/null | wc -l)" -gt 1 ]; do
	$TMUX kill-pane -t '{last}' 2>/dev/null
done
check_alive "Test $test_num: many vertical splits ($panes panes)"

# --- Test 13: Zero-width pane attempt ---
test_num=$((test_num + 1))
# Try to resize pane to 0 width
$TMUX resize-pane -x 0 2>/dev/null
sleep 0.2
$TMUX resize-pane -x 80 2>/dev/null
check_alive "Test $test_num: zero-width pane resize attempt"

# --- Test 14: Window rename with UTF-8 ---
test_num=$((test_num + 1))
$TMUX rename-window '日本語ウィンドウ'
name=$($TMUX display-message -p '#{window_name}')
check_result "Test $test_num: UTF-8 window name" '日本語ウィンドウ' "$name"
$TMUX rename-window ''

# --- Test 15: Session rename with UTF-8 ---
test_num=$((test_num + 1))
$TMUX rename-session 'セッション'
name=$($TMUX display-message -p '#{session_name}')
check_result "Test $test_num: UTF-8 session name" 'セッション' "$name"
$TMUX rename-session '0'

# --- Test 16: Capture-pane with UTF-8 content ---
test_num=$((test_num + 1))
$TMUX send-keys "echo 'café résumé naïve'" Enter
sleep 0.3
result=$($TMUX capture-pane -p | grep 'café' | head -1)
case "$result" in
	*café*)
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s Test %d: capture-pane with UTF-8\n' \
			"$GREEN" "$RESET" "$test_num"
		;;
	*)
		printf '%s[FAIL]%s Test %d: capture-pane UTF-8 failed (got: "%s")\n' \
			"$RED" "$RESET" "$test_num" "$result"
		exit_status=1
		;;
esac

# --- Test 17: Layout switching under stress ---
test_num=$((test_num + 1))
$TMUX split-window -h
$TMUX split-window -v
for layout in even-horizontal even-vertical main-horizontal main-vertical tiled; do
	$TMUX select-layout "$layout" 2>/dev/null
done
# Kill extra panes
while [ "$($TMUX list-panes 2>/dev/null | wc -l)" -gt 1 ]; do
	$TMUX kill-pane -t '{last}' 2>/dev/null
done
check_alive "Test $test_num: layout switching with multiple panes"

# --- Test 18: Scrollback with many lines ---
test_num=$((test_num + 1))
$TMUX send-keys "seq 1 1000" Enter
sleep 1
$TMUX copy-mode
$TMUX send-keys -X history-top
$TMUX send-keys -X cancel
check_alive "Test $test_num: scrollback navigation (1000 lines)"

# --- Test 19: Swap-pane stress ---
test_num=$((test_num + 1))
$TMUX split-window -h
for i in $(seq 1 10); do
	$TMUX swap-pane -U 2>/dev/null
	$TMUX swap-pane -D 2>/dev/null
done
$TMUX kill-pane -t '{last}' 2>/dev/null
check_alive "Test $test_num: rapid swap-pane (10 cycles)"

# --- Final: Verify pane still functional ---
test_num=$((test_num + 1))
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
