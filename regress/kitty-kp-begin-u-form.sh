#!/bin/sh

# Test: KP_BEGIN (codepoint 57427) via CSI u form
#
# Bug: tty_keys_kitty_key() handles KP_BEGIN (57427) in the tilde form
# (CSI 57427~) but NOT in the u form (CSI 57427u). The u-form switch
# at tty-keys.c skips codepoint 57427 — goes from 57426 (KP_DELETE)
# straight to 57428 (MEDIA_PLAY). Result: CSI 57427u is treated as
# Unicode U+E043 (BMP PUA) instead of KEYC_KP_BEGIN.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lkpbeg"
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
    os.execvp(tmux_bin, [tmux_bin, '-Lkpbeg', 'attach'])
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

    # Test 1: KP_BEGIN via tilde form (control — should work)
    # CSI 57427~ = KP_BEGIN
    os.write(master, b'\033[57427~')
    time.sleep(0.2)

    # Test 2: KP_BEGIN via u form (bug — 57427 missing from u switch)
    # CSI 57427u = should also be KP_BEGIN
    os.write(master, b'\033[57427u')
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

$TMUX kill-server 2>/dev/null

# KP_BEGIN output in kitty disambiguate mode: CSI 1;1E
expected="^[[1;1E"

# Test 1: tilde form (should work)
case "$actual" in
*"$expected"*)
	[ -n "$VERBOSE" ] && printf '%s[PASS]%s kp-begin-tilde -> CSI 57427~ produced %s\n' \
		"$GREEN" "$RESET" "$expected"
	;;
*)
	printf '%s[FAIL]%s kp-begin-tilde -> expected %s in output, got %s\n' \
		"$RED" "$RESET" "$expected" "$actual"
	exit_status=1
	;;
esac

# Test 2: u form (fixed — 57427 added to u switch)
# Count occurrences: should appear twice if u form works
count=$(printf '%s' "$actual" | grep -o '1;1E' | wc -l)
if [ "$count" -ge 2 ]; then
	[ -n "$VERBOSE" ] && printf '%s[PASS]%s kp-begin-u-form -> CSI 57427u also produced %s\n' \
		"$GREEN" "$RESET" "$expected"
else
	printf '%s[FAIL]%s kp-begin-u-form -> CSI 57427u did not produce %s (got %s)\n' \
		"$RED" "$RESET" "$expected" "$actual"
	exit_status=1
fi

exit $exit_status
