#!/bin/sh

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -f/dev/null -Ltest"
$TMUX kill-server 2>/dev/null

TMP=$(mktemp)
trap "rm -f $TMP" 0 1 15

$TMUX -f/dev/null new -d -x40 -y10 \
      "cat $TESTDIR/cursor-test.txt; printf '\e[9;15H'; cat" || exit 1
$TMUX set -g window-size manual || exit 1

$TMUX display -pF '#{cursor_x} #{cursor_y} #{cursor_character}' >>$TMP
$TMUX capturep -p|awk '{print NR-1,$0}' >>$TMP
$TMUX resizew -x10 || exit 1
$TMUX display -pF '#{cursor_x} #{cursor_y} #{cursor_character}' >>$TMP
$TMUX capturep -p|awk '{print NR-1,$0}' >>$TMP
$TMUX resizew -x50 || exit 1
$TMUX display -pF '#{cursor_x} #{cursor_y} #{cursor_character}' >>$TMP
$TMUX capturep -p|awk '{print NR-1,$0}' >>$TMP

$TMUX kill-server 2>/dev/null

if cmp -s $TMP "$TESTDIR/cursor-test1.result"; then
	[ -n "$VERBOSE" ] && echo "[PASS] cursor-test1"
	exit 0
else
	echo "[FAIL] cursor-test1 (capture-pane output differs)"
	diff $TMP "$TESTDIR/cursor-test1.result"
	exit 1
fi
