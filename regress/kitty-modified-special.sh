#!/bin/sh

# Test: Modified Tab, Enter, and Backspace should get CSI u encoding in kitty mode
# Bug: input_key_kitty() returns -1 for Meta+Tab, Meta+Enter, Meta+Bspace
# because the fallthrough check masks off META but not other modifiers,
# causing these keys to fall through to legacy ESC-prefix encoding
# instead of proper CSI u encoding.

PATH=/bin:/usr/bin
TERM=screen

[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f ../tmux)
TMUX="$TEST_TMUX -Ltest"
$TMUX kill-server 2>/dev/null
sleep 1
$TMUX -f/dev/null new -x40 -y2 -d || exit 1
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
				printf '%s[XFAIL]%s %s -> expected "%s", got "%s"\n' \
				"$YELLOW" "$RESET" "$label" "$expected" "$actual"
			[ -n "$STRICT" ] && exit_status=1
		fi
	elif [ "$actual" = "$expected" ]; then
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s %s -> %s\n' \
			"$GREEN" "$RESET" "$label" "$actual"
	else
		printf '%s[FAIL]%s %s -> expected "%s", got "%s"\n' \
			"$RED" "$RESET" "$label" "$expected" "$actual"
		exit_status=1
	fi
}

assert_key () {
	$TMUX respawnw -k -t0 'printf "\033[>1u"; stty raw -echo && cat -tv' \
		2>/dev/null
	sleep 0.3
	$TMUX send-keys "$1" 'EOL'
	sleep 0.3
	actual=$($TMUX capturep -pt0 | head -1 | sed -e 's/EOL.*$//')
	check_result "$1" "$2" "$actual" "$3"
}

# Meta+Tab should be CSI 9;3u — legacy produces ESC + Tab (^[^I)
assert_key 'M-Tab' '^[[9;3u' xfail

# Meta+Enter should be CSI 13;3u — legacy produces ESC + CR (^[^M)
assert_key 'M-Enter' '^[[13;3u' xfail

# Meta+BSpace should be CSI 127;3u — legacy produces ESC + DEL (^[^?)
assert_key 'M-BSpace' '^[[127;3u' xfail

# Ctrl+Tab should be CSI 9;5u
assert_key 'C-Tab' '^[[9;5u'

# Unmodified Tab should still use legacy encoding
assert_key 'Tab' '^I'

# Unmodified Enter should still use legacy encoding
assert_key 'Enter' '^M'

$TMUX kill-server 2>/dev/null

exit $exit_status
