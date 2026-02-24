#!/bin/sh

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Ltest"
$TMUX kill-server 2>/dev/null

TMP=$(mktemp)
trap "rm -f $TMP" 0 1 15

$TMUX -f/dev/null new -d -x10 -y10 \
      "cat $TESTDIR/cursor-test.txt; printf '\e[8;10H'; cat" || exit 1
$TMUX set -g window-size manual || exit 1

# Wait for the printf '\e[8;10H' to execute, placing the cursor at
# row 8 col 10 (0-indexed: y=7 x=9). This avoids a race between the
# command startup and the first capture.
retries=0
while [ "$($TMUX display -pF '#{cursor_y}')" != "7" ] \
      && [ "$retries" -lt 50 ]; do
	sleep 0.05
	retries=$((retries + 1))
done

$TMUX display -pF '#{cursor_x} #{cursor_y} #{cursor_character}' >>$TMP
$TMUX capturep -p|awk '{print NR-1,$0}' >>$TMP
$TMUX resizew -x5 || exit 1
$TMUX display -pF '#{cursor_x} #{cursor_y} #{cursor_character}' >>$TMP
$TMUX capturep -p|awk '{print NR-1,$0}' >>$TMP
$TMUX resizew -x50 || exit 1
$TMUX display -pF '#{cursor_x} #{cursor_y} #{cursor_character}' >>$TMP
$TMUX capturep -p|awk '{print NR-1,$0}' >>$TMP

cmp -s $TMP "$TESTDIR/cursor-test2.result" || exit 1

$TMUX kill-server 2>/dev/null
exit 0
