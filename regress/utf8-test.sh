#!/bin/sh

PATH=/bin:/usr/bin
TERM=screen

[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f ../tmux)
TMUX="$TEST_TMUX -Ltest"
TMP=$(mktemp)
trap "rm -f $TMP" 0 1 15
$TMUX kill-server 2>/dev/null

$TMUX -f/dev/null \
	  set -g remain-on-exit on \; \
	  set -g remain-on-exit-format '' \; \
      new -d -- cat UTF-8-test.txt
sleep 1
$TMUX capturep -pCeJS- >$TMP
$TMUX kill-server

if cmp -s $TMP utf8-test.result; then
	[ -n "$VERBOSE" ] && echo "[PASS] UTF-8 rendering"
	exit 0
else
	echo "[FAIL] UTF-8 rendering (capture-pane output differs)"
	exit 1
fi
