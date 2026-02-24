#!/bin/sh

# Test: Adversarial edge cases for kitty key parser
#
# Targets specific parser code paths identified during security audit:
#   - strsep parsing with pathological delimiters
#   - Modifier bits beyond standard range
#   - txt[] field overflow attempt
#   - Letter-final forms with edge-case modifiers
#   - Mixed valid/invalid sequences to test state recovery
#   - Negative-like values via unsigned wraparound
#   - Partial sequences followed by valid ones

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Ladvers"
$TMUX kill-server 2>/dev/null
sleep 1

RED=$(printf '\033[31m')
GREEN=$(printf '\033[32m')
RESET=$(printf '\033[0m')

exit_status=0

$TMUX -f/dev/null new -x80 -y24 -d || exit 1
sleep 1
$TMUX set -g escape-time 0
$TMUX set -g kitty-keys always

$TMUX respawn-window -k -- sh -c \
	'printf "\033[>1u"; stty raw -echo && cat -v'
sleep 0.5

python3 - "$TEST_TMUX" <<'PYEOF'
import pty, os, sys, time, signal, struct, fcntl, termios, select

tmux_bin = sys.argv[1]
master, slave = pty.openpty()

attrs = termios.tcgetattr(slave)
attrs[0] &= ~(termios.IGNBRK | termios.BRKINT | termios.PARMRK |
              termios.ISTRIP | termios.INLCR | termios.IGNCR |
              termios.ICRNL | termios.IXON)
attrs[1] &= ~termios.OPOST
attrs[2] &= ~(termios.CSIZE | termios.PARENB)
attrs[2] |= termios.CS8
attrs[3] &= ~(termios.ECHO | termios.ECHONL | termios.ICANON |
              termios.ISIG | termios.IEXTEN)
attrs[6][termios.VMIN] = 1
attrs[6][termios.VTIME] = 0
termios.tcsetattr(slave, termios.TCSANOW, attrs)

winsize = struct.pack('HHHH', 24, 80, 0, 0)
fcntl.ioctl(slave, termios.TIOCSWINSZ, winsize)

pid = os.fork()
if pid == 0:
    os.close(master)
    os.setsid()
    fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
    os.dup2(slave, 0)
    os.dup2(slave, 1)
    os.dup2(slave, 2)
    os.close(slave)
    os.environ['TERM'] = 'xterm-256color'
    os.execvp(tmux_bin, [tmux_bin, '-Ladvers', 'attach'])
else:
    os.close(slave)

    def drain(timeout=0.5):
        deadline = time.time() + timeout
        while time.time() < deadline:
            r, _, _ = select.select([master], [], [], 0.05)
            if r:
                try:
                    os.read(master, 65536)
                except OSError:
                    break

    time.sleep(1.5)
    drain(0.5)

    # Enable kitty parser
    os.write(master, b'\033[?1u')
    time.sleep(0.5)
    drain(0.5)
    os.write(master, b'\033[?1u')
    time.sleep(0.5)
    drain(0.5)

    # --- Adversarial sequences ---

    # 1. txt[] overflow: more than 5 colon-separated values in text field
    os.write(master, b'\033[97;1;48:49:50:51:52:53:54:55:56:57u')
    time.sleep(0.1)

    # 2. Modifier with all kitty bits set (255 = all 8 bits)
    os.write(master, b'\033[97;256u')
    time.sleep(0.1)

    # 3. Modifier value exactly at 32-bit boundary (4294967295)
    os.write(master, b'\033[97;4294967295u')
    time.sleep(0.1)

    # 4. Codepoint 0xD800 (UTF-16 surrogate, invalid Unicode)
    os.write(master, b'\033[55296u')
    time.sleep(0.1)

    # 5. Codepoint 0xFFFE (noncharacter)
    os.write(master, b'\033[65534u')
    time.sleep(0.1)

    # 6. Letter-final with modifier 256 (all bits set)
    os.write(master, b'\033[1;256A')
    time.sleep(0.1)

    # 7. Letter-final 'R' (CSI R is also CPR response) with modifiers
    os.write(master, b'\033[1;2R')
    time.sleep(0.1)

    # 8. Partial sequence then valid: send CSI then wait, then complete
    os.write(master, b'\033[')
    time.sleep(0.15)
    os.write(master, b'97;1u')
    time.sleep(0.1)

    # 9. Many colons in key code field (pathological strsep)
    os.write(master, b'\033[97:::::::u')
    time.sleep(0.1)

    # 10. Release event (evtype=3) for a modifier-only key
    os.write(master, b'\033[57441;1:3u')
    time.sleep(0.1)

    # 11. Event type beyond valid range (evtype=99)
    os.write(master, b'\033[97;1:99u')
    time.sleep(0.1)

    # 12. Tilde-final with invalid key number
    os.write(master, b'\033[999;2~')
    time.sleep(0.1)

    # 13. Rapid interleaved valid and invalid
    for _ in range(50):
        os.write(master, b'\033[BOGUS')
        os.write(master, b'\033[97;1u')
    time.sleep(0.3)

    # 14. NUL bytes within escape sequence
    os.write(master, b'\033[\x0097;1u')
    time.sleep(0.1)

    # 15. Valid end marker
    os.write(master, b'Z')
    time.sleep(0.5)

    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        pass
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass
    os.close(master)
PYEOF

sleep 0.5

# Check tmux survived
if $TMUX has-session 2>/dev/null; then
	[ -n "$VERBOSE" ] && printf '%s[PASS]%s server survived adversarial kitty input\n' \
		"$GREEN" "$RESET"
else
	printf '%s[FAIL]%s server crashed on adversarial kitty input\n' \
		"$RED" "$RESET"
	exit_status=1
fi

# Check pane is functional
actual=$($TMUX capturep -pt0:0.0 2>/dev/null)
case "$actual" in
	*Z*)
		[ -n "$VERBOSE" ] && printf '%s[PASS]%s end marker received (pane functional)\n' \
			"$GREEN" "$RESET"
		;;
	*)
		printf '%s[FAIL]%s no end marker (pane may be broken): %s\n' \
			"$RED" "$RESET" "$(echo "$actual" | head -3)"
		exit_status=1
		;;
esac

$TMUX kill-server 2>/dev/null
exit $exit_status
