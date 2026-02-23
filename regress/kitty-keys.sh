#!/bin/sh

PATH=/bin:/usr/bin
TERM=screen

[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f ../tmux)
TMUX="$TEST_TMUX -Ltest"
$TMUX kill-server 2>/dev/null
sleep 1
$TMUX -f/dev/null new -x20 -y2 -d || exit 1
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
# A. Key encoding with kitty-keys enabled
#
# All windows are created up front, then keys are sent and results
# checked in batch to avoid sequential sleeps.
#

$TMUX set -g kitty-keys always

add_kitty_test () {
	W=$($TMUX new-window -P -- sh -c \
		'printf "\033[>1u"; stty raw -echo && cat -tv')
	printf '%s %s %s %s\n' "$W" "$1" "$2" "$3" >> "$TMPDIR/kitty"
}

# Function keys (unmodified)
add_kitty_test 'F1' '^[[P'
add_kitty_test 'F2' '^[[Q'
add_kitty_test 'F3' '^[[R' xfail
add_kitty_test 'F4' '^[[S'
add_kitty_test 'F5' '^[[15~'
add_kitty_test 'F6' '^[[17~'
add_kitty_test 'F7' '^[[18~'
add_kitty_test 'F8' '^[[19~'
add_kitty_test 'F9' '^[[20~'
add_kitty_test 'F10' '^[[21~'
add_kitty_test 'F11' '^[[23~'
add_kitty_test 'F12' '^[[24~'

# Function keys with Shift modifier
add_kitty_test 'S-F1' '^[[1;2P'
add_kitty_test 'S-F2' '^[[1;2Q'
add_kitty_test 'S-F3' '^[[1;2R' xfail
add_kitty_test 'S-F4' '^[[1;2S'
add_kitty_test 'S-F5' '^[[15;2~'

# Function keys with Ctrl modifier
add_kitty_test 'C-F1' '^[[1;5P'
add_kitty_test 'C-F2' '^[[1;5Q'
add_kitty_test 'C-F3' '^[[1;5R' xfail
add_kitty_test 'C-F4' '^[[1;5S'

# Function keys with Alt modifier
add_kitty_test 'M-F3' '^[[1;3R' xfail

# Arrow keys (unmodified)
add_kitty_test 'Up' '^[[A'
add_kitty_test 'Down' '^[[B'
add_kitty_test 'Right' '^[[C'
add_kitty_test 'Left' '^[[D'

# Arrow keys with modifiers
add_kitty_test 'S-Up' '^[[1;2A'
add_kitty_test 'S-Down' '^[[1;2B'
add_kitty_test 'S-Right' '^[[1;2C'
add_kitty_test 'S-Left' '^[[1;2D'
add_kitty_test 'C-Up' '^[[1;5A'
add_kitty_test 'C-Down' '^[[1;5B'
add_kitty_test 'C-Right' '^[[1;5C'
add_kitty_test 'C-Left' '^[[1;5D'
add_kitty_test 'M-Up' '^[[1;3A'
add_kitty_test 'M-Down' '^[[1;3B'

# Special keys (unmodified)
add_kitty_test 'IC' '^[[2~'
add_kitty_test 'DC' '^[[3~'
add_kitty_test 'PPage' '^[[5~'
add_kitty_test 'NPage' '^[[6~'
add_kitty_test 'Home' '^[[H'
add_kitty_test 'End' '^[[F'

# Special keys with modifiers
add_kitty_test 'S-IC' '^[[2;2~'
add_kitty_test 'S-DC' '^[[3;2~'
add_kitty_test 'C-Home' '^[[1;5H'
add_kitty_test 'C-End' '^[[1;5F'
add_kitty_test 'S-PPage' '^[[5;2~'
add_kitty_test 'S-NPage' '^[[6;2~'
# Simple ASCII keys (unmodified, should pass through directly)
add_kitty_test 'a' 'a'
add_kitty_test 'z' 'z'
add_kitty_test '0' '0'
add_kitty_test '9' '9'

# Modified ASCII keys
add_kitty_test 'C-a' '^[[97;5u'
add_kitty_test 'C-z' '^[[122;5u'
add_kitty_test 'S-a' '^[[97;2u'
add_kitty_test 'M-a' '^[[97;3u'
add_kitty_test 'C-S-a' '^[[97;6u'

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
#
#
# B. Protocol query response
#

W=$($TMUX new-window -P -- sh -c \
	'stty raw -echo && printf "\033[?u" && cat -v')
sleep 0.3
actual=$($TMUX capturep -pt"$W" | head -1)
$TMUX kill-window -t"$W" || exit 1
check_result "query" "^[[?0u" "$actual"

#
# C. PUA character filtering (supplementary PUA should be dropped)
#
# Supplementary PUA characters from macOS (e.g., Cmd+Shift+{ in iTerm2)
# should be silently dropped and never reach the pane application.
#

# Test with kitty-keys on: PUA chars via send-keys -l should produce empty output
W=$($TMUX new-window -P -- sh -c \
	'printf "\033[>1u"; stty raw -echo && cat -tv')
sleep 0.3
# Send U+100001 (PUA-B) as literal UTF-8: F4 80 80 81
printf '\364\200\200\201' | $TMUX send-keys -t"$W" -l "$(cat)"
$TMUX send-keys -t"$W" 'EOL'
sleep 0.2
actual=$($TMUX capturep -pt"$W" | head -1 | sed -e 's/EOL.*$//')
$TMUX kill-window -t"$W" 2>/dev/null
check_result "PUA-B-drop-kitty" "" "$actual" xfail

# Test with kitty-keys on: U+F0001 (PUA-A) should also be dropped
W=$($TMUX new-window -P -- sh -c \
	'printf "\033[>1u"; stty raw -echo && cat -tv')
sleep 0.3
# Send U+F0001 (PUA-A) as literal UTF-8: F3 B0 80 81
printf '\363\260\200\201' | $TMUX send-keys -t"$W" -l "$(cat)"
$TMUX send-keys -t"$W" 'EOL'
sleep 0.2
actual=$($TMUX capturep -pt"$W" | head -1 | sed -e 's/EOL.*$//')
$TMUX kill-window -t"$W" 2>/dev/null
check_result "PUA-A-drop-kitty" "" "$actual" xfail

# Test that BMP PUA (U+E000, Nerd Fonts range) is NOT dropped
W=$($TMUX new-window -P -- sh -c \
	'printf "\033[>1u"; stty raw -echo && cat -tv')
sleep 0.3
# Send U+E000 (BMP PUA) as literal UTF-8: EE 80 80
printf '\356\200\200' | $TMUX send-keys -t"$W" -l "$(cat)"
$TMUX send-keys -t"$W" 'EOL'
sleep 0.2
actual=$($TMUX capturep -pt"$W" | head -1 | sed -e 's/EOL.*$//')
$TMUX kill-window -t"$W" 2>/dev/null
# BMP PUA should pass through (non-empty)
if [ -z "$actual" ]; then
	printf '%s[FAIL]%s BMP-PUA-passthrough -> should not be empty\n' \
		"$RED" "$RESET"
	exit_status=1
else
	[ -n "$VERBOSE" ] && \
		printf '%s[PASS]%s BMP-PUA-passthrough -> %s\n' \
		"$GREEN" "$RESET" "$actual"
fi

# Test that normal emoji (U+1F600) is NOT dropped
W=$($TMUX new-window -P -- sh -c \
	'printf "\033[>1u"; stty raw -echo && cat -tv')
sleep 0.3
# Send U+1F600 as literal UTF-8: F0 9F 98 80
printf '\360\237\230\200' | $TMUX send-keys -t"$W" -l "$(cat)"
$TMUX send-keys -t"$W" 'EOL'
sleep 0.2
actual=$($TMUX capturep -pt"$W" | head -1 | sed -e 's/EOL.*$//')
$TMUX kill-window -t"$W" 2>/dev/null
if [ -z "$actual" ]; then
	printf '%s[FAIL]%s emoji-passthrough -> should not be empty\n' \
		"$RED" "$RESET"
	exit_status=1
else
	[ -n "$VERBOSE" ] && \
		printf '%s[PASS]%s emoji-passthrough -> %s\n' \
		"$GREEN" "$RESET" "$actual"
fi

# Test with kitty-keys off: PUA chars should still be dropped
$TMUX set -g kitty-keys off
W=$($TMUX new-window -P -- sh -c 'stty raw -echo && cat -tv')
sleep 0.3
printf '\364\200\200\201' | $TMUX send-keys -t"$W" -l "$(cat)"
$TMUX send-keys -t"$W" 'EOL'
sleep 0.2
actual=$($TMUX capturep -pt"$W" | head -1 | sed -e 's/EOL.*$//')
$TMUX kill-window -t"$W" 2>/dev/null
check_result "PUA-B-drop-legacy" "" "$actual" xfail
$TMUX set -g kitty-keys always

#
# D. Legacy fallback (kitty-keys off)
#

$TMUX set -g kitty-keys off

add_legacy_test () {
	W=$($TMUX new-window -P -- sh -c 'stty raw -echo && cat -tv')
	printf '%s %s %s %s\n' "$W" "$1" "$2" "$3" >> "$TMPDIR/legacy"
}

add_legacy_test 'F1' '^[OP'
add_legacy_test 'F2' '^[OQ'
add_legacy_test 'F3' '^[OR'
add_legacy_test 'F4' '^[OS'
add_legacy_test 'Up' '^[[A'
add_legacy_test 'Down' '^[[B'
add_legacy_test 'Right' '^[[C'
add_legacy_test 'Left' '^[[D'
add_legacy_test 'a' 'a'
add_legacy_test 'z' 'z'
add_legacy_test 'C-a' '^A'
add_legacy_test 'C-z' '^Z'

sleep 0.2

while read -r w key expected xfail; do
	$TMUX send-keys -t"$w" "$key" 'EOL' || exit 1
done < "$TMPDIR/legacy"

sleep 0.3

while read -r w key expected xfail; do
	actual=$($TMUX capturep -pt"$w" | \
		head -1 | sed -e 's/EOL.*$//')
	$TMUX kill-window -t"$w" 2>/dev/null
	check_result "$key" "$expected" "$actual" "$xfail"
done < "$TMPDIR/legacy"

exit $exit_status
