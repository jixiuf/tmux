#!/bin/sh

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Ltest"
$TMUX kill-server 2>/dev/null

for i in "$TESTDIR"/conf/*.conf; do
	$TMUX -f/dev/null start \; source -n $i || exit 1
done

exit 0
