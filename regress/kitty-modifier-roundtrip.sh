#!/bin/sh

# Test: kitty modifier roundtrip integrity
#
# Verifies that various modifier combinations are preserved correctly
# through the full tmux pipeline: input parser (tty_keys_kitty_key) →
# internal representation (set_modifier) → output encoder
# (input_key_kitty / get_modifier).

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lmodrt"
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
    os.execvp(tmux_bin, [tmux_bin, '-Lmodrt', 'attach'])
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

    os.write(master, b'\033[?1u')
    time.sleep(0.5)
    drain(0.5)
    os.write(master, b'\033[?1u')
    time.sleep(0.5)
    drain(0.5)

    # Test sequences (each should roundtrip perfectly):

    # 1. Ctrl+a: CSI 97;5u (a=97, modifier=ctrl(0x4)+1=5)
    os.write(master, b'\033[97;5u')
    time.sleep(0.15)

    # 2. Shift+Tab: CSI 9;2u (tab=9, modifier=shift(0x1)+1=2)
    os.write(master, b'\033[9;2u')
    time.sleep(0.15)

    # 3. Alt+Enter: CSI 13;3u (enter=13, modifier=alt(0x2)+1=3)
    os.write(master, b'\033[13;3u')
    time.sleep(0.15)

    # 4. Shift+F5: CSI 15;2~ (F5=15, modifier=shift(0x1)+1=2)
    os.write(master, b'\033[15;2~')
    time.sleep(0.15)

    # 5. Ctrl+Shift+Up: CSI 1;6A (Up, modifier=ctrl+shift(0x5)+1=6)
    os.write(master, b'\033[1;6A')
    time.sleep(0.15)

    # 6. Super+a: CSI 97;9u (a=97, modifier=super(0x8)+1=9)
    os.write(master, b'\033[97;9u')
    time.sleep(0.15)

    # 7. Hyper+a: CSI 97;17u (a=97, modifier=hyper(0x10)+1=17)
    os.write(master, b'\033[97;17u')
    time.sleep(0.15)

    # 8. Meta+a: CSI 97;33u (a=97, modifier=meta(0x20)+1=33)
    os.write(master, b'\033[97;33u')
    time.sleep(0.15)

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

$TMUX kill-server 2>/dev/null

check_result () {
	label=$1
	expected=$2

	case "$actual" in
	*"$expected"*)
		[ -n "$VERBOSE" ] && printf '%s[PASS]%s %s\n' "$GREEN" "$RESET" "$label"
		;;
	*)
		printf '%s[FAIL]%s %s -> expected %s, got %s\n' \
			"$RED" "$RESET" "$label" "$expected" "$actual"
		exit_status=1
		;;
	esac
}

# All sequences should roundtrip: input == output
check_result "Ctrl+a (CSI 97;5u)"          "^[[97;5u"
check_result "Shift+Tab (CSI 9;2u)"        "^[[9;2u"
check_result "Alt+Enter (CSI 13;3u)"       "^[[13;3u"
check_result "Shift+F5 (CSI 15;2~)"        "^[[15;2~"
check_result "Ctrl+Shift+Up (CSI 1;6A)"    "^[[1;6A"
check_result "Super+a (CSI 97;9u)"         "^[[97;9u"
check_result "Hyper+a (CSI 97;17u)"        "^[[97;17u"
check_result "Meta+a (CSI 97;33u)"         "^[[97;33u"

exit $exit_status
