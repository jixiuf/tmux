#!/bin/sh

# Test: kitty query (CSI ? u) must return the currently active flags,
# not the supported-capabilities mask.
#
# Bug: input_csi_dispatch_kitk_push() masks flags with
# KITTY_KBD_SUPPORTED (=0x01) so only disambiguate is ever stored.
# When an application pushes flags=3 (disambiguate | report_event),
# only flags=1 is stored. The query correctly reports what was stored
# but the stored value is wrong.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Ltest"
$TMUX kill-server 2>/dev/null
sleep 1

RED=$(printf '\033[31m')
GREEN=$(printf '\033[32m')
YELLOW=$(printf '\033[33m')
RESET=$(printf '\033[0m')

exit_status=0

TMPDIR=$(mktemp -d)
RESULT="$TMPDIR/result"
trap 'rm -rf "$TMPDIR"; $TMUX kill-server 2>/dev/null' EXIT

check_result () {
	label=$1
	expected=$2
	actual=$3
	xfail=$4

	if [ "$xfail" = "xfail" ]; then
		if [ "$actual" = "$expected" ]; then
			printf '%s[XPASS]%s %s -> %s\n' \
				"$RED" "$RESET" "$label" "$actual"
			exit_status=1
		else
			[ -n "$VERBOSE" ] || [ -n "$STRICT" ] && \
				printf '%s[XFAIL]%s %s -> expected %s, got %s\n' \
				"$YELLOW" "$RESET" "$label" "$expected" "$actual"
			[ -n "$STRICT" ] && exit_status=1
		fi
	elif [ "$actual" = "$expected" ]; then
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

# Python helper that pushes kitty flags=3, queries, and writes
# the reported flags to a file.
cat > "$TMPDIR/query.py" <<'PYEOF'
import sys, os, tty, termios, select, re, time

result_path = sys.argv[1]

fd = sys.stdin.fileno()
old = termios.tcgetattr(fd)
try:
    tty.setraw(fd)

    # Push kitty flags = 3 (disambiguate | report_event)
    os.write(1, b'\033[>3u')
    time.sleep(0.5)

    # Send query (CSI ? u)
    os.write(1, b'\033[?u')

    # Read response - expected format: ESC [ ? <flags> u
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
    if m:
        flags = m.group(1).decode()
    else:
        flags = 'NO_MATCH:' + repr(buf)

    with open(result_path, 'w') as f:
        f.write(flags)
finally:
    termios.tcsetattr(fd, termios.TCSADRAIN, old)
PYEOF

# Run the query script in a new window
$TMUX new-window -- python3 "$TMPDIR/query.py" "$RESULT"
sleep 3

if [ ! -f "$RESULT" ]; then
	printf '%s[FAIL]%s kitty-query-active-flags -> no result file\n' \
		"$RED" "$RESET"
	exit 1
fi

flags=$(cat "$RESULT")

# Expected: 3 (the flags we pushed)
# Push flags=3 (disambiguate|report_event), query should return 3
check_result "kitty-query-active-flags" "3" "$flags"

$TMUX kill-server 2>/dev/null
exit $exit_status
