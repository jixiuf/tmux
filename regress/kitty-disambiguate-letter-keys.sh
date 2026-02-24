#!/bin/sh

# Test: kitty disambiguate mode should send CSI 1;1R for unmodified F3
#
# The kitty keyboard protocol's disambiguate flag (flag 1) exists
# specifically to resolve ambiguities like F3 (CSI R) vs CPR (CSI R).
# In disambiguate mode, letter-final keys (F1-F4, cursor keys) should
# always include the number and modifier fields, even when unmodified.
#
# Unmodified F3 in disambiguate mode:
#   Expected:  CSI 1;1R  (disambiguated, always includes number;modifier)
#   Actual:    CSI R     (legacy, ambiguous with CPR)

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lkdlk"
$TMUX kill-server 2>/dev/null
sleep 1

$TMUX -f/dev/null new -x20 -y2 -d || exit 1
sleep 1
$TMUX set -g escape-time 0
$TMUX set -g kitty-keys always

RED=$(printf '\033[31m')
GREEN=$(printf '\033[32m')
YELLOW=$(printf '\033[33m')
RESET=$(printf '\033[0m')

exit_status=0

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

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"; $TMUX kill-server 2>/dev/null' EXIT

add_test () {
	W=$($TMUX new-window -P -- sh -c \
		'printf "\033[>1u"; stty raw -echo && cat -tv')
	printf '%s %s %s %s\n' "$W" "$1" "$2" "$3" >> "$TMPDIR/tests"
}

# F3 unmodified: the key ambiguity this flag is designed to fix
add_test 'F3' '^[[1;1R'

# F1 unmodified: same category (letter-final key)
add_test 'F1' '^[[1;1P'

# F2 unmodified
add_test 'F2' '^[[1;1Q'

# F4 unmodified
add_test 'F4' '^[[1;1S'

# Modified F3 should already work (Shift-F3 = CSI 1;2R)
add_test 'S-F3' '^[[1;2R'

# Cursor keys: spec says they should also use CSI 1;1X format
add_test 'Up' '^[[1;1A'
add_test 'Home' '^[[1;1H'
add_test 'End' '^[[1;1F'

# Modified cursor keys should already work
add_test 'S-Up' '^[[1;2A'

sleep 0.3

while read -r w key expected xfail; do
	$TMUX send-keys -t"$w" "$key" 'EOL' || exit 1
done < "$TMPDIR/tests"

sleep 0.3

while read -r w key expected xfail; do
	actual=$($TMUX capturep -pt"$w" | \
		head -1 | sed -e 's/EOL.*$//')
	$TMUX kill-window -t"$w" 2>/dev/null
	check_result "disambiguate-$key" "$expected" "$actual" "$xfail"
done < "$TMPDIR/tests"

exit $exit_status
