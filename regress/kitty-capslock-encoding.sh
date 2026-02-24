#!/bin/sh

# Test: CapsLock modifier is correctly preserved through the kitty
# keyboard protocol pipeline (parser -> key dispatch -> encoder).
#
# Sends keys with CapsLock modifier (kitty modifier bit 6 = 64) via
# both u-terminated (CSI 97;65u) and letter-final (CSI 1;65A) forms.
# The pane has kitty disambiguate mode pushed, so the kitty encoder
# re-emits the keys with CapsLock modifier preserved.
#
# This exercises:
#   - tty_keys_kitty_key() u-terminated parsing with CapsLock
#   - tty_keys_kitty_key() letter-final parsing with CapsLock
#   - set_modifier() / get_modifier() CapsLock round-trip
#   - input_key_kitty() encoding with CapsLock modifier
#
# Related: T-038 (CapsLock legacy encoding fix at input-keys.c).
# The legacy path is only reachable during a brief pane-switch
# transition (pane-switch sync at server-client.c resets kitty_state
# to match pane flags in steady state), so it cannot be tested
# deterministically via integration test.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lclenc"
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

# Respawn pane: push kitty disambiguate mode, then run cat -v.
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
    os.execvp(tmux_bin, [tmux_bin, '-Lclenc', 'attach'])
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

    # Inject kitty capability response to activate kitty parser.
    os.write(master, b'\033[?1u')
    time.sleep(0.5)
    drain(0.5)

    # tmux will push kitty mode and re-query.  Respond again.
    os.write(master, b'\033[?1u')
    time.sleep(0.5)
    drain(0.5)

    # Send 'a' with CapsLock modifier (CSI 97;65u).
    # Kitty modifier 65 = 1 + 64 (CapsLock = bit 6).
    # Pane has kitty disambiguate -> kitty encoder -> CSI 97;65u.
    os.write(master, b'\033[97;65u')
    time.sleep(0.3)

    # Send Up arrow with CapsLock (CSI 1;65A).
    # This exercises the letter-final parsing path in the kitty parser
    # (requires tty->kitty_state > 0 to activate).
    # Pane has kitty disambiguate -> kitty encoder -> CSI 1;65A.
    os.write(master, b'\033[1;65A')
    time.sleep(0.3)

    # End marker.
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

# Capture pane content. cat -v shows ESC as ^[.
actual=$($TMUX capturep -pt0:0.0 | head -1)

# Expected: kitty-encoded 'a' with CapsLock (^[[97;65u), then
# kitty-encoded Up with CapsLock (^[[1;65A), then end marker 'Z'.
check_result "CapsLock round-trip (u-form + letter-final)" \
	"^[[97;65u^[[1;65AZ" "$actual"

$TMUX kill-server 2>/dev/null

exit $exit_status
