#!/bin/sh

# Test: Caps Lock modifier should not spuriously add Shift
#
# Fixed (T-012): set_modifier() now only infers Shift from uppercase
# when Caps Lock is NOT reported. CapsLock 'A' (modifier=65) is
# preserved correctly without spurious Shift addition.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lkcaps"
$TMUX kill-server 2>/dev/null
sleep 1

RED=$(printf '\033[31m')
GREEN=$(printf '\033[32m')
RESET=$(printf '\033[0m')

exit_status=0

# Start server
$TMUX -f/dev/null new -x80 -y24 -d || exit 1
sleep 1
$TMUX set -g escape-time 0
$TMUX set -g kitty-keys always

# Create pane with kitty flags pushed (disambiguate + report_all)
$TMUX respawn-window -k -- sh -c \
	'printf "\033[>9u"; stty raw -echo && cat -v'
sleep 0.5

# Use Python to inject a kitty CSI u key with Caps Lock modifier
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
    os.execvp(tmux_bin, [tmux_bin, '-Lkcaps', 'attach'])
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

    # Test 1: Inject 'A' (codepoint 65) with CapsLock modifier
    # modifier_param = capslock(0x40) + 1 = 65
    # CSI 65;65u
    os.write(master, b'\033[65;65u')
    time.sleep(0.3)

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

# Capture output
actual=$($TMUX capturep -pt0:0.0 | head -1)

$TMUX kill-server 2>/dev/null

# CapsLock 'A': modifier_param should be 65 (capslock only, no shift)
# Expected output: ^[[65;65u  (capslock only, modifier 65)
expected="^[[65;65u"

case "$actual" in
*"$expected"*)
	[ -n "$VERBOSE" ] && printf '%s[PASS]%s capslock-A-no-shift -> modifier preserved correctly\n' \
		"$GREEN" "$RESET"
	;;
*)
	printf '%s[FAIL]%s capslock-A-no-shift -> expected %s, got %s\n' \
		"$RED" "$RESET" "$expected" "$actual"
	exit_status=1
	;;
esac

exit $exit_status
