#!/bin/sh

# Test: kitty functional key roundtrip for spec codepoints 57358-57454
#
# Verifies that functional keys defined in the kitty keyboard protocol
# (lock keys, F13+, keypad keys, media keys, modifier keys) roundtrip
# correctly through: input parser (tty_keys_kitty_key) → internal
# representation → output encoder (input_key_kitty).
#
# Each key is injected as CSI <codepoint> u and should be re-encoded
# as CSI <codepoint> u (or CSI <codepoint>;1 u when modifiers are
# explicitly present).

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lkfunc"
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

# Use wait-for to synchronize: the pane signals readiness after cat -v starts
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
    os.execvp(tmux_bin, [tmux_bin, '-Lkfunc', 'attach'])
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

    # Functional keys to test (codepoint, name):
    keys = [
        (57358, 'CapsLock'),
        (57360, 'NumLock'),
        (57361, 'PrintScreen'),
        (57376, 'F13'),
        (57387, 'F24'),
        (57398, 'F35'),
        (57399, 'KP_0'),
        (57414, 'KP_Enter'),
        (57427, 'KP_Begin'),
        (57428, 'MediaPlay'),
        (57440, 'VolumeMute'),
        (57441, 'ShiftL'),
        (57454, 'ISOLevel5'),
    ]

    for cp, name in keys:
        seq = f'\033[{cp}u'.encode()
        os.write(master, seq)
        time.sleep(0.12)

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

actual=$($TMUX capturep -pt0:0.0 | tr -d '\n')

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

# Each functional key should roundtrip as CSI <codepoint> u
check_result "CapsLock (57358)"       "^[[57358u"
check_result "NumLock (57360)"        "^[[57360u"
check_result "PrintScreen (57361)"    "^[[57361u"
check_result "F13 (57376)"           "^[[57376u"
check_result "F24 (57387)"           "^[[57387u"
check_result "F35 (57398)"           "^[[57398u"
check_result "KP_0 (57399)"          "^[[57399u"
check_result "KP_Enter (57414)"      "^[[57414u"
# KP_BEGIN re-encodes as CSI 1;1E (legacy form), not CSI 57427u
check_result "KP_Begin (CSI E)"      "^[[1;1E"
check_result "MediaPlay (57428)"     "^[[57428u"
check_result "VolumeMute (57440)"    "^[[57440u"
check_result "ShiftL (57441)"        "^[[57441u"
check_result "ISOLevel5 (57454)"     "^[[57454u"

exit $exit_status
