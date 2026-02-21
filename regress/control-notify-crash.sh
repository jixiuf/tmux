#!/bin/sh

# Test: tmux server should not crash when last pane in window closes
# with a control mode client attached.
#
# Exercises the control_notify_window_pane_changed() path by killing
# the active pane in a multi-pane window while a control client is
# subscribed to notifications.

PATH=/bin:/usr/bin
TERM=screen

[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f ../tmux)
TMUX="$TEST_TMUX -Ltest"
$TMUX kill-server 2>/dev/null

TMP=$(mktemp)
trap "rm -f $TMP" 0 1 15

$TMUX -f/dev/null new -d || exit 1

# Second session keeps the server alive.
$TMUX -f/dev/null new -d || exit 1

# Control mode client enables control_notify_* callbacks.
cat /dev/null | $TMUX -C a -t0: >$TMP 2>&1 &
CONTROL_PID=$!
sleep 1

# Split to get two panes, then kill the active pane.
$TMUX splitw -t0:0
$TMUX killp -t0:0.1

# Kill the last pane (goes through server_kill_window).
$TMUX killp -t0:0.0

sleep 1

if $TMUX has 2>/dev/null; then
	[ -n "$VERBOSE" ] && echo "[PASS] control-notify-crash"
else
	echo "[FAIL] control-notify-crash (server died)"
	kill $CONTROL_PID 2>/dev/null
	wait $CONTROL_PID 2>/dev/null
	exit 1
fi

kill $CONTROL_PID 2>/dev/null
wait $CONTROL_PID 2>/dev/null
$TMUX kill-server 2>/dev/null

exit 0
