#!/bin/sh

# Test: kitty keyboard pop count is capped to stack size
#
# Verifies that popping more entries than were pushed does not corrupt
# the flag stack.  The 8-entry circular buffer should clamp the pop
# count so that:
#   - flags return to 0 after over-pop
#   - subsequent push/query cycle works correctly (idx is sane)

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lkpopc"
$TMUX kill-server 2>/dev/null
sleep 1

$TMUX -f/dev/null new -x80 -y24 -d || exit 1
sleep 1
$TMUX set -g escape-time 0
$TMUX set -g kitty-keys always

RED=$(printf '\033[31m')
GREEN=$(printf '\033[32m')
RESET=$(printf '\033[0m')

exit_status=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"; $TMUX kill-server 2>/dev/null' EXIT

check_result () {
	label=$1
	expected=$2
	actual=$3

	if [ "$actual" = "$expected" ]; then
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s %s -> %s\n' \
			"$GREEN" "$RESET" "$label" "$actual"
	else
		printf '%s[FAIL]%s %s -> expected %s, got %s\n' \
			"$RED" "$RESET" "$label" "$expected" "$actual"
		exit_status=1
	fi
}

run_kitty_test () {
	label=$1
	expected=$2
	csi_cmds=$3

	W=$($TMUX new-window -P -- sh -c \
		"stty raw -echo && printf '$csi_cmds' && cat -v")
	sleep 0.3
	actual=$($TMUX capturep -pt"$W" | head -1)
	$TMUX kill-window -t"$W" 2>/dev/null
	check_result "$label" "$expected" "$actual"
}

# Test 1: Push 2 entries, pop 100 — flags should be 1 (kitty-keys always base)
run_kitty_test "push2-pop100-flags-zero" "^[[?1u" \
	'\033[>3u\033[>7u\033[<100u\033[?u'

# Test 2: After the over-pop, push a new value and query — idx is sane
# Push 2, pop 100, then push flags=5, query should return 5
run_kitty_test "push2-pop100-push-recover" "^[[?5u" \
	'\033[>3u\033[>7u\033[<100u\033[>5u\033[?u'

# Test 3: Pop 100 from empty stack (no pushes) — should be 1 (kitty-keys always base)
run_kitty_test "pop100-from-empty" "^[[?1u" \
	'\033[<100u\033[?u'

# Test 4: Push exactly 8 (fill stack), pop 100 — all cleared, flags 1 (kitty-keys always base)
run_kitty_test "fill-stack-pop100" "^[[?1u" \
	'\033[>1u\033[>2u\033[>3u\033[>4u\033[>5u\033[>6u\033[>7u\033[>8u\033[<100u\033[?u'

# Test 5: Push 2, pop 100, push 3 new values, verify stack works normally
# Push flags 10, 20, 30, pop 1, query should return 20
run_kitty_test "overpop-then-normal-stack" "^[[?20u" \
	'\033[>3u\033[>7u\033[<100u\033[>10u\033[>20u\033[>30u\033[<u\033[?u'

# Test 6: Pop from base (no pushes), verify idx stays at 0
# Pop 5 from empty, push 1, pop 1, query should return 1 (kitty-keys always base)
run_kitty_test "pop-from-base-idx-stable" "^[[?1u" \
	'\033[<5u\033[>9u\033[<u\033[?u'

$TMUX kill-server 2>/dev/null
exit $exit_status
