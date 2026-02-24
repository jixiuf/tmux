#!/bin/sh

# 4476
# run-shell should go to stdout if present without -t

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Ltest"
$TMUX kill-server 2>/dev/null

TMP=$(mktemp)
trap "rm -f $TMP" 0 1 15

# Poll until a condition file has expected content.
wait_for_content () {
	n=0
	while [ $n -lt 30 ]; do
		[ "$(cat "$1" 2>/dev/null)" = "$2" ] && return 0
		sleep 0.2
		n=$((n+1))
	done
	return 1
}

# Poll until a pane enters view-mode.
wait_for_view_mode () {
	target=${1:-}
	n=0
	while [ $n -lt 30 ]; do
		if [ -n "$target" ]; then
			mode=$($TMUX display -p -t"$target" '#{pane_mode}' 2>/dev/null)
		else
			mode=$($TMUX display -p '#{pane_mode}' 2>/dev/null)
		fi
		[ "$mode" = "view-mode" ] && return 0
		sleep 0.2
		n=$((n+1))
	done
	return 1
}

# Test 1: run-shell without -t sends output to stdout (redirected to TMP).
$TMUX -f/dev/null new -d "$TMUX run 'echo foo' >$TMP; sleep 10" || exit 1
wait_for_content "$TMP" "foo" || exit 1

# Test 2: run-shell with -t: displays output in target pane (view-mode),
# NOT on stdout. Use a named session so we can target it with display -p.
# Clear TMP first — test 1 wrote "foo" to it, and the pane's >$TMP redirect
# is asynchronous (may not have truncated TMP yet when we check).
> $TMP
$TMUX new -d -sruntest "$TMUX run -t: 'echo foo' >$TMP; sleep 10" || exit 1
wait_for_view_mode "runtest:" || exit 1
[ "$(cat $TMP)" = "" ] || exit 1

$TMUX kill-server 2>/dev/null

exit 0
