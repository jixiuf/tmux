#!/bin/sh

# Test: Key bindings fire when CapsLock is reported by kitty protocol
#
# Bug (T-033): KEYC_CAPS_LOCK (0x0004000000000000ULL) is in
# KEYC_MASK_MODIFIERS, so it participates in key binding lookup via
# key0 = key & (KEYC_MASK_KEY|KEYC_MASK_MODIFIERS). No bindings
# include KEYC_CAPS_LOCK, so ALL key bindings fail when CapsLock is
# active on a kitty terminal.
#
# Fix: Strip KEYC_CAPS_LOCK from key0 before binding lookup in
# server_client_key_callback().
#
# Test: Bind 'z' and Up arrow to set options. Send CSI 122;65u ('z'
# with CapsLock) and CSI 1;65A (Up with CapsLock). Verify bindings
# fire. The pane pushes kitty disambiguate mode so the kitty parser
# is active (kitty_state > 0) and KEYC_CAPS_LOCK is actually set on
# the key — without this, the extended key handler processes
# u-terminated sequences without CapsLock, making the test a
# false positive.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lcapslock"
$TMUX kill-server 2>/dev/null
sleep 1

RED=$(printf '\033[31m')
GREEN=$(printf '\033[32m')
RESET=$(printf '\033[0m')

exit_status=0

check_result () {
	label=$1
	expected=$2
	actual=$3

	if [ "$actual" = "$expected" ]; then
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s %s\n' \
			"$GREEN" "$RESET" "$label"
	else
		printf '%s[FAIL]%s %s -> expected %s (Got: %s)\n' \
			"$RED" "$RESET" "$label" "$expected" "$actual"
		exit_status=1
	fi
}

# Start tmux with kitty-keys always.
$TMUX -f/dev/null new -x80 -y24 -d || exit 1
sleep 1
$TMUX set -g escape-time 0
$TMUX set -g kitty-keys always

# Respawn with kitty disambiguate mode so kitty_state > 0 in steady
# state (pane-switch sync matches tty->kitty_state to pane flags).
$TMUX respawn-window -k -- sh -c \
	'printf "\033[>1u"; exec cat'
sleep 0.5

# Bind 'z' (root table) to set a user option.
$TMUX bind -n z set -g @capslock-z yes

# Bind Up arrow to set another option.
$TMUX bind -n Up set -g @capslock-up yes

# Clear the markers.
$TMUX set -g @capslock-z no
$TMUX set -g @capslock-up no

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
    os.execvp(tmux_bin, [tmux_bin, '-Lcapslock', 'attach'])
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

    # Send kitty capability response so tmux activates kitty mode.
    os.write(master, b'\033[?1u')
    time.sleep(0.5)
    drain(0.5)
    os.write(master, b'\033[?1u')
    time.sleep(0.5)
    drain(0.5)

    # Send CSI 122;65u = 'z' (codepoint 122) with CapsLock modifier.
    # Kitty modifier 65 = 1 + 64 (CapsLock = bit 6).
    # With kitty parser active, this sets KEYC_CAPS_LOCK on the key.
    # T-033 strips CapsLock before binding lookup -> 'z' binding fires.
    os.write(master, b'\033[122;65u')
    time.sleep(0.5)

    # Send CSI 1;65A = Up arrow with CapsLock modifier.
    # Letter-final form — ONLY the kitty parser handles this (not the
    # extended key handler). Exercises a distinct code path.
    os.write(master, b'\033[1;65A')
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

# Check if bindings fired despite CapsLock modifier.
result_z=$($TMUX show -gv @capslock-z 2>/dev/null)
result_up=$($TMUX show -gv @capslock-up 2>/dev/null)

check_result "binding fires with CapsLock u-form (CSI 122;65u)" \
	"yes" "$result_z"
check_result "binding fires with CapsLock letter-final (CSI 1;65A)" \
	"yes" "$result_up"

$TMUX kill-server 2>/dev/null

exit $exit_status
