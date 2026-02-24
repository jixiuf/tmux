#!/bin/sh

# Test: Screen write operations adversarial edge cases
#
# Verifies that the screen write subsystem handles adversarial inputs:
# extreme cursor positions, wide characters at boundaries, scroll region
# stress, rapid screen operations, alternate screen mode, and grid
# expansion edge cases.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lscrwrt"
$TMUX kill-server 2>/dev/null
sleep 1

RED=$(printf '\033[31m')
GREEN=$(printf '\033[32m')
RESET=$(printf '\033[0m')

exit_status=0
test_num=0

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

# --- Test 1: Cursor move to extreme positions ---
test_num=$((test_num + 1))
# CUP to row 9999, col 9999 — should be clamped
$TMUX send-keys "printf '\\033[9999;9999H'" Enter
sleep 0.3
check_alive "Test $test_num: cursor move to extreme position (9999,9999)"

# --- Test 2: Cursor move to origin ---
test_num=$((test_num + 1))
$TMUX send-keys "printf '\\033[1;1H'" Enter
sleep 0.3
check_alive "Test $test_num: cursor move to origin (1,1)"

# --- Test 3: Wide character at right margin ---
test_num=$((test_num + 1))
# Move to column 79 (last column in 80-col terminal) and write a wide char
$TMUX send-keys "printf '\\033[1;80H漢'" Enter
sleep 0.3
check_alive "Test $test_num: wide character at right margin"

# --- Test 4: Fill screen with wide characters ---
test_num=$((test_num + 1))
$TMUX send-keys "python3 -c \"print('漢' * 1000)\"" Enter
sleep 0.5
check_alive "Test $test_num: fill screen with wide characters"

# --- Test 5: Scroll region set and scroll ---
test_num=$((test_num + 1))
# Set scroll region to rows 5-15
$TMUX send-keys "printf '\\033[5;15r'" Enter
# Move to bottom of region and scroll
$TMUX send-keys "printf '\\033[15;1H'" Enter
for i in $(seq 1 20); do
	$TMUX send-keys "printf '\\n'" Enter
done
# Reset scroll region
$TMUX send-keys "printf '\\033[r'" Enter
check_alive "Test $test_num: scroll region scrolling"

# --- Test 6: Scroll region with single line ---
test_num=$((test_num + 1))
# Try to set a single-line scroll region (should be rejected or handled)
$TMUX send-keys "printf '\\033[5;5r'" Enter
sleep 0.3
$TMUX send-keys "printf '\\033[r'" Enter
check_alive "Test $test_num: single-line scroll region"

# --- Test 7: Alternate screen mode on/off ---
test_num=$((test_num + 1))
$TMUX send-keys "printf '\\033[?1049h'" Enter
sleep 0.3
$TMUX send-keys "echo 'alternate screen'" Enter
sleep 0.3
$TMUX send-keys "printf '\\033[?1049l'" Enter
sleep 0.3
check_alive "Test $test_num: alternate screen mode on/off"

# --- Test 8: Rapid alternate screen toggling ---
test_num=$((test_num + 1))
for i in $(seq 1 20); do
	$TMUX send-keys "printf '\\033[?1049h'" Enter
	$TMUX send-keys "printf '\\033[?1049l'" Enter
done
sleep 0.5
check_alive "Test $test_num: rapid alternate screen toggle (20 cycles)"

# --- Test 9: Clear screen operations ---
test_num=$((test_num + 1))
# ED - Erase in Display (all variants)
$TMUX send-keys "printf '\\033[0J'" Enter  # cursor to end
$TMUX send-keys "printf '\\033[1J'" Enter  # beginning to cursor
$TMUX send-keys "printf '\\033[2J'" Enter  # entire screen
$TMUX send-keys "printf '\\033[3J'" Enter  # entire screen + scrollback
sleep 0.3
check_alive "Test $test_num: clear screen operations (ED 0,1,2,3)"

# --- Test 10: Clear line operations ---
test_num=$((test_num + 1))
$TMUX send-keys "printf '\\033[0K'" Enter  # cursor to end
$TMUX send-keys "printf '\\033[1K'" Enter  # beginning to cursor
$TMUX send-keys "printf '\\033[2K'" Enter  # entire line
sleep 0.3
check_alive "Test $test_num: clear line operations (EL 0,1,2)"

# --- Test 11: Insert/delete line operations ---
test_num=$((test_num + 1))
# IL - Insert 10 lines
$TMUX send-keys "printf '\\033[10L'" Enter
# DL - Delete 10 lines
$TMUX send-keys "printf '\\033[10M'" Enter
check_alive "Test $test_num: insert/delete 10 lines"

# --- Test 12: Insert/delete with excessive count ---
test_num=$((test_num + 1))
$TMUX send-keys "printf '\\033[9999L'" Enter
$TMUX send-keys "printf '\\033[9999M'" Enter
check_alive "Test $test_num: insert/delete 9999 lines (clamped)"

# --- Test 13: Insert/delete character operations ---
test_num=$((test_num + 1))
$TMUX send-keys "printf '\\033[10@'" Enter  # ICH - Insert 10 chars
$TMUX send-keys "printf '\\033[10P'" Enter  # DCH - Delete 10 chars
check_alive "Test $test_num: insert/delete characters"

# --- Test 14: Erase characters ---
test_num=$((test_num + 1))
$TMUX send-keys "printf '\\033[80X'" Enter  # ECH - Erase 80 chars
check_alive "Test $test_num: erase 80 characters"

# --- Test 15: Tab handling ---
test_num=$((test_num + 1))
# Set and clear tabs
$TMUX send-keys "printf '\\033H'" Enter   # HTS - Set tab stop
$TMUX send-keys "printf '\\033[0g'" Enter  # TBC - Clear current tab
$TMUX send-keys "printf '\\033[3g'" Enter  # TBC - Clear all tabs
check_alive "Test $test_num: tab stop set/clear"

# --- Test 16: Rapid resize during output ---
test_num=$((test_num + 1))
$TMUX send-keys "seq 1 500 &" Enter
for i in $(seq 1 10); do
	$TMUX resize-window -x 40 -y 12 2>/dev/null
	$TMUX resize-window -x 80 -y 24 2>/dev/null
done
sleep 2
check_alive "Test $test_num: rapid resize during output"

# --- Test 17: Very long line (no wrap mode) ---
test_num=$((test_num + 1))
# Disable wrap mode and write a very long line
$TMUX send-keys "printf '\\033[?7l'" Enter  # DECRST autowrap
$TMUX send-keys "python3 -c \"print('X' * 500, end='')\"" Enter
sleep 0.3
$TMUX send-keys "printf '\\033[?7h'" Enter  # DECSET autowrap
check_alive "Test $test_num: long line without wrap mode"

# --- Test 18: Reverse index at top of screen ---
test_num=$((test_num + 1))
$TMUX send-keys "printf '\\033[1;1H'" Enter  # Move to top
$TMUX send-keys "printf '\\033M'" Enter       # RI - Reverse Index
$TMUX send-keys "printf '\\033M'" Enter       # Again
check_alive "Test $test_num: reverse index at top of screen"

# --- Test 19: Reverse index with scroll region ---
test_num=$((test_num + 1))
$TMUX send-keys "printf '\\033[5;15r'" Enter  # Set scroll region
$TMUX send-keys "printf '\\033[5;1H'" Enter   # Move to top of region
for i in $(seq 1 10); do
	$TMUX send-keys "printf '\\033M'" Enter    # RI - Reverse scroll
done
$TMUX send-keys "printf '\\033[r'" Enter       # Reset region
check_alive "Test $test_num: reverse index within scroll region"

# --- Test 20: Save/restore cursor around operations ---
test_num=$((test_num + 1))
$TMUX send-keys "printf '\\033[s'" Enter      # DECSC
$TMUX send-keys "printf '\\033[10;10H'" Enter # Move
$TMUX send-keys "printf '\\033[u'" Enter      # DECRC
check_alive "Test $test_num: save/restore cursor"

# --- Test 21: Many scrollback lines ---
test_num=$((test_num + 1))
$TMUX send-keys "seq 1 5000" Enter
sleep 2
# Navigate in scrollback
$TMUX copy-mode
$TMUX send-keys -X history-top
sleep 0.3
$TMUX send-keys -X history-bottom
$TMUX send-keys -X cancel
check_alive "Test $test_num: 5000 scrollback lines navigation"

# --- Test 22: Rapid split with output in each pane ---
test_num=$((test_num + 1))
$TMUX split-window -h
$TMUX send-keys -t0 "seq 1 100" Enter
$TMUX send-keys -t1 "seq 1 100" Enter
sleep 1
$TMUX kill-pane -t1 2>/dev/null
check_alive "Test $test_num: output in split panes"

# --- Test 23: Fill scrollback with wide characters ---
test_num=$((test_num + 1))
$TMUX send-keys "python3 -c \"
for i in range(200):
    print('漢字テスト' * 10)
\"" Enter
sleep 2
check_alive "Test $test_num: scrollback with wide characters"

# --- Test 24: Origin mode with scroll region ---
test_num=$((test_num + 1))
$TMUX send-keys "printf '\\033[5;15r'" Enter    # Set scroll region
$TMUX send-keys "printf '\\033[?6h'" Enter      # DECOM - Origin mode
$TMUX send-keys "printf '\\033[1;1H'" Enter     # Should be relative to region
$TMUX send-keys "printf '\\033[?6l'" Enter      # Reset origin mode
$TMUX send-keys "printf '\\033[r'" Enter         # Reset region
check_alive "Test $test_num: origin mode with scroll region"

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
