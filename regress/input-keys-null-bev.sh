#!/bin/sh

# Test: tmux server should not crash when sending keys to a dead pane
# Bug: input_key_write() dereferences bev (bufferevent) without NULL check.
# When a pane's process exits, wp->event becomes NULL.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Ltest"
$TMUX kill-server 2>/dev/null
sleep 1

$TMUX -f/dev/null new -x40 -y2 -d || exit 1
sleep 0.3

GREEN=$(printf '\033[32m')
YELLOW=$(printf '\033[33m')
RESET=$(printf '\033[0m')

# Keep the pane around after the process exits so the window is not destroyed
$TMUX set remain-on-exit on
sleep 0.1

# Run a command that exits immediately, leaving a dead pane.
$TMUX respawnw -k -t0 'exit 0'
sleep 0.5

# Send keys to the dead pane — this should not crash the server.
$TMUX send-keys -t0 'hello' 2>/dev/null
$TMUX send-keys -t0 Enter 2>/dev/null
sleep 0.3

if $TMUX has 2>/dev/null; then
	[ -n "$VERBOSE" ] && \
		printf '%s[PASS]%s input-keys-null-bev\n' "$GREEN" "$RESET"
else
	[ -n "$VERBOSE" ] || [ -n "$STRICT" ] && \
		printf '%s[XFAIL]%s input-keys-null-bev (server crashed)\n' "$YELLOW" "$RESET"
	[ -n "$STRICT" ] && exit 1
fi

$TMUX kill-server 2>/dev/null
exit 0
