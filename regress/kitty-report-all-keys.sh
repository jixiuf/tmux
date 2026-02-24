#!/bin/sh

# Test: kitty REPORT_ALL (flag 8) should encode all keys as CSI u
#
# When the REPORT_ALL flag (0x08) is set, even unmodified ASCII keys
# should be sent as CSI codepoint u sequences, not raw characters.
#
# Bug (fixed): input_key_kitty() returned early for unmodified ASCII
# keys before checking the all_as_escapes flag. Fixed by adding
# !all_as_escapes guard to the early return.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lkrak"
$TMUX kill-server 2>/dev/null
sleep 1

$TMUX -f/dev/null new -x20 -y2 -d || exit 1
sleep 1
$TMUX set -g escape-time 0
$TMUX set -g kitty-keys always

RED=$(printf '\033[31m')
GREEN=$(printf '\033[32m')
RESET=$(printf '\033[0m')

exit_status=0

check_result () {
	label=$1
	expected=$2
	actual=$3

	# Use prefix matching: with REPORT_ALL, the EOL marker sent via
	# send-keys is also CSI-u encoded, so exact equality doesn't work.
	case "$actual" in
	"$expected"*)
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s %s -> %s\n' \
			"$GREEN" "$RESET" "$label" "$actual"
		;;
	*)
		printf '%s[FAIL]%s %s -> expected %s, got %s\n' \
			"$RED" "$RESET" "$label" "$expected" "$actual"
		exit_status=1
		;;
	esac
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"; $TMUX kill-server 2>/dev/null' EXIT

add_test () {
	# Push flags=9 (DISAMBIGUATE|REPORT_ALL = 0x01|0x08)
	W=$($TMUX new-window -P -- sh -c \
		'printf "\033[>9u"; stty raw -echo && cat -tv')
	printf '%s %s %s %s\n' "$W" "$1" "$2" "$3" >> "$TMPDIR/tests"
}

# Unmodified 'a' with REPORT_ALL: should be CSI 97 u, not raw 'a'
add_test 'a' '^[[97u'

# Unmodified 'z' with REPORT_ALL: should be CSI 122 u
add_test 'z' '^[[122u'

# Unmodified '0' with REPORT_ALL: should be CSI 48 u
add_test '0' '^[[48u'

# Unmodified space with REPORT_ALL: should be CSI 32 u
add_test 'Space' '^[[32u'

# Modified key should still work correctly (Ctrl-a = CSI 97;5u)
add_test 'C-a' '^[[97;5u'

# Unmodified Tab with REPORT_ALL: should be CSI 9 u (not raw tab)
add_test 'Tab' '^[[9u'

# Unmodified Enter with REPORT_ALL: should be CSI 13 u (not raw CR)
add_test 'Enter' '^[[13u'

# Unicode: ä (U+00E4) with REPORT_ALL: should be CSI 228 u
add_test 'ä' '^[[228u'

# Unicode: 世 (U+4E16) with REPORT_ALL: should be CSI 19990 u
add_test '世' '^[[19990u'

sleep 0.3

while read -r w key expected xfail; do
	$TMUX send-keys -t"$w" "$key" 'EOL' || exit 1
done < "$TMPDIR/tests"

sleep 0.3

while read -r w key expected xfail; do
	actual=$($TMUX capturep -pt"$w" | \
		head -1 | sed -e 's/EOL.*$//')
	$TMUX kill-window -t"$w" 2>/dev/null
	check_result "report-all-$key" "$expected" "$actual" "$xfail"
done < "$TMPDIR/tests"

exit $exit_status
