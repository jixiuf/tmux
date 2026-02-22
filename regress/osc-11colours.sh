#!/bin/sh

PATH=/bin:/usr/bin
TERM=screen

[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f ../tmux)
TMUX="$TEST_TMUX -Ltest"
$TMUX kill-server 2>/dev/null

$TMUX new -d
$TMUX set -g remain-on-exit on

exit_status=0

do_test() {
	$TMUX splitw "printf '$1'"
	sleep 0.25
	c="$($TMUX display -p '#{pane_bg}')"
	$TMUX kill-pane
	if [ "$c" != "$2" ]; then
		echo "[FAIL] $1 -> expected $2 (Got: $c)"
		exit_status=1
		return 1
	fi
	[ -n "$VERBOSE" ] && echo "[PASS] $1 -> $2"
	return 0
}

# Basic colour formats.
do_test '\033]11;rgb:ff/ff/ff\007' '#ffffff'
do_test '\033]11;rgb:ff/ff/ff\007\033]111\007' 'default'
do_test '\033]11;cmy:0.9373/0.6941/0.4549\007' '#0f4e8b'
do_test '\033]11;cmyk:0.88/0.44/0.00/0.45\007' '#104e8c'

# Numeric, hex, and named colour formats.
do_test '\033]11;16,78,139\007' '#104e8b'
do_test '\033]11;#104E8B\007' '#104e8b'
do_test '\033]11;#10004E008B00\007' '#104e8b'
do_test '\033]11;DodgerBlue4\007' '#104e8b'
do_test '\033]11;DodgerBlue4    \007' '#104e8b'
do_test '\033]11;    DodgerBlue4\007' '#104e8b'
do_test '\033]11;rgb:10/4E/8B\007' '#104e8b'
do_test '\033]11;rgb:1000/4E00/8B00\007' '#104e8b'

# Grey/gray 0-100: X11 rgb.txt uses (int)(N * 2.55 + 0.5) in C, which
# depends on IEEE 754 double rounding, so we need awk for correctness.
test_greys() {
	do_test "\033]11;$1\007" '#bebebe'
	i=0
	while [ "$i" -le 100 ]; do
		expected=$(awk "BEGIN { v = int($i * 2.55 + 0.5); printf \"#%02x%02x%02x\", v, v, v }")
		do_test "\033]11;$1$i\007" "$expected"
		i=$((i + 1))
	done
}
test_greys grey
test_greys gray

$TMUX -f/dev/null kill-server 2>/dev/null
exit $exit_status
