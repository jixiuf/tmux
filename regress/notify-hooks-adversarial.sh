#!/bin/sh

# Test: Notify/alert system and hook adversarial edge cases
#
# Verifies that the notification system (monitor-activity, monitor-bell,
# monitor-silence), hooks, and alert handling work correctly under stress
# without crashing.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lnotify"
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

# --- Test 1: Monitor-activity toggle ---
test_num=$((test_num + 1))
$TMUX set -g monitor-activity on
val=$($TMUX show -gv monitor-activity 2>/dev/null)
check_result "Test $test_num: monitor-activity set on" "on" "$val"
$TMUX set -g monitor-activity off

# --- Test 2: Monitor-bell toggle ---
test_num=$((test_num + 1))
$TMUX set -g monitor-bell on
val=$($TMUX show -gv monitor-bell 2>/dev/null)
check_result "Test $test_num: monitor-bell set on" "on" "$val"

# --- Test 3: Bell triggers with monitor-bell ---
test_num=$((test_num + 1))
$TMUX set -g monitor-bell on
$TMUX new-window 'sleep 10'
sleep 0.3
$TMUX select-window -t0
# Send bell to background window
$TMUX send-keys -t1 "printf '\\a'" Enter 2>/dev/null
sleep 0.5
check_alive "Test $test_num: bell in background window"
$TMUX kill-window -t1 2>/dev/null

# --- Test 4: Rapid bell sequences ---
test_num=$((test_num + 1))
for i in $(seq 1 20); do
	$TMUX send-keys "printf '\\a'" Enter
done
sleep 0.5
check_alive "Test $test_num: rapid bell sequences (20)"

# --- Test 5: Monitor-silence with very short interval ---
test_num=$((test_num + 1))
$TMUX set -g monitor-silence 1
sleep 2
$TMUX set -g monitor-silence 0
check_alive "Test $test_num: monitor-silence short interval"

# --- Test 6: Set-hook with simple command ---
test_num=$((test_num + 1))
$TMUX set-hook -g after-new-window 'display-message "hook-fired"'
$TMUX new-window
sleep 0.3
$TMUX kill-window
$TMUX set-hook -gu after-new-window
check_alive "Test $test_num: set-hook after-new-window"

# --- Test 7: Set-hook with format expansion ---
test_num=$((test_num + 1))
$TMUX set-hook -g after-new-session 'display-message "session: #{session_name}"'
$TMUX set-hook -gu after-new-session
check_alive "Test $test_num: hook with format expansion"

# --- Test 8: Rapid hook set/unset ---
test_num=$((test_num + 1))
for i in $(seq 1 20); do
	$TMUX set-hook -g after-new-window "display-message 'hook-$i'"
	$TMUX set-hook -gu after-new-window
done
check_alive "Test $test_num: rapid hook set/unset (20 cycles)"

# --- Test 9: Multiple hooks on same event ---
test_num=$((test_num + 1))
$TMUX set-hook -g after-new-window[0] 'display-message "hook0"'
$TMUX set-hook -g after-new-window[1] 'display-message "hook1"'
$TMUX set-hook -g after-new-window[2] 'display-message "hook2"'
$TMUX new-window
sleep 0.3
$TMUX kill-window
$TMUX set-hook -gu after-new-window
check_alive "Test $test_num: multiple hooks on same event"

# --- Test 10: Hook with shell metacharacters in command ---
test_num=$((test_num + 1))
$TMUX set-hook -g after-new-window 'display-message "$(echo test)"'
$TMUX new-window
sleep 0.3
$TMUX kill-window
$TMUX set-hook -gu after-new-window
check_alive "Test $test_num: hook with shell metacharacters"

# --- Test 11: Visual bell option ---
test_num=$((test_num + 1))
$TMUX set -g visual-bell on
$TMUX send-keys "printf '\\a'" Enter
sleep 0.3
$TMUX set -g visual-bell off
check_alive "Test $test_num: visual-bell on/off"

# --- Test 12: Visual activity option ---
test_num=$((test_num + 1))
$TMUX set -g visual-activity on
$TMUX set -g monitor-activity on
sleep 0.3
$TMUX set -g visual-activity off
$TMUX set -g monitor-activity off
check_alive "Test $test_num: visual-activity on/off"

# --- Test 13: Activity action options ---
test_num=$((test_num + 1))
for action in any none current other; do
	$TMUX set -g activity-action "$action" 2>/dev/null
done
$TMUX set -g activity-action other
check_alive "Test $test_num: activity-action cycling"

# --- Test 14: Bell action options ---
test_num=$((test_num + 1))
for action in any none current other; do
	$TMUX set -g bell-action "$action" 2>/dev/null
done
$TMUX set -g bell-action any
check_alive "Test $test_num: bell-action cycling"

# --- Test 15: Wait-for signal ---
test_num=$((test_num + 1))
# Signal a channel that no one is waiting on
$TMUX wait-for -S test-signal-12345
check_alive "Test $test_num: wait-for signal with no waiter"

# --- Test 16: Display-message with format variables ---
test_num=$((test_num + 1))
result=$($TMUX display-message -p '#{window_index}:#{pane_index}' 2>/dev/null)
case "$result" in
	[0-9]*:[0-9]*)
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s Test %d: display-message format vars\n' \
			"$GREEN" "$RESET" "$test_num"
		;;
	*)
		printf '%s[FAIL]%s Test %d: format vars -> got "%s"\n' \
			"$RED" "$RESET" "$test_num" "$result"
		exit_status=1
		;;
esac

# --- Test 17: Hook that triggers another hook (chain) ---
test_num=$((test_num + 1))
$TMUX set-hook -g after-new-window 'new-window'
# This would cause infinite window creation without limits
# tmux should handle this gracefully (command queue limits)
$TMUX new-window 2>/dev/null
sleep 1
# Kill any excess windows
while [ "$($TMUX list-windows 2>/dev/null | wc -l)" -gt 1 ]; do
	$TMUX kill-window 2>/dev/null
done
$TMUX set-hook -gu after-new-window
check_alive "Test $test_num: recursive hook (new-window in after-new-window)"

# --- Test 18: Rapid window rename notifications ---
test_num=$((test_num + 1))
for i in $(seq 1 30); do
	$TMUX rename-window "name-$i"
done
$TMUX rename-window ''
check_alive "Test $test_num: rapid window rename (30 cycles)"

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
