#!/bin/sh

# Test that keypad keys produce correct kitty modifier values.
# Regression test for signed char overflow in get_modifier():
# KEYC_KEYPAD (0x80) in a signed char becomes -128, and after ++
# becomes -127, which sign-extends to ~4 billion when returned as u_int.

PATH=/bin:/usr/bin
TERM=screen

[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f ../tmux)
TMUX="$TEST_TMUX -Ltest-kpmod"
$TMUX kill-server 2>/dev/null
sleep 1
$TMUX -f/dev/null new -x40 -y2 -d || exit 1
sleep 1
$TMUX set -g escape-time 0

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
				printf '%s[XFAIL]%s %s -> %s (Got: %s)\n' \
				"$YELLOW" "$RESET" "$label" "$expected" "$actual"
			[ -n "$STRICT" ] && exit_status=1
		fi
	elif [ "$actual" = "$expected" ]; then
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s %s -> %s\n' \
			"$GREEN" "$RESET" "$label" "$actual"
	else
		printf '%s[FAIL]%s %s -> %s (Got: %s)\n' \
			"$RED" "$RESET" "$label" "$expected" "$actual"
		exit_status=1
	fi
}

#
# Test keypad keys in kitty keyboard mode.
# The KEYC_KEYPAD flag (0x80) must produce modifier=129 (0x80+1),
# NOT a huge number from signed char overflow.
#

$TMUX set -g kitty-keys always

add_kitty_test () {
	W=$($TMUX new-window -P -- sh -c \
		'printf "\033[>1u"; stty raw -echo && cat -tv')
	printf '%s %s %s %s\n' "$W" "$1" "$2" "$3" >> "$TMPDIR/kitty"
}

# KP0 unmodified: keypad codepoint, no modifiers (;modifier omitted)
add_kitty_test 'KP0' '^[[57399u'

# KP5 unmodified: keypad codepoint, no modifiers
add_kitty_test 'KP5' '^[[57404u'

# KPEnter unmodified: keypad codepoint, no modifiers
add_kitty_test 'KPEnter' '^[[57414u'

# KP+ with Shift: shift only -> modifier = 0x01 + 1 = 2
add_kitty_test 'S-KP+' '^[[57413;2u'

# KP/ with Ctrl: ctrl only -> modifier = 0x04 + 1 = 5
add_kitty_test 'C-KP/' '^[[57410;5u'

# Wait for all windows to initialize and push kitty flags
sleep 0.3

# Send keys to all windows
while read -r w key expected xfail; do
	$TMUX send-keys -t"$w" "$key" 'EOL' || exit 1
done < "$TMPDIR/kitty"

# Wait for output
sleep 0.3

# Check all results
while read -r w key expected xfail; do
	actual=$($TMUX capturep -pt"$w" | \
		head -1 | sed -e 's/EOL.*$//')
	$TMUX kill-window -t"$w" 2>/dev/null
	check_result "$key" "$expected" "$actual" "$xfail"
done < "$TMPDIR/kitty"

exit $exit_status
