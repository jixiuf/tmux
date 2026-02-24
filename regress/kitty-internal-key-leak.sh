#!/bin/sh

# Test: Internal keys must NOT leak through kitty CSI u encoder
#
# When a pane has kitty keyboard flags pushed, input_key_kitty() encodes
# keys as CSI u sequences. But internal keys in the KEYC_BASE range
# (KEYC_FOCUS_IN, KEYC_FOCUS_OUT, etc.) should NOT be encoded — they
# have no kitty protocol representation and must be silently dropped.
#
# Bug: The default case in input_key_kitty()'s switch sets
# number = onlykey (the raw enum value, ~0x10e000) and final = 'u',
# producing garbage like CSI 1105920 u. This is because the
# KEYC_IS_UNICODE check is false for KEYC_BASE range keys, but the
# fallback treats them as ASCII codepoints.
#
# The KEYC_BASE guard in input_key() at line 970 normally catches
# these, but it runs AFTER the kitty path at line 854. If
# input_key_kitty() returns 0 (consumed), the guard never runs.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lkilk"
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
$TMUX set -g focus-events on

# Pane pushes kitty disambiguate flag so output uses kitty encoding.
# Do NOT enable MODE_FOCUSON (no \033[?1004h) — we only want kitty
# output encoding, not legacy focus event forwarding.
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
    os.execvp(tmux_bin, [tmux_bin, '-Lkilk', 'attach'])
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

    # Do NOT send \033[?1u — keep client kitty parser INACTIVE.
    # The pane still has kitty output encoding via its pushed flags.
    # This way, \033[I is parsed by the legacy parser (no timing issues).

    # Send FocusIn event (\033[I) — legacy parser produces KEYC_FOCUS_IN
    os.write(master, b'\033[I')
    time.sleep(0.3)

    # Send FocusOut event (\033[O) — legacy parser produces KEYC_FOCUS_OUT
    os.write(master, b'\033[O')
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

actual=$($TMUX capturep -pt0:0.0 | head -1)

$TMUX kill-server 2>/dev/null

# The pane should only show the 'Z' marker, with no garbage CSI u
# sequences from internal keys leaking through the kitty encoder.
# If the bug exists, we'd see something like ^[[1105920u (KEYC_FOCUS_IN
# enum value encoded as CSI u).

check_pass=true

case "$actual" in
*"1105920"*|*"1105921"*)
	printf '%s[FAIL]%s focus-in-leak -> internal key KEYC_FOCUS_IN/OUT leaked as CSI u: %s\n' \
		"$RED" "$RESET" "$actual"
	exit_status=1
	check_pass=false
	;;
esac

case "$actual" in
*"Z"*)
	if $check_pass; then
		[ -n "$VERBOSE" ] && printf '%s[PASS]%s no-internal-key-leak -> pane output clean (no garbage CSI u)\n' \
			"$GREEN" "$RESET"
	fi
	;;
*)
	printf '%s[FAIL]%s end-marker-missing -> expected Z in output, got: %s\n' \
		"$RED" "$RESET" "$actual"
	exit_status=1
	;;
esac

exit $exit_status
