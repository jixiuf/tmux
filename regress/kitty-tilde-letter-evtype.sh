#!/bin/sh

# Test: event type parsing for ~-terminated and letter-terminated kitty
# key sequences.
#
# Bug: The ~-terminated parser uses sscanf "%u;%u~" and the letter-
# terminated parser uses "1;%u" -- neither format string accounts for
# the colon-separated event type field (modifier:event_type).
# Release events (evtype=3) are not discarded for these sequence types.

PATH=/bin:/usr/bin
TERM=screen

[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f ../tmux)
TMUX="$TEST_TMUX -Ltest"
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

# Create a pane running cat -v that has pushed kitty flags.
$TMUX respawn-window -k -t0:0 -- sh -c \
	'printf "\033[>1u"; stty raw -echo && cat -v'
sleep 0.5

# Use Python to create a PTY, attach a tmux client, inject kitty
# capability responses, then inject CSI sequences with event types.
python3 - "$TEST_TMUX" <<'PYEOF'
import pty, os, sys, time, signal, struct, fcntl, termios, select

tmux_bin = sys.argv[1]

master, slave = pty.openpty()

# Set the PTY slave to raw mode.
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

# Set a reasonable window size.
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
    os.execvp(tmux_bin, [tmux_bin, '-Ltest', 'attach'])
else:
    os.close(slave)

    def drain(timeout=0.5):
        """Read and discard all pending output from the master."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            r, _, _ = select.select([master], [], [], 0.05)
            if r:
                try:
                    os.read(master, 65536)
                except OSError:
                    break

    # Wait for client to attach and send initial queries.
    time.sleep(1.5)
    drain(0.5)

    # Inject kitty capability response: \033[?1u
    os.write(master, b'\033[?1u')
    time.sleep(0.5)
    drain(0.5)

    # Re-respond to re-query after push.
    os.write(master, b'\033[?1u')
    time.sleep(0.5)
    drain(0.5)

    # Test 1: ~-terminated press event: CSI 2;5:1~ (Insert, Ctrl, press)
    os.write(master, b'\033[2;5:1~')
    time.sleep(0.2)

    # Test 2: ~-terminated release event: CSI 3;5:3~ (Delete, Ctrl, release)
    os.write(master, b'\033[3;5:3~')
    time.sleep(0.2)

    # Test 3: letter-terminated press event: CSI 1;5:1A (Up, Ctrl, press)
    os.write(master, b'\033[1;5:1A')
    time.sleep(0.2)

    # Test 4: letter-terminated release event: CSI 1;5:3B (Down, Ctrl, release)
    os.write(master, b'\033[1;5:3B')
    time.sleep(0.2)

    # Test 5: ~-terminated repeat event: CSI 5;3:2~ (PgUp, Alt, repeat)
    os.write(master, b'\033[5;3:2~')
    time.sleep(0.2)

    # Test 6: letter-terminated repeat event: CSI 1;3:2C (Right, Alt, repeat)
    os.write(master, b'\033[1;3:2C')
    time.sleep(0.2)

    # End marker
    os.write(master, b'Z')
    time.sleep(0.5)

    # Kill the client.
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

# Capture what the pane received.
actual=$($TMUX capturep -pt0:0.0 | head -1)

check_present () {
	label=$1
	expected=$2

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
}

check_absent () {
	label=$1
	forbidden=$2
	xfail=$3

	case "$actual" in
	*"$forbidden"*)
		if [ "$xfail" = "xfail" ]; then
			[ -n "$VERBOSE" ] || [ -n "$STRICT" ] && \
				printf '%s[XFAIL]%s %s not discarded\n' \
				"$YELLOW" "$RESET" "$label"
			[ -n "$STRICT" ] && exit_status=1
		else
			printf '%s[FAIL]%s %s should not appear in output (got: %s)\n' \
				"$RED" "$RESET" "$label" "$actual"
			exit_status=1
		fi
		;;
	*)
		if [ "$xfail" = "xfail" ]; then
			printf '%s[XPASS]%s %s correctly absent\n' \
				"$RED" "$RESET" "$label"
			exit_status=1
		else
			[ -n "$VERBOSE" ] && \
				printf '%s[PASS]%s %s correctly absent\n' \
				"$GREEN" "$RESET" "$label"
		fi
		;;
	esac
}

# Press events should pass through
check_present "Ctrl+Insert press (^[[2;5~)"  "^[[2;5~"
check_present "Ctrl+Up press (^[[1;5A)"      "^[[1;5A"

# Repeat events should pass through
check_present "Alt+PgUp repeat (^[[5;3~)"    "^[[5;3~"
check_present "Alt+Right repeat (^[[1;3C)"   "^[[1;3C"

# Release events should be discarded but the ~ and letter handlers
# don't parse the colon-separated event type field.
check_absent "Ctrl+Delete release (^[[3;5~)" "^[[3;5~"
check_absent "Ctrl+Down release (^[[1;5B)"   "^[[1;5B"

# End marker should be present
check_present "End marker Z" "Z"

$TMUX kill-server 2>/dev/null

exit $exit_status
