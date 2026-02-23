#!/bin/sh

PATH=/bin:/usr/bin
TERM=screen

[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f ../tmux)
TMUX="$TEST_TMUX -Ltest"
$TMUX kill-server 2>/dev/null

$TMUX new -d

exit_status=0
n=0

# Create all test windows up front, sleep once, then check results.
# Each window prints an OSC 11 colour sequence and holds open with sleep.

add_test() {
	W=$($TMUX new-window -P "printf '$1'; sleep 999")
	eval "test_win_$n=\"$W\""
	eval "test_seq_$n=\"$1\""
	eval "test_exp_$n=\"$2\""
	n=$((n + 1))
}

# Basic colour formats.
add_test '\033]11;rgb:ff/ff/ff\007' '#ffffff'
add_test '\033]11;rgb:ff/ff/ff\007\033]111\007' 'default'
add_test '\033]11;cmy:0.9373/0.6941/0.4549\007' '#0f4e8b'
add_test '\033]11;cmyk:0.88/0.44/0.00/0.45\007' '#104e8c'

# Numeric, hex, and named colour formats.
add_test '\033]11;16,78,139\007' '#104e8b'
add_test '\033]11;#104E8B\007' '#104e8b'
add_test '\033]11;#10004E008B00\007' '#104e8b'
add_test '\033]11;DodgerBlue4\007' '#104e8b'
add_test '\033]11;DodgerBlue4    \007' '#104e8b'
add_test '\033]11;    DodgerBlue4\007' '#104e8b'
add_test '\033]11;rgb:10/4E/8B\007' '#104e8b'
add_test '\033]11;rgb:1000/4E00/8B00\007' '#104e8b'

# Grey/gray 0-100: X11 rgb.txt uses (int)(N * 2.55 + 0.5) in C, which
# depends on IEEE 754 double rounding, so we need awk for correctness.
for variant in grey gray; do
	add_test "\033]11;$variant\007" '#bebebe'
	i=0
	while [ "$i" -le 100 ]; do
		expected=$(awk "BEGIN { v = int($i * 2.55 + 0.5); printf \"#%02x%02x%02x\", v, v, v }")
		add_test "\033]11;$variant$i\007" "$expected"
		i=$((i + 1))
	done
done

# All windows are created; wait once for escape sequences to be processed.
sleep 2

# Now check all results.
i=0
while [ "$i" -lt "$n" ]; do
	eval "W=\$test_win_$i"
	eval "seq=\$test_seq_$i"
	eval "expected=\$test_exp_$i"
	c=$($TMUX display -t"$W" -p '#{pane_bg}')
	if [ "$c" != "$expected" ]; then
		echo "[FAIL] $seq -> expected $expected (Got: $c)"
		exit_status=1
	fi
	[ -n "$VERBOSE" ] && echo "[PASS] $seq -> $expected"
	i=$((i + 1))
done

$TMUX -f/dev/null kill-server 2>/dev/null
exit $exit_status
