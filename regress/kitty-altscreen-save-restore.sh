#!/bin/sh

# Test: kitty keyboard state is saved/restored across alternate screen
#
# Verifies that screen_alternate_on() saves the kitty_kbd state and
# screen_alternate_off() restores it. An application that pushes flags,
# enters alternate screen, modifies flags, then exits alternate screen
# should see its original flags restored.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lkalt"
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

# Python helper:
# 1. Push flags=5 (disambiguate|report_alternate), query
# 2. Enter alternate screen, push flags=1 (disambiguate), query
# 3. Exit alternate screen, query (should restore flags=5)
cat > "$TMPDIR/altscreen.py" <<'PYEOF'
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
results = []
try:
    tty.setraw(fd)

    # 1. Push flags=5 (disambiguate=1 + report_alternate=4)
    os.write(1, b'\033[>5u')
    time.sleep(0.3)
    results.append(query_flags(fd))

    # 2. Enter alternate screen
    os.write(1, b'\033[?1049h')
    time.sleep(0.3)

    # 3. Push flags=1 (just disambiguate) in alternate screen
    os.write(1, b'\033[>1u')
    time.sleep(0.3)
    results.append(query_flags(fd))

    # 4. Exit alternate screen — should restore pre-alternate state
    os.write(1, b'\033[?1049l')
    time.sleep(0.3)
    results.append(query_flags(fd))

    with open(result_path, 'w') as f:
        f.write(','.join(results))
finally:
    termios.tcsetattr(fd, termios.TCSADRAIN, old)
PYEOF

$TMUX new-window -- python3 "$TMPDIR/altscreen.py" "$RESULT"
sleep 5

if [ ! -f "$RESULT" ]; then
	printf '%s[FAIL]%s kitty-altscreen -> no result file\n' \
		"$RED" "$RESET"
	exit 1
fi

result=$(cat "$RESULT")

# Parse comma-separated results: before_alt,in_alt,after_alt
before_alt=$(echo "$result" | cut -d, -f1)
in_alt=$(echo "$result" | cut -d, -f2)
after_alt=$(echo "$result" | cut -d, -f3)

# Before alternate screen: flags should be 5 (what we pushed)
check_result "before-altscreen: flags=5" "5" "$before_alt"

# In alternate screen after push: flags should be 1
check_result "in-altscreen: flags=1" "1" "$in_alt"

# After exiting alternate screen: flags should be restored to 5
check_result "after-altscreen: flags=5 (restored)" "5" "$after_alt"

$TMUX kill-server 2>/dev/null
exit $exit_status
