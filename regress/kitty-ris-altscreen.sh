#!/bin/sh

# Test: RIS (ESC c) in alternate screen clears kitty state but
# exiting alternate screen restores saved state.
#
# Verifies that screen_write_reset() clears kitty_kbd but NOT
# saved_kitty_kbd, so alternate screen exit still restores properly.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lkris"
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

cat > "$TMPDIR/ris_altscreen.py" <<'PYEOF'
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

    # 1. Push flags=5 (disambiguate=1 + report_alternate=4), query
    os.write(1, b'\033[>5u')
    time.sleep(0.3)
    results.append(query_flags(fd))  # should be 5

    # 2. Enter alternate screen
    os.write(1, b'\033[?1049h')
    time.sleep(0.3)

    # 3. Push flags=3 in alternate screen, query
    os.write(1, b'\033[>3u')
    time.sleep(0.3)
    results.append(query_flags(fd))  # should be 3

    # 4. Send RIS (ESC c) — clears kitty_kbd but NOT saved_kitty_kbd
    os.write(1, b'\033c')
    time.sleep(0.3)

    # 5. Re-enable raw mode (RIS resets terminal settings)
    tty.setraw(fd)
    time.sleep(0.1)

    # 6. Query flags after RIS — should be 0 (cleared)
    results.append(query_flags(fd))  # should be 0

    # 7. Exit alternate screen — should restore saved state (flags=5)
    os.write(1, b'\033[?1049l')
    time.sleep(0.3)
    results.append(query_flags(fd))  # should be 5

    with open(result_path, 'w') as f:
        f.write(','.join(results))
finally:
    termios.tcsetattr(fd, termios.TCSADRAIN, old)
PYEOF

$TMUX new-window -- python3 "$TMPDIR/ris_altscreen.py" "$RESULT"
sleep 7

if [ ! -f "$RESULT" ]; then
	printf '%s[FAIL]%s kitty-ris-altscreen -> no result file\n' \
		"$RED" "$RESET"
	exit 1
fi

result=$(cat "$RESULT")

# Parse comma-separated results
before_alt=$(echo "$result" | cut -d, -f1)
in_alt=$(echo "$result" | cut -d, -f2)
after_ris=$(echo "$result" | cut -d, -f3)
after_exit=$(echo "$result" | cut -d, -f4)

# Before alternate screen: flags should be 5
check_result "before-altscreen: flags=5" "5" "$before_alt"

# In alternate screen: flags should be 3
check_result "in-altscreen: flags=3" "3" "$in_alt"

# After RIS in alternate screen: flags should be 0 (cleared)
check_result "after-RIS: flags=0" "0" "$after_ris"

# After exiting alternate screen: saved state should restore to 5
check_result "after-exit-altscreen: flags=5 (restored)" "5" "$after_exit"

$TMUX kill-server 2>/dev/null
exit $exit_status
