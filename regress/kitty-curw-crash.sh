#!/bin/sh

# Test: tmux server should not crash when kitty keyboard handlers
# encounter a session with no current window
# Bug: input_csi_dispatch_kitk_{push,pop,set}() dereference
# c->session->curw without NULL check

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lkcwc"
$TMUX kill-server 2>/dev/null

TMP=$(mktemp)
trap "rm -f $TMP" 0 1 15

# Create session 0 — its window will be destroyed to trigger the bug.
$TMUX -f/dev/null new -d || exit 1

# Create session 1 — keeps the server alive and will push kitty flags.
$TMUX -f/dev/null new -d || exit 1

# Attach a control mode client to session 0 so that the client list
# includes a client whose session->curw will become NULL.
cat /dev/null | $TMUX -C a -t0: >$TMP 2>&1 &
CONTROL_PID=$!
sleep 1

# Kill the only window in session 0.  This leaves the control client
# attached to a session where curw is NULL.
$TMUX killw -t0:0

sleep 1

# Now push kitty keyboard flags from session 1's pane.  The handler
# iterates all clients and checks c->session->curw->window without
# verifying curw is non-NULL, crashing the server.
$TMUX send-keys -t1:0.0 "printf '\\033[>1u'" Enter

sleep 1

# If the server crashed, "has-session" will fail.
$TMUX has || exit 1

kill $CONTROL_PID 2>/dev/null
wait $CONTROL_PID 2>/dev/null
$TMUX kill-server 2>/dev/null

exit 0
