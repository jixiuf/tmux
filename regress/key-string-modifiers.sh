#!/bin/sh

# Test: long modifier names (Control-, Meta-, Alt-) should be parsed correctly
# Bug: strncasecmp lengths in key_string_get_modifiers() are wrong,
# causing "Meta-" and "Alt-" to never match and "Control-" to match
# too broadly

PATH=/bin:/usr/bin
TERM=screen

[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f ../tmux)
TMUX="$TEST_TMUX -Ltest"
$TMUX kill-server 2>/dev/null
sleep 1

$TMUX -f/dev/null new -x40 -y2 -d 'stty raw -echo && cat -tv' || exit 1
sleep 0.5

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

assert_key () {
	$TMUX respawnw -k -t0 'stty raw -echo && cat -tv' 2>/dev/null
	sleep 0.2
	$TMUX send-keys "$1" 'EOL'
	sleep 0.3
	actual=$($TMUX capturep -pt0 | head -1 | sed -e 's/EOL.*$//')
	check_result "$1" "$2" "$actual" "$3"
}

assert_key 'Meta-a' '^[a' xfail
assert_key 'Alt-a' '^[a' xfail
assert_key 'Control-a' '^A'

$TMUX kill-server 2>/dev/null

exit $exit_status
