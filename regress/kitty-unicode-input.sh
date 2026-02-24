#!/bin/sh

# Test: non-ASCII Unicode characters received via kitty CSI u sequences
# must be correctly converted from UTF-32 codepoint to UTF-8 and delivered
# to the pane application.
#
# This tests the utf8_fromwc() + utf8_from_data() conversion path in
# tty_keys_kitty_key().

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lkuni"
$TMUX kill-server 2>/dev/null
sleep 1

RED=$(printf '\033[31m')
GREEN=$(printf '\033[32m')
YELLOW=$(printf '\033[33m')
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
    os.execvp(tmux_bin, [tmux_bin, '-Lkuni', 'attach'])
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

    # Inject kitty capability response
    os.write(master, b'\033[?1u')
    time.sleep(0.5)
    drain(0.5)
    os.write(master, b'\033[?1u')
    time.sleep(0.5)
    drain(0.5)

    # Test 1: a-umlaut (U+00E4 = 228) via CSI 228 u
    os.write(master, b'\033[228u')
    time.sleep(0.2)

    # Test 2: CJK character (U+4E16 = 19990, "世") via CSI 19990 u
    os.write(master, b'\033[19990u')
    time.sleep(0.2)

    # Test 3: Emoji (U+1F600 = 128512, "😀") via CSI 128512 u
    os.write(master, b'\033[128512u')
    time.sleep(0.2)

    # End marker
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

actual=$($TMUX capturep -pt0:0.0 | head -1)

check_result () {
	label=$1
	expected=$2
	xfail=$3

	if [ "$xfail" = "xfail" ]; then
		case "$actual" in
		*"$expected"*)
			printf '%s[XPASS]%s %s found in output\n' \
				"$RED" "$RESET" "$label"
			exit_status=1
			;;
		*)
			[ -n "$VERBOSE" ] || [ -n "$STRICT" ] && \
				printf '%s[XFAIL]%s %s not found in output (got: %s)\n' \
				"$YELLOW" "$RESET" "$label" "$actual"
			[ -n "$STRICT" ] && exit_status=1
			;;
		esac
	else
		case "$actual" in
		*"$expected"*)
			[ -n "$VERBOSE" ] && \
				printf '%s[PASS]%s %s found in output\n' \
				"$GREEN" "$RESET" "$label"
			;;
		*)
			printf '%s[FAIL]%s %s not found in output (got: %s)\n' \
				"$RED" "$RESET" "$label" "$actual"
			exit_status=1
			;;
		esac
	fi
}

# cat -v renders:
# U+00E4 (ä) as M-CM-$  (two bytes: 0xC3 0xA4 → 0xC3 = M-C, 0xA4 = M-$)
# U+4E16 (世) as the character itself (cat -v passes through multi-byte)
# U+1F600 (😀) similarly

# For non-ASCII, cat -v renders bytes > 127 with M- prefix.
# ä = C3 A4 → cat -v: M-CM-$
check_result "a-umlaut (U+00E4)" "M-CM-$"
# 世 = E4 B8 96 → cat -v: M-dM-8M-^V
check_result "CJK U+4E16"        "M-dM-8M-^V"
# 😀 = F0 9F 98 80 → cat -v: M-pM-^_M-^XM-^@
check_result "emoji U+1F600"     "M-pM-^_M-^XM-^@"

$TMUX kill-server 2>/dev/null

exit $exit_status
