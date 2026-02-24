#!/bin/sh

# Test that multi-modifier key combinations produce correct CSI u
# encoding in kitty keyboard mode.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lksmo"
$TMUX kill-server 2>/dev/null
sleep 1
$TMUX -f/dev/null new -x80 -y2 -d || exit 1
sleep 1
$TMUX set -g escape-time 0

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
		printf '%s[FAIL]%s %s -> %s (Got: %s)\n' \
			"$RED" "$RESET" "$label" "$expected" "$actual"
		exit_status=1
	fi
}

$TMUX set -g kitty-keys always

add_kitty_test () {
	W=$($TMUX new-window -P -- sh -c \
		'printf "\033[>1u"; stty raw -echo && cat -tv')
	printf '%s %s %s\n' "$W" "$1" "$2" >> "$TMPDIR/kitty"
}

# Ctrl+Shift+Alt (modifier = 1 + 1 + 2 + 4 = 8)
add_kitty_test 'C-S-M-a' '^[[97;8u'

# Ctrl+Alt (modifier = 1 + 2 + 4 = 7)
add_kitty_test 'C-M-a' '^[[97;7u'

# Shift+Alt (modifier = 1 + 1 + 2 = 4)
add_kitty_test 'S-M-a' '^[[97;4u'

# Ctrl+Shift+Alt with another key
add_kitty_test 'C-S-M-z' '^[[122;8u'

# Ctrl+Shift+Alt with a digit
add_kitty_test 'C-S-M-1' '^[[49;8u'

# Wait for all windows to initialize and push kitty flags
sleep 0.3

# Send keys to all windows
while read -r w key expected; do
	$TMUX send-keys -t"$w" "$key" 'EOL' || exit 1
done < "$TMPDIR/kitty"

# Wait for output
sleep 0.3

# Check all results
while read -r w key expected; do
	actual=$($TMUX capturep -pt"$w" | \
		head -1 | sed -e 's/EOL.*$//')
	$TMUX kill-window -t"$w" 2>/dev/null
	check_result "$key" "$expected" "$actual"
done < "$TMPDIR/kitty"

exit $exit_status
