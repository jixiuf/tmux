#!/bin/sh

# Test: kitty keyboard state is cleared when a new process starts in a pane
#
# Verifies that screen_reinit() clears both kitty_kbd and saved_kitty_kbd
# when the process in a pane exits and a new one starts. An application
# that pushes kitty flags, then exits, should not leave stale flags for
# the next process.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lkrinit"
$TMUX kill-server 2>/dev/null
sleep 1

RED=$(printf '\033[31m')
GREEN=$(printf '\033[32m')
RESET=$(printf '\033[0m')

exit_status=0

TMPDIR=$(mktemp -d)
RESULT="$TMPDIR/result"
trap 'rm -rf "$TMPDIR"; $TMUX kill-server 2>/dev/null' EXIT

check_result () {
	label=$1
	expected=$2
	actual=$3

	if [ "$actual" = "$expected" ]; then
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s %s -> %s\n' \
			"$GREEN" "$RESET" "$label" "$actual"
	else
		printf '%s[FAIL]%s %s -> expected %s, got %s\n' \
			"$RED" "$RESET" "$label" "$expected" "$actual"
		exit_status=1
	fi
}

$TMUX -f/dev/null new -x80 -y24 -d || exit 1
sleep 1
$TMUX set -g kitty-keys always
$TMUX set -g remain-on-exit on

cat > "$TMPDIR/reinit_test.py" <<'PYEOF'
import sys, os, tty, termios, select, re, time

result_path = sys.argv[1]

def query_flags(fd):
    """Send CSI ? u and parse response CSI ? <flags> u."""
    os.write(1, b'\033[?u')
    buf = b''
    for _ in range(50):
        r, _, _ = select.select([fd], [], [], 2.0)
        if not r:
            break
        ch = os.read(fd, 1)
        buf += ch
        if ch == b'u' and b'\033[?' in buf:
            break
    m = re.search(rb'\033\[\?(\d+)u', buf)
    return m.group(1).decode() if m else 'NO_MATCH'

fd = sys.stdin.fileno()
old = termios.tcgetattr(fd)
try:
    tty.setraw(fd)

    # Query initial flags — with kitty-keys=always, should be 1
    initial = query_flags(fd)

    # Push flags=7
    os.write(1, b'\033[>7u')
    time.sleep(0.3)
    after_push = query_flags(fd)

    with open(result_path, 'w') as f:
        f.write(','.join([initial, after_push]))
finally:
    termios.tcsetattr(fd, termios.TCSADRAIN, old)
PYEOF

# Phase 1: Push flags in a window, then let the process exit
W=$($TMUX new-window -PF '#{pane_id}' -- python3 "$TMPDIR/reinit_test.py" "$RESULT")
sleep 5

if [ ! -f "$RESULT" ]; then
	printf '%s[FAIL]%s phase 1 -> no result file\n' \
		"$RED" "$RESET"
	exit 1
fi

result1=$(cat "$RESULT")
initial=$(echo "$result1" | cut -d, -f1)
after_push=$(echo "$result1" | cut -d, -f2)

check_result "initial-flags=1 (always mode)" "1" "$initial"
check_result "after-push: flags=7" "7" "$after_push"

# Phase 2: The process exited. The pane should have had screen_reinit()
# called which clears kitty state. Start a new process in the same
# pane and verify the state is clean.
rm -f "$RESULT"
sleep 2

# respawn-pane starts a new process in the same pane
$TMUX respawn-pane -t"$W" -k python3 "$TMPDIR/reinit_test.py" "$RESULT"
sleep 5

if [ ! -f "$RESULT" ]; then
	printf '%s[FAIL]%s phase 2 -> no result file\n' \
		"$RED" "$RESET"
	exit 1
fi

result2=$(cat "$RESULT")
initial2=$(echo "$result2" | cut -d, -f1)

# After respawn, kitty state should be clean (1 from always mode, not 7)
check_result "after-respawn: flags=1 (cleared)" "1" "$initial2"

$TMUX kill-server 2>/dev/null
exit $exit_status
