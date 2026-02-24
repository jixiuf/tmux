#!/bin/sh

# Test: release events should be discarded in copy mode (T-021)
#
# Bug: window_pane_key() strips KEYC_RELEASE (via KEYC_MASK_FLAGS) before
# dispatching to the mode handler, causing release events to be treated as
# additional keypresses. Fix: discard release events before entering mode
# dispatch.
#
# Test approach: Enter vi copy mode, inject a release 'q' event (should be
# discarded — copy mode should stay active), then inject a press 'q' event
# (should quit copy mode). If release events are treated as presses, the
# release 'q' would quit copy mode prematurely.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lt021"
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
			printf '%s[PASS]%s %s -> %s\n' \
			"$GREEN" "$RESET" "$label" "$actual"
	else
		printf '%s[FAIL]%s %s -> expected %s (Got: %s)\n' \
			"$RED" "$RESET" "$label" "$expected" "$actual"
		exit_status=1
	fi
}

$TMUX -f/dev/null new -x80 -y24 -d || exit 1
sleep 1
$TMUX set -g escape-time 0
$TMUX set -g mode-keys vi
$TMUX set -g kitty-keys always

# Put some content in the pane and enter copy mode.
$TMUX send-keys 'echo hello' Enter
sleep 0.3
$TMUX copy-mode
sleep 0.3

# Verify copy mode is active.
in_mode=$($TMUX display-message -p -t0 '#{pane_in_mode}')
check_result "copy mode initially active" "1" "$in_mode"

# Use Python to create a PTY, attach a tmux client, inject kitty
# capability responses, then inject release event followed by press event.
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
    os.execvp(tmux_bin, [tmux_bin, '-Lt021', 'attach'])
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

    # Inject kitty capability response.
    os.write(master, b'\033[?1u')
    time.sleep(0.5)
    drain(0.5)

    # Re-respond to re-query after push.
    os.write(master, b'\033[?1u')
    time.sleep(0.5)
    drain(0.5)

    # Inject release 'q' event: CSI 113;1:3u
    # In copy-mode-vi, 'q' quits copy mode.
    # If releases are discarded, copy mode stays active.
    # If releases are treated as presses, copy mode exits here.
    os.write(master, b'\033[113;1:3u')
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

# After release 'q', copy mode should still be active.
in_mode=$($TMUX display-message -p -t0 '#{pane_in_mode}')
check_result "copy mode still active after release q" "1" "$in_mode"

# Now use a second PTY client to inject a press 'q' to verify
# normal presses still work.
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
    os.execvp(tmux_bin, [tmux_bin, '-Lt021', 'attach'])
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

    # Inject press 'q' event: CSI 113;1:1u (or just bare 'q')
    # This should quit copy mode.
    os.write(master, b'\033[113;1:1u')
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

# After press 'q', copy mode should have exited.
in_mode=$($TMUX display-message -p -t0 '#{pane_in_mode}')
check_result "copy mode exited after press q" "0" "$in_mode"

$TMUX kill-server 2>/dev/null

exit $exit_status
