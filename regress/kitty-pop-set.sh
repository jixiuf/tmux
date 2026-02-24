#!/bin/sh

# Test: kitty keyboard protocol push/pop/set handlers
#
# Verifies:
# - Push multiple levels, query returns correct flags
# - Pop reduces stack correctly
# - Set with mode 1 (replace), mode 2 (OR), mode 3 (clear bits)
# - Over-pop clamps to stack size

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lkpset"
$TMUX kill-server 2>/dev/null
sleep 1

$TMUX -f/dev/null new -x80 -y24 -d || exit 1
sleep 1
$TMUX set -g escape-time 0
$TMUX set -g kitty-keys always

RED=$(printf '\033[31m')
GREEN=$(printf '\033[32m')
YELLOW=$(printf '\033[33m')
RESET=$(printf '\033[0m')

exit_status=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"; $TMUX kill-server 2>/dev/null' EXIT

check_result () {
	label=$1
	expected=$2
	actual=$3
	xfail=$4

	if [ "$xfail" = "xfail" ]; then
		if [ "$actual" = "$expected" ]; then
			printf '%s[XPASS]%s %s -> %s\n' \
				"$RED" "$RESET" "$label" "$actual"
			exit_status=1
		else
			[ -n "$VERBOSE" ] || [ -n "$STRICT" ] && \
				printf '%s[XFAIL]%s %s -> expected %s, got %s\n' \
				"$YELLOW" "$RESET" "$label" "$expected" "$actual"
			[ -n "$STRICT" ] && exit_status=1
		fi
	elif [ "$actual" = "$expected" ]; then
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s %s -> %s\n' \
			"$GREEN" "$RESET" "$label" "$actual"
	else
		printf '%s[FAIL]%s %s -> expected %s, got %s\n' \
			"$RED" "$RESET" "$label" "$expected" "$actual"
		exit_status=1
	fi
}

# Helper: run a sequence of CSI commands in a fresh window and capture
# the query response.
run_kitty_test () {
	label=$1
	expected=$2
	csi_cmds=$3
	xfail=$4

	W=$($TMUX new-window -P -- sh -c \
		"stty raw -echo && printf '$csi_cmds' && cat -v")
	sleep 0.3
	actual=$($TMUX capturep -pt"$W" | head -1)
	$TMUX kill-window -t"$W" 2>/dev/null
	check_result "$label" "$expected" "$actual" "$xfail"
}

# Test 1: Push flags=3, query should return 3
run_kitty_test "push-3-query" "^[[?3u" \
	'\033[>3u\033[?u'

# Test 2: Push flags=1, push flags=5, query returns 5 (top of stack)
run_kitty_test "push-1-push-5-query" "^[[?5u" \
	'\033[>1u\033[>5u\033[?u'

# Test 3: Push flags=1, push flags=5, pop 1, query returns 1
run_kitty_test "push-pop-query" "^[[?1u" \
	'\033[>1u\033[>5u\033[<u\033[?u'

# Test 4: Push flags=3, pop 1, query returns 1 (kitty-keys always base)
run_kitty_test "push-pop-empty" "^[[?1u" \
	'\033[>3u\033[<u\033[?u'

# Test 5: Push 3 levels, pop 2 levels, query returns first push
run_kitty_test "push3-pop2-query" "^[[?1u" \
	'\033[>1u\033[>3u\033[>7u\033[<2u\033[?u'

# Test 6: Set mode 1 (replace) — push 0, set flags=5 mode 1
run_kitty_test "set-replace" "^[[?5u" \
	'\033[>0u\033[=5;1u\033[?u'

# Test 7: Set mode 2 (OR bits) — push flags=1, set flags=8 mode 2
# Result: 1 | 8 = 9
run_kitty_test "set-or" "^[[?9u" \
	'\033[>1u\033[=8;2u\033[?u'

# Test 8: Set mode 3 (clear bits) — push flags=15, set flags=6 mode 3
# Result: 15 & ~6 = 9
run_kitty_test "set-clear" "^[[?9u" \
	'\033[>15u\033[=6;3u\033[?u'

# Test 9: Over-pop (pop 100 from stack with only 1 push) should not crash
# and should leave flags at 1 (kitty-keys always base)
run_kitty_test "over-pop" "^[[?1u" \
	'\033[>3u\033[<100u\033[?u'

# Test 10: Alternate screen save/restore
# Push flags=3, enter alt screen, push flags=15, exit alt screen, query
# Flags should be restored to 3 (pre-alternate-screen value)
run_kitty_test "alt-screen-restore" "^[[?3u" \
	'\033[>3u\033[?1049h\033[>15u\033[?1049l\033[?u'

$TMUX kill-server 2>/dev/null
exit $exit_status
