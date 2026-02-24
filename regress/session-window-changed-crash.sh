#!/bin/sh

# Test: tmux server should not crash when session-window-changed fires
# after the session's last window has been destroyed.
#
# Exercises control_notify_session_window_changed() by switching the
# active window and immediately destroying all windows in the session
# while a control client is attached.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Ltest"
$TMUX kill-server 2>/dev/null

TMP=$(mktemp)
trap "rm -f $TMP" 0 1 15

# Session 0 with two windows.
$TMUX -f/dev/null new -x40 -y2 -d || exit 1
$TMUX neww || exit 1

# Session 1 keeps the server alive.
$TMUX -f/dev/null new -d || exit 1

# Control client on session 0 enables control_notify_* callbacks.
cat /dev/null | $TMUX -C a -t0: >$TMP 2>&1 &
CONTROL_PID=$!
sleep 1

# Batch: switch window then kill both. The session-window-changed
# notification is queued asynchronously and delivered after all
# windows are destroyed.
$TMUX selectw -t0:1 \; killw -t0:1 \; killw -t0:0

sleep 1

if $TMUX has 2>/dev/null; then
	[ -n "$VERBOSE" ] && echo "[PASS] session-window-changed-crash"
else
	echo "[FAIL] session-window-changed-crash (server died)"
	kill $CONTROL_PID 2>/dev/null
	wait $CONTROL_PID 2>/dev/null
	exit 1
fi

kill $CONTROL_PID 2>/dev/null
wait $CONTROL_PID 2>/dev/null
$TMUX kill-server 2>/dev/null

exit 0
