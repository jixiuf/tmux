#!/bin/sh

# Test: kitty release events forwarded when flag 2 (report event types) active
#
# Bug (fixed in T-002): The u-terminated parser's modifier:eventtype
# sub-field loop had j++ after a continue, so j never incremented and
# the event type value overwrote the modifier. Release events were
# never discarded because evtype stayed at default 1 (press). The ~
# and letter terminated parsers didn't parse the event type at all.
#
# The flag masking bug (T-004) that prevented flag 2 from being stored
# has also been fixed.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lkrel"
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

# Create a pane running cat -v that pushes flag 3 (disambiguate | report_event).
$TMUX respawn-window -k -- sh -c \
	'printf "\033[>3u"; stty raw -echo && cat -v'
sleep 0.5

# Use Python to create a PTY, attach a tmux client, inject kitty
# capability responses, then inject key sequences including releases.
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
    os.execvp(tmux_bin, [tmux_bin, '-Lkrel', 'attach'])
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

    # Inject kitty capability response: flag 3 = disambiguate + report_event
    os.write(master, b'\033[?3u')
    time.sleep(0.5)
    drain(0.5)

    # Re-respond to re-query after push.
    os.write(master, b'\033[?3u')
    time.sleep(0.5)
    drain(0.5)

    # CSI u release: CSI 97;1:3u ('a' release, no modifiers)
    os.write(master, b'\033[97;1:3u')
    time.sleep(0.2)

    # CSI u press: CSI 98;1:1u ('b' press, no modifiers)
    os.write(master, b'\033[98;1:1u')
    time.sleep(0.2)

    # ~-terminated release: CSI 2;1:3~ (Insert release)
    os.write(master, b'\033[2;1:3~')
    time.sleep(0.2)

    # letter-terminated release: CSI 1;1:3A (Up release)
    os.write(master, b'\033[1;1:3A')
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

check_result () {
	label=$1
	expected=$2
	xfail=$3

	case "$actual" in
	*"$expected"*)
		if [ "$xfail" = "xfail" ]; then
			printf '%s[XPASS]%s %s found in output\n' \
				"$RED" "$RESET" "$label"
			exit_status=1
		else
			[ -n "$VERBOSE" ] && \
				printf '%s[PASS]%s %s found in output\n' \
				"$GREEN" "$RESET" "$label"
		fi
		;;
	*)
		if [ "$xfail" = "xfail" ]; then
			[ -n "$VERBOSE" ] || [ -n "$STRICT" ] && \
				printf '%s[XFAIL]%s %s not found in output\n' \
				"$YELLOW" "$RESET" "$label"
			[ -n "$STRICT" ] && exit_status=1
		else
			printf '%s[FAIL]%s %s not found in output (got: %s)\n' \
				"$RED" "$RESET" "$label" "$actual"
			exit_status=1
		fi
		;;
	esac
}

# Release events should be forwarded with :3 event type when flag 2 active.
check_result "'a' release (^[[97;1:3u)"     "^[[97;1:3u"
check_result "Insert release (^[[2;1:3~)"    "^[[2;1:3~"
check_result "Up release (^[[1;1:3A)"        "^[[1;1:3A"

# Press event should be forwarded normally.
check_result "'b' press forwarded as 'b'"    "b"

# End marker should be present.
check_result "End marker Z" "Z"

$TMUX kill-server 2>/dev/null

exit $exit_status
