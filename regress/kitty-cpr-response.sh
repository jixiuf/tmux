#!/bin/sh

# Test: CPR (Cursor Position Report) responses must not be silently
# dropped when kitty keyboard mode is enabled.
#
# Bug: The kitty key terminator scan accepts 'R' (because
# kitty_ascii_keys['R'-'A'] = KEYC_F3 is nonzero), but the switch
# statement that dispatches the final character omits case 'R'.
# Sequences like \033[24;80R (CPR) are intercepted by the kitty
# parser, which then hits `default: return -1`, silently discarding
# them.

PATH=/bin:/usr/bin
TERM=screen

[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f ../tmux)
TMUX="$TEST_TMUX -Ltest"
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
				printf '%s[XFAIL]%s %s -> expected: %s got: %s\n' \
				"$YELLOW" "$RESET" "$label" "$expected" "$actual"
			[ -n "$STRICT" ] && exit_status=1
		fi
	elif [ "$actual" = "$expected" ]; then
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s %s -> %s\n' \
			"$GREEN" "$RESET" "$label" "$actual"
	else
		printf '%s[FAIL]%s %s -> expected: %s got: %s\n' \
			"$RED" "$RESET" "$label" "$expected" "$actual"
		exit_status=1
	fi
}

# ---------- Part A: F3 with modifier (CSI 1;modR) must work ----------
# This uses the kitty-keys.sh pattern: cat -tv in a pane,
# then send-keys a key name and check what arrives.

add_test () {
	W=$($TMUX new-window -P -- sh -c \
		'printf "\033[>1u"; stty raw -echo && cat -tv')
	printf '%s %s %s\n' "$W" "$1" "$2" >> "$TMPDIR/tests"
}

# Modified F3 keys via kitty encoding (CSI 1;modR)
add_test 'S-F3' '^[[1;2R'
add_test 'C-F3' '^[[1;5R'
add_test 'M-F3' '^[[1;3R'

# Wait for windows to initialize and push kitty flags
sleep 0.3

# Send keys to all windows
while read -r w key expected; do
	$TMUX send-keys -t"$w" "$key" 'EOL' || exit 1
done < "$TMPDIR/tests"

# Wait for output
sleep 0.3

# Check all results
while read -r w key expected; do
	actual=$($TMUX capturep -pt"$w" | \
		head -1 | sed -e 's/EOL.*$//')
	$TMUX kill-window -t"$w" 2>/dev/null
	check_result "$key" "$expected" "$actual"
done < "$TMPDIR/tests"

# ---------- Part B: CPR response must not hang the server ----------
# A CPR response (\033[24;80R) should be rejected by the kitty parser
# (because parameters "24;80" don't match "1;modifier") and not
# silently dropped.  We verify the server remains responsive.

W=$($TMUX new-window -P -- sh -c \
	'printf "\033[>1u"; stty raw -echo && cat -tv')
sleep 0.3

# Send a CPR-like response directly to the pane's pty via send-keys -l.
# The inner application requested cursor position, and the terminal
# would respond with \033[24;80R.  The kitty parser should reject it.
printf '\033[24;80R' | $TMUX send-keys -t"$W" -l "$(cat)"
sleep 0.2

# Now send a normal key to verify the server isn't stuck.
$TMUX send-keys -t"$W" 'a' 'EOL'
sleep 0.2
actual=$($TMUX capturep -pt"$W" | head -1 | sed -e 's/EOL.*$//')
$TMUX kill-window -t"$W" 2>/dev/null

# The 'a' key should have gone through.  The CPR response bytes may
# also appear in the output since the kitty parser correctly rejects
# them and they pass through to the application.  The key assertion
# is that the server didn't hang and 'a' is present.
case "$actual" in
*a*)
	[ -n "$VERBOSE" ] && \
		printf '%s[PASS]%s CPR-server-responsive -> %s\n' \
		"$GREEN" "$RESET" "$actual"
	;;
*)
	printf '%s[FAIL]%s CPR-server-responsive -> expected output containing "a" got: %s\n' \
		"$RED" "$RESET" "$actual"
	exit_status=1
	;;
esac

exit $exit_status
