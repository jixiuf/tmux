#!/bin/sh

# Test: Popup and menu adversarial stress testing
#
# Verifies that popup and menu operations handle rapid create/destroy,
# edge cases, and stress conditions without crashing. Tests the single
# overlay per client design, nested menu within popup, and lifecycle.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lpopstress"
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

$TMUX -f/dev/null new -x80 -y24 -d || exit 1
sleep 1

# --- Test 1: Basic popup create and close ---
test_num=$((test_num + 1))
$TMUX display-popup -w20 -h5 'echo popup1; sleep 0.2' 2>/dev/null
sleep 0.5
check_alive "Test $test_num: basic popup create/close"

# --- Test 2: Rapid popup create/destroy (20 cycles) ---
test_num=$((test_num + 1))
for i in $(seq 1 20); do
	$TMUX display-popup -w20 -h5 -E 'true' 2>/dev/null
done
sleep 0.5
check_alive "Test $test_num: rapid popup create/destroy (20 cycles)"

# --- Test 3: Popup with minimum dimensions (3x3 with border) ---
test_num=$((test_num + 1))
$TMUX display-popup -w3 -h3 -E 'true' 2>/dev/null
sleep 0.3
check_alive "Test $test_num: minimum dimension popup (3x3)"

# --- Test 4: Popup with maximum dimensions (full terminal) ---
test_num=$((test_num + 1))
$TMUX display-popup -w80 -h24 -E 'true' 2>/dev/null
sleep 0.3
check_alive "Test $test_num: full-size popup (80x24)"

# --- Test 5: Popup without borders ---
test_num=$((test_num + 1))
$TMUX display-popup -B -w20 -h5 -E 'true' 2>/dev/null
sleep 0.3
check_alive "Test $test_num: popup without borders (-B)"

# --- Test 6: Display-menu basic ---
test_num=$((test_num + 1))
$TMUX display-menu -x0 -y0 "Item1" a "display-message 'ok'" "Item2" b "" "" "" "" "Item3" c "display-message 'ok'" 2>/dev/null
sleep 0.3
$TMUX send-keys Escape 2>/dev/null
sleep 0.2
check_alive "Test $test_num: basic display-menu"

# --- Test 7: Rapid menu create/dismiss (20 cycles) ---
test_num=$((test_num + 1))
for i in $(seq 1 20); do
	$TMUX display-menu -x0 -y0 "Test" t "display-message 'test'" 2>/dev/null
	$TMUX send-keys Escape 2>/dev/null
done
sleep 0.5
check_alive "Test $test_num: rapid menu create/dismiss (20 cycles)"

# --- Test 8: Menu with many items ---
test_num=$((test_num + 1))
# Build a menu with 20 items
menu_args=""
for i in $(seq 1 20); do
	menu_args="$menu_args \"Item$i\" \"\" \"display-message 'item$i'\""
done
eval $TMUX display-menu -x0 -y0 $menu_args 2>/dev/null
sleep 0.3
$TMUX send-keys Escape 2>/dev/null
sleep 0.2
check_alive "Test $test_num: menu with 20 items"

# --- Test 9: Menu with separator lines ---
test_num=$((test_num + 1))
$TMUX display-menu -x0 -y0 \
	"Above" a "" \
	"" "" "" \
	"Below" b "" \
	2>/dev/null
sleep 0.3
$TMUX send-keys Escape 2>/dev/null
sleep 0.2
check_alive "Test $test_num: menu with separator lines"

# --- Test 10: Popup replacing existing popup (overlay swap) ---
test_num=$((test_num + 1))
$TMUX display-popup -w20 -h5 'sleep 10' 2>/dev/null &
sleep 0.3
# Open another popup while first is still running — should replace
$TMUX display-popup -w25 -h8 -E 'true' 2>/dev/null
sleep 0.3
check_alive "Test $test_num: popup replacing existing popup"

# --- Test 11: Popup with format expansion in title ---
test_num=$((test_num + 1))
$TMUX display-popup -T '#{session_name}' -w30 -h5 -E 'true' 2>/dev/null
sleep 0.3
check_alive "Test $test_num: popup with format-expanded title"

# --- Test 12: Popup with format metacharacters in title ---
test_num=$((test_num + 1))
$TMUX display-popup -T '#(echo PWNED)' -w30 -h5 -E 'true' 2>/dev/null
sleep 0.3
check_alive "Test $test_num: popup with #(cmd) in title"

# --- Test 13: Popup close via Escape ---
test_num=$((test_num + 1))
$TMUX display-popup -w20 -h5 'sleep 10' 2>/dev/null
sleep 0.3
$TMUX send-keys Escape 2>/dev/null
sleep 0.3
check_alive "Test $test_num: popup close via Escape"

# --- Test 14: Popup close via Ctrl-C ---
test_num=$((test_num + 1))
$TMUX display-popup -w20 -h5 'sleep 10' 2>/dev/null
sleep 0.3
$TMUX send-keys C-c 2>/dev/null
sleep 0.3
check_alive "Test $test_num: popup close via C-c"

# --- Test 15: Popup with special characters in command ---
test_num=$((test_num + 1))
$TMUX display-popup -w30 -h5 -E "echo 'hello \"world\"'; true" 2>/dev/null
sleep 0.5
check_alive "Test $test_num: popup with special chars in command"

# --- Test 16: Popup during window split ---
test_num=$((test_num + 1))
$TMUX split-window -h
sleep 0.3
$TMUX display-popup -w20 -h5 -E 'true' 2>/dev/null
sleep 0.3
# Close the extra pane
$TMUX select-pane -t1
$TMUX send-keys exit Enter
sleep 0.3
check_alive "Test $test_num: popup during split window"

# --- Test 17: Rapid popup with -E (close on exit) ---
test_num=$((test_num + 1))
for i in $(seq 1 30); do
	$TMUX display-popup -E 'true' 2>/dev/null
done
sleep 0.5
check_alive "Test $test_num: rapid popup with -E flag (30 cycles)"

# --- Test 18: Menu keyboard navigation ---
test_num=$((test_num + 1))
$TMUX display-menu -x0 -y0 \
	"First" a "display-message 'first'" \
	"Second" b "display-message 'second'" \
	"Third" c "display-message 'third'" \
	2>/dev/null
sleep 0.2
$TMUX send-keys Down 2>/dev/null
$TMUX send-keys Down 2>/dev/null
$TMUX send-keys Up 2>/dev/null
$TMUX send-keys Enter 2>/dev/null
sleep 0.3
check_alive "Test $test_num: menu keyboard navigation"

# --- Test 19: Menu item by key code ---
test_num=$((test_num + 1))
$TMUX display-menu -x0 -y0 \
	"Alpha" a "display-message 'alpha'" \
	"Beta" b "display-message 'beta'" \
	2>/dev/null
sleep 0.2
$TMUX send-keys b 2>/dev/null
sleep 0.3
check_alive "Test $test_num: menu item selection by key"

# --- Test 20: Popup with zero-length command ---
test_num=$((test_num + 1))
$TMUX display-popup -w20 -h5 -E '' 2>/dev/null
sleep 0.3
check_alive "Test $test_num: popup with empty command"

# --- Test 21: Display-popup -C (close popup when none exists) ---
test_num=$((test_num + 1))
$TMUX display-popup -C 2>/dev/null
sleep 0.2
check_alive "Test $test_num: close popup when none exists"

# --- Test 22: Popup with very long title ---
test_num=$((test_num + 1))
long_title=$(python3 -c "print('T' * 500)")
$TMUX display-popup -T "$long_title" -w30 -h5 -E 'true' 2>/dev/null
sleep 0.3
check_alive "Test $test_num: popup with 500-char title"

# --- Final: Verify pane still functional ---
test_num=$((test_num + 1))
# Dismiss any leftover popup/menu overlay before checking the pane.
$TMUX display-popup -C 2>/dev/null
sleep 0.3
$TMUX send-keys 'echo ALIVE' Enter
# Poll for up to 5 seconds for the output to appear in the pane.
alive_check=""
for _try in $(seq 1 25); do
	alive_check=$($TMUX capture-pane -p | grep ALIVE | tail -1)
	case "$alive_check" in
		*ALIVE*) break ;;
	esac
	sleep 0.2
done
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
