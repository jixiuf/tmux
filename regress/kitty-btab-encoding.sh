#!/bin/sh

# Test: KEYC_BTAB (legacy backtab) encoded correctly for kitty protocol (T-024)
#
# Bug: input_key_kitty() has no case for KEYC_BTAB. When a pane has kitty
# keyboard protocol active and receives KEYC_BTAB (from legacy CSI Z input),
# the function returns -1 (fallback to legacy). The pane gets CSI Z instead
# of the correct kitty encoding CSI 9;2u (Tab with Shift).
#
# Fix: Convert KEYC_BTAB to Tab(9) | KEYC_SHIFT early in input_key_kitty().
#
# This test runs a Python helper inside a pane that pushes kitty keyboard
# flags via stdout and captures what it receives on stdin after send-keys BTab.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Ltest"
$TMUX kill-server 2>/dev/null

WORKDIR=$(mktemp -d) || exit 1
trap '$TMUX kill-server 2>/dev/null; rm -rf "$WORKDIR"' EXIT

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
			printf '%s[PASS]%s %s -> %s\n' \
			"$GREEN" "$RESET" "$label" "$actual"
	else
		printf '%s[FAIL]%s %s -> expected %s (Got: %s)\n' \
			"$RED" "$RESET" "$label" "$expected" "$actual"
		exit_status=1
	fi
}

HELPER="$WORKDIR/helper.py"
OUTFILE="$WORKDIR/out.txt"

# Create the Python helper that pushes kitty flags then reads stdin.
cat > "$HELPER" << PYEOF
import sys, os, select, termios, tty

# Push kitty keyboard flags via stdout (disambiguate=0x01).
sys.stdout.buffer.write(b'\033[>1u')
sys.stdout.buffer.flush()

# Signal readiness.
open('$WORKDIR/ready', 'w').close()

# Switch stdin to raw mode so bytes pass through unmodified.
fd = sys.stdin.fileno()
old_attrs = termios.tcgetattr(fd)
tty.setraw(fd)

# Wait for data with a timeout, then read it.
data = b''
if select.select([fd], [], [], 5.0)[0]:
    # Read initial data.
    data = os.read(fd, 1024)
    # Drain any remaining bytes.
    while select.select([fd], [], [], 0.5)[0]:
        more = os.read(fd, 1024)
        if not more:
            break
        data += more

# Restore terminal settings.
termios.tcsetattr(fd, termios.TCSANOW, old_attrs)

# Write hex-encoded bytes to the output file.
with open('$OUTFILE', 'w') as f:
    f.write(data.hex())
PYEOF

$TMUX -f/dev/null new -x80 -y24 -d 2>/dev/null || exit 1

# Wait for server.
n=0; while [ $n -lt 50 ] && ! $TMUX info >/dev/null 2>&1; do sleep 0.1; n=$((n+1)); done

$TMUX set -g escape-time 0 2>/dev/null
$TMUX set -g kitty-keys always 2>/dev/null

# Run the Python helper in the pane.
$TMUX send-keys "unset PROMPT_COMMAND; PS1='$ '" Enter
sleep 0.3
$TMUX send-keys "python3 $HELPER" Enter

# Wait for helper to signal readiness.
n=0; while [ $n -lt 50 ] && [ ! -f "$WORKDIR/ready" ]; do sleep 0.1; n=$((n+1)); done
sleep 0.5

# Send BTab (Shift+Tab). Internally this is KEYC_BTAB.
$TMUX send-keys BTab

# Wait for the Python script to write output.
n=0; while [ $n -lt 80 ] && [ ! -f "$OUTFILE" ]; do sleep 0.1; n=$((n+1)); done

# Read the hex-encoded output.
output=$(cat "$OUTFILE" 2>/dev/null)

# CSI 9;2u = \033[9;2u = hex: 1b5b393b3275
case "$output" in
	*1b5b393b3275*)
		check_result "BTab encoded as CSI 9;2u for kitty pane" "found" "found"
		;;
	*1b5b5a*)
		check_result "BTab encoded as CSI 9;2u for kitty pane" \
			"CSI 9;2u (1b5b393b3275)" \
			"CSI Z (1b5b5a) — legacy fallback"
		;;
	*)
		check_result "BTab encoded as CSI 9;2u for kitty pane" \
			"CSI 9;2u (1b5b393b3275)" \
			"other ($output)"
		;;
esac

exit $exit_status
