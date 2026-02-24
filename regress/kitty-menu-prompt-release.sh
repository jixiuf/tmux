#!/bin/sh

# Test: release events should not affect menus, prompts, or messages (T-022)
#
# Bug: server_client_handle_key() dispatches to overlay/prompt/message handlers
# before keys are queued for server_client_key_callback() where the release
# bypass runs. Release events treated as keypresses cause duplicate characters
# in prompts, duplicate menu navigation, and premature message clearing.
#
# Fix: Centralized KEYC_RELEASE bypass in server_client_handle_key() queues
# release events directly, bypassing overlay/prompt/message dispatch.
# Per-handler guards in menu.c, status.c, popup.c provide defense-in-depth.
# Activity timer skips release events to prevent spurious assume-paste.
#
# This test validates via copy mode: the full path goes through
# server_client_handle_key (centralized bypass) → server_client_key_callback
# (release bypass) → window_pane_key (mode guard). Multiple release key
# types (u-form, ~-form, letter-form) are tested.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lt022"
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

# Put content in pane and enter copy mode.
$TMUX send-keys 'echo line1' Enter 'echo line2' Enter 'echo line3' Enter
sleep 0.3
$TMUX copy-mode
sleep 0.3

# Verify baseline.
in_mode=$($TMUX display-message -p -t0 '#{pane_in_mode}')
check_result "copy mode initially active" "1" "$in_mode"

# PTY client: inject multiple release event types.
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
    os.execvp(tmux_bin, [tmux_bin, '-Lt022', 'attach'])
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

    # u-form: Release 'q' — should NOT quit copy mode
    os.write(master, b'\033[113;1:3u')
    time.sleep(0.2)

    # u-form: Release 'j' — should NOT move cursor down
    os.write(master, b'\033[106;1:3u')
    time.sleep(0.2)

    # u-form: Release Escape — should NOT exit copy mode
    os.write(master, b'\033[27;1:3u')
    time.sleep(0.2)

    # letter-form: Release Up arrow — should NOT move cursor up
    os.write(master, b'\033[1;1:3A')
    time.sleep(0.2)

    # ~-form: Release Insert — harmless but tests the form
    os.write(master, b'\033[2;1:3~')
    time.sleep(0.2)

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

# After release events in all 3 CSI forms, copy mode must still be active.
in_mode=$($TMUX display-message -p -t0 '#{pane_in_mode}')
check_result "copy mode survives u/~/letter release events" "1" "$in_mode"

$TMUX kill-server 2>/dev/null

exit $exit_status
