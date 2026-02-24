#!/bin/sh

# Test: long modifier names (Control-, Meta-, Alt-) should be parsed correctly
# Bug: strncasecmp lengths in key_string_get_modifiers() are wrong,
# causing "Meta-" and "Alt-" to never match and "Control-" to match
# too broadly

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
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

assert_key 'Meta-a' '^[a'
assert_key 'Alt-a' '^[a'
assert_key 'Control-a' '^A'

# Long-form Super- and Hyper- modifiers
# In legacy mode, Super and Hyper are remapped to Meta
assert_key 'Super-a' '^[a'
assert_key 'Hyper-a' '^[a'

# Short-form equivalents must also work
assert_key 'M-a' '^[a'
assert_key 'A-a' '^[a'
assert_key 'C-a' '^A'
assert_key 'H-a' '^[a'

# "Control-" false positive: "ControXYa" should be rejected as unknown.
# With the bug, strncasecmp only checks 6 chars ("Contro") so it
# matches "Control-", advances 8 bytes, and parses "a" as C-a.
result=$($TMUX bind-key 'ControXYa' send-keys hello 2>&1)
if echo "$result" | grep -q "unknown key"; then
	[ -n "$VERBOSE" ] && \
		printf '%s[PASS]%s reject ControXYa -> unknown key\n' \
		"$GREEN" "$RESET"
else
	printf '%s[FAIL]%s reject ControXYa -> should be unknown key (Got: %s)\n' \
		"$RED" "$RESET" "$result"
	exit_status=1
fi

$TMUX kill-server 2>/dev/null

exit $exit_status
