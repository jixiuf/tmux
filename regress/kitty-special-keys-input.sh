#!/bin/sh

# Test: special keys received via kitty CSI input sequences produce
# correct key output in the pane application.
#
# Injects raw kitty CSI sequences into a tmux client via a PTY
# (exercising tty_keys_kitty_key()) and verifies the pane receives
# the correct escape sequences.

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

# Start a pane with cat -v to capture key output.
$TMUX -f/dev/null new -x80 -y24 -d || exit 1
sleep 1
$TMUX set -g escape-time 0
$TMUX set -g kitty-keys always

# Create a pane running cat -v that has pushed kitty flags.
$TMUX respawn-window -k -t0:0 -- sh -c \
	'printf "\033[>1u"; stty raw -echo && cat -v'
sleep 0.5

# Use Python to create a PTY, attach a tmux client, inject a kitty
# capability response to enable the kitty parser on the client, then
# inject raw kitty CSI key sequences.
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
    # This tells tmux the terminal supports kitty keys at level 1.
    os.write(master, b'\033[?1u')
    time.sleep(0.5)
    drain(0.5)

    # tmux will push kitty mode and re-query.  Respond again.
    os.write(master, b'\033[?1u')
    time.sleep(0.5)
    drain(0.5)

    # Inject test keys (kitty CSI format).

    # Delete: CSI 3;1~
    os.write(master, b'\033[3;1~')
    time.sleep(0.2)

    # F5: CSI 15;1~
    os.write(master, b'\033[15;1~')
    time.sleep(0.2)

    # Up arrow: CSI 1;1A
    os.write(master, b'\033[1;1A')
    time.sleep(0.2)

    # F3: CSI 1;1R
    os.write(master, b'\033[1;1R')
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

	if [ "$xfail" = "xfail" ]; then
		case "$actual" in
		*"$expected"*)
			printf '%s[XPASS]%s %s found in output\n' \
				"$RED" "$RESET" "$label"
			exit_status=1
			;;
		*)
			[ -n "$VERBOSE" ] || [ -n "$STRICT" ] && \
				printf '%s[XFAIL]%s %s not found in output (got: %s)\n' \
				"$YELLOW" "$RESET" "$label" "$actual"
			[ -n "$STRICT" ] && exit_status=1
			;;
		esac
	else
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
	fi
}

# Delete → ^[[3~ , F5 → ^[[15~ , Up → ^[[A , F3 → ^[[R
check_result "Delete (^[[3~)"  "^[[3~"
check_result "F5 (^[[15~)"    "^[[15~"
check_result "Up (^[[A)"      "^[[A"
check_result "F3 (^[[R)"      "^[[R" xfail

$TMUX kill-server 2>/dev/null

exit $exit_status
