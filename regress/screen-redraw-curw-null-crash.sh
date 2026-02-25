#!/bin/sh

# Test: tmux server should not crash in screen_redraw_screen() or
# screen_redraw_pane() when ctx->c is NULL (i.e. session->curw is NULL).
#
# Bug: screen_redraw_set_context() zeroes the ctx struct (setting ctx->c=NULL)
# when c->session==NULL or c->session->curw==NULL.  The callers
# screen_redraw_screen() and screen_redraw_pane() then passed the zeroed ctx
# to screen_redraw_update() which immediately dereferenced ctx->c->session
# without a NULL check, causing a segfault.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Ltest-srnull"
$TMUX kill-server 2>/dev/null
sleep 0.5

# Keepalive session: survives the target session being destroyed.
$TMUX -f/dev/null new -x40 -y10 -d -s keepalive || exit 1
sleep 0.3

RC=0

# -----------------------------------------------------------------------
# Test 1: force a screen redraw while curw is NULL
# -----------------------------------------------------------------------
# Create a target session.
$TMUX -f/dev/null new -x40 -y10 -d -s target || exit 1
sleep 0.3

# Attach a control-mode client; this registers an overlay_draw and keeps
# a client attached that will receive redraw requests.
$TMUX -CC attach -t target -d >/dev/null 2>&1 &
CC_PID=$!
sleep 0.3

# Add a second window so we can kill window 0 without destroying the session.
$TMUX neww -t target: || exit 1
sleep 0.1

# Kill window 0 — curw moves to window 1 (still non-NULL here).
# Now kill window 1 — curw becomes NULL, session still exists briefly.
$TMUX killw -t target:0 2>/dev/null
$TMUX killw -t target:1 2>/dev/null

# Give the event loop time to process and fire any pending redraws.
sleep 0.5

if $TMUX has -t keepalive 2>/dev/null; then
	[ -n "$VERBOSE" ] && echo "PASS: server survived screen_redraw with curw=NULL"
else
	echo "FAIL: server crashed (screen_redraw curw=NULL dereference)"
	RC=1
fi

kill $CC_PID 2>/dev/null
wait $CC_PID 2>/dev/null
$TMUX kill-session -t target 2>/dev/null

$TMUX kill-server 2>/dev/null
exit $RC
