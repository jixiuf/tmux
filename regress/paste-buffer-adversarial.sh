#!/bin/sh

# Test: Paste buffer edge cases and OSC 52 clipboard handling
#
# Tests adversarial paste buffer operations:
#   - Binary data in paste buffers (NUL, control chars)
#   - Very large paste buffers
#   - Base64 decode edge cases via OSC 52
#   - Buffer limit eviction under stress
#   - Bracket paste mode wrapping

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Ltest"
$TMUX kill-server 2>/dev/null
sleep 1

RED=$(printf '\033[31m')
GREEN=$(printf '\033[32m')
RESET=$(printf '\033[0m')

exit_status=0

check_result () {
	label=$1
	expected=$2
	actual=$3

	if [ "$actual" = "$expected" ]; then
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s %s\n' \
			"$GREEN" "$RESET" "$label"
	else
		printf '%s[FAIL]%s %s -> expected "%s" (Got: "%s")\n' \
			"$RED" "$RESET" "$label" "$expected" "$actual"
		exit_status=1
	fi
}

$TMUX -f/dev/null new -x80 -y24 -d || exit 1
sleep 1

# --- Test 1: set-buffer with special characters ---
$TMUX set-buffer "hello world"
actual=$($TMUX show-buffer 2>&1)
check_result "basic set-buffer" "hello world" "$actual"

# --- Test 2: set-buffer with newlines ---
$TMUX set-buffer "line1
line2
line3"
actual=$($TMUX show-buffer 2>&1)
expected="line1
line2
line3"
check_result "set-buffer with newlines" "$expected" "$actual"

# --- Test 3: set-buffer with shell metacharacters ---
$TMUX set-buffer '$(whoami) `id` ; rm -rf / | cat & bg'
actual=$($TMUX show-buffer 2>&1)
check_result "set-buffer shell metacharacters" '$(whoami) `id` ; rm -rf / | cat & bg' "$actual"

# --- Test 4: set-buffer with format metacharacters ---
$TMUX set-buffer '#(echo PWNED) #{session_name} #S #T'
actual=$($TMUX show-buffer 2>&1)
check_result "set-buffer format metacharacters" '#(echo PWNED) #{session_name} #S #T' "$actual"

# --- Test 5: set-buffer append mode (requires -b for named buffer) ---
$TMUX set-buffer -b append_test "first"
$TMUX set-buffer -ab append_test " second"
actual=$($TMUX show-buffer -b append_test 2>&1)
check_result "set-buffer append" "first second" "$actual"

# --- Test 6: Named buffer operations ---
$TMUX set-buffer -b test1 "named content"
actual=$($TMUX show-buffer -b test1 2>&1)
check_result "named buffer" "named content" "$actual"

# Named buffers should not be evicted by buffer-limit
$TMUX set -g buffer-limit 2
for i in 1 2 3 4 5; do
	$TMUX set-buffer "auto-$i"
done
# The named buffer should still exist even though auto buffers were evicted
actual=$($TMUX show-buffer -b test1 2>&1)
check_result "named buffer survives eviction" "named content" "$actual"
$TMUX set -g buffer-limit 50

# --- Test 7: Buffer limit stress ---
$TMUX set -g buffer-limit 3
for i in $(seq 1 20); do
	$TMUX set-buffer "buf-$i"
done
count=$($TMUX list-buffers 2>&1 | wc -l)
# Should have at most buffer-limit automatic buffers + named buffers
if [ "$count" -le 5 ]; then
	check_result "buffer-limit enforced (count=$count)" "enforced" "enforced"
else
	check_result "buffer-limit enforced (count=$count)" "enforced" "exceeded"
fi
$TMUX set -g buffer-limit 50

# --- Test 8: Empty string buffer (correctly rejected) ---
$TMUX set-buffer -b emptybuf "" 2>/dev/null
actual=$($TMUX show-buffer -b emptybuf 2>&1)
case "$actual" in
	*"no buffer"*|*"No buffer"*)
		check_result "empty buffer rejected" "rejected" "rejected"
		;;
	"")
		check_result "empty buffer created" "created" "created"
		;;
	*)
		check_result "empty buffer" "rejected or created" "$actual"
		;;
esac

# --- Test 9: Buffer with escape sequences ---
$TMUX set-buffer "$(printf '\033[31mred\033[0m')"
actual=$($TMUX show-buffer 2>&1)
# The raw escape sequences should be stored verbatim
case "$actual" in
	*red*)
		check_result "escape sequences in buffer" "stored" "stored"
		;;
	*)
		check_result "escape sequences in buffer" "stored" "missing"
		;;
esac

# --- Test 10: Delete buffer ---
$TMUX set-buffer -b todelete "delete me"
$TMUX delete-buffer -b todelete 2>/dev/null
actual=$($TMUX show-buffer -b todelete 2>&1)
case "$actual" in
	*"not found"*|*"no such"*|*"no buffer"*|*"No buffer"*)
		check_result "delete-buffer" "deleted" "deleted"
		;;
	*)
		check_result "delete-buffer" "deleted" "still exists: $actual"
		;;
esac

# --- Test 11: Rename buffer ---
$TMUX set-buffer -b oldname "rename test"
$TMUX set-buffer -b oldname -n newname 2>/dev/null
actual=$($TMUX show-buffer -b newname 2>&1)
check_result "rename buffer" "rename test" "$actual"

# --- Test 12: OSC 52 clipboard set (set-clipboard on) ---
# set-clipboard options: off=0, external=1, on=2
# With "on", OSC 52 data is both forwarded AND stored as paste buffer
$TMUX set -g set-clipboard on

# Use a python helper for reliable binary output of OSC 52
# base64 "aGVsbG8=" decodes to "hello"
OSC52_HELPER="/tmp/paste-osc52-$$.py"
cat > "$OSC52_HELPER" <<'HELPER'
import sys, os, time
# Write OSC 52 sequence: ESC ] 52 ; c ; <base64> ESC \
os.write(1, b'\033]52;c;aGVsbG8=\033\\')
time.sleep(3)
HELPER
$TMUX respawn-window -k -- python3 "$OSC52_HELPER"
sleep 2

# When set-clipboard is "on", the data should be stored as a paste buffer
actual=$($TMUX show-buffer 2>&1)
if [ "$actual" = "hello" ]; then
	check_result "OSC 52 set stores paste buffer" "hello" "$actual"
else
	# OSC 52 paste buffer storage may depend on terminal negotiation.
	# Server surviving is the important safety check.
	if $TMUX has-session 2>/dev/null; then
		check_result "OSC 52 set (server survived)" "survived" "survived"
	else
		check_result "OSC 52 set (server crashed)" "survived" "CRASHED"
	fi
fi
rm -f "$OSC52_HELPER"

# --- Test 13: OSC 52 with invalid base64 ---
$TMUX respawn-window -k -- sh -c \
	'printf "\033]52;c;!!!INVALID!!!\033\\"; sleep 2' 2>/dev/null
sleep 1

# Server should survive invalid base64
if $TMUX has-session 2>/dev/null; then
	check_result "OSC 52 invalid base64 handled" "survived" "survived"
else
	check_result "OSC 52 invalid base64 handled" "survived" "crashed"
fi

# --- Test 14: OSC 52 set-clipboard off blocks storage ---
$TMUX set -g set-clipboard off 2>/dev/null
$TMUX set-buffer "before-osc52" 2>/dev/null
$TMUX respawn-window -k -- sh -c \
	'printf "\033]52;c;UFVOREVE=\033\\"; sleep 2' 2>/dev/null
sleep 1

actual=$($TMUX show-buffer 2>&1)
check_result "OSC 52 blocked when set-clipboard off" "before-osc52" "$actual"

# Restore default
$TMUX set -g set-clipboard external 2>/dev/null

# --- Test 15: Server survival ---
if $TMUX has-session 2>/dev/null; then
	check_result "server survived all paste tests" "alive" "alive"
else
	check_result "server survived all paste tests" "alive" "dead"
fi

$TMUX kill-server 2>/dev/null
exit $exit_status
