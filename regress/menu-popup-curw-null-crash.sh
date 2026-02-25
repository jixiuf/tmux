#!/bin/sh

# Test: tmux server should not crash when s->curw is NULL during
# menu_reapply_styles() or popup_reapply_styles().
#
# Bug: menu_reapply_styles() (menu.c) and popup_reapply_styles() (popup.c)
# checked s == NULL but not s->curw == NULL before dereferencing
# s->curw->window->options.  When the session's current window is destroyed
# while a menu or popup overlay is active, curw becomes NULL and the next
# overlay redraw segfaults the server.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Ltest-mpcw"
$TMUX kill-server 2>/dev/null
sleep 0.5

# Session keepalive: keeps the server alive so we can test for crashes.
$TMUX -f/dev/null new -x40 -y10 -d -s keepalive || exit 1
sleep 0.3

RC=0

# -----------------------------------------------------------------------
# Test 1: popup open, then curw goes NULL
# -----------------------------------------------------------------------
# Create a target session with one window.
$TMUX -f/dev/null new -x40 -y10 -d -s target || exit 1
sleep 0.3

# Open a popup on the target session (runs sleep so the popup stays open).
$TMUX display-popup -t target: -d /tmp -- sleep 5 2>/dev/null &
POPUP_PID=$!
sleep 0.3

# Destroy all windows in target session — curw becomes NULL while popup
# may still be pending a redraw.
$TMUX killw -t target:0 2>/dev/null
sleep 0.5

# If the server survived, keepalive session is still there.
if $TMUX has -t keepalive 2>/dev/null; then
	[ -n "$VERBOSE" ] && echo "PASS: server survived popup with curw=NULL"
else
	echo "FAIL: server crashed (popup curw=NULL dereference)"
	RC=1
fi

kill $POPUP_PID 2>/dev/null
wait $POPUP_PID 2>/dev/null
$TMUX kill-session -t target 2>/dev/null

# -----------------------------------------------------------------------
# Test 2: display-menu open, then curw goes NULL via control client
# -----------------------------------------------------------------------
$TMUX -f/dev/null new -x80 -y24 -d -s target2 || exit 1
sleep 0.3

# Attach a control client to target2 so we can generate redraws.
$TMUX -CC attach -t target2 -d >/dev/null 2>&1 &
CC_PID=$!
sleep 0.3

# Open a menu overlay via send-keys to display-menu (non-blocking).
$TMUX display-menu -t target2: -x 5 -y 5 \
	'Item1' '' '' \
	'Item2' '' '' \
	2>/dev/null &
MENU_PID=$!
sleep 0.3

# Kill the current window — curw becomes NULL while menu overlay
# might still be scheduled for a redraw.
$TMUX killw -t target2:0 2>/dev/null
sleep 0.5

if $TMUX has -t keepalive 2>/dev/null; then
	[ -n "$VERBOSE" ] && echo "PASS: server survived menu with curw=NULL"
else
	echo "FAIL: server crashed (menu curw=NULL dereference)"
	RC=1
fi

kill $MENU_PID 2>/dev/null
wait $MENU_PID 2>/dev/null
kill $CC_PID 2>/dev/null
wait $CC_PID 2>/dev/null
$TMUX kill-session -t target2 2>/dev/null

$TMUX kill-server 2>/dev/null
exit $RC
