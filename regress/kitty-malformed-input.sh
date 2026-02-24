#!/bin/sh

# Test: tmux survives malformed kitty CSI u sequences
#
# Injects various malformed, oversized, and edge-case kitty sequences
# into a tmux client via PTY to verify the parser doesn't crash.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lmalfi"
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

# Inject malformed sequences via PTY
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
    os.execvp(tmux_bin, [tmux_bin, '-Lmalfi', 'attach'])
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

    # Enable kitty parser
    os.write(master, b'\033[?1u')
    time.sleep(0.5)
    drain(0.5)
    os.write(master, b'\033[?1u')
    time.sleep(0.5)
    drain(0.5)

    # --- Malformed sequences ---

    # 1. Empty CSI u (no parameters)
    os.write(master, b'\033[u')
    time.sleep(0.1)

    # 2. Very large codepoint (> 0x10FFFF)
    os.write(master, b'\033[999999999u')
    time.sleep(0.1)

    # 3. Zero codepoint
    os.write(master, b'\033[0u')
    time.sleep(0.1)

    # 4. Many semicolons (too many parameters)
    os.write(master, b'\033[65;1;1;1;1;1u')
    time.sleep(0.1)

    # 5. Very long parameter string (near buffer limit)
    os.write(master, (b'\033[' + b'9' * 55 + b'u'))
    time.sleep(0.1)

    # 6. Empty sub-parameters (consecutive colons)
    os.write(master, b'\033[65::;1u')
    time.sleep(0.1)

    # 7. Empty parameters (consecutive semicolons)
    os.write(master, b'\033[;;u')
    time.sleep(0.1)

    # 8. Codepoint in PUA range (should be handled)
    os.write(master, b'\033[983040u')  # U+F0000
    time.sleep(0.1)

    # 9. Very large modifier value
    os.write(master, b'\033[65;999999u')
    time.sleep(0.1)

    # 10. Sequence with text sub-parameters
    os.write(master, b'\033[97;1;104:101:108:108:111u')
    time.sleep(0.1)

    # End marker: normal 'a' key
    os.write(master, b'\033[97;1u')
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

# Check tmux server is still alive
if $TMUX has-session 2>/dev/null; then
	[ -n "$VERBOSE" ] && printf '%s[PASS]%s server-alive -> tmux survived all malformed sequences\n' \
		"$GREEN" "$RESET"
else
	printf '%s[FAIL]%s server-alive -> tmux server crashed\n' \
		"$RED" "$RESET"
	exit_status=1
fi

# Check the pane is still functional
actual=$($TMUX capturep -pt0:0.0 2>/dev/null | head -1)
if [ -n "$actual" ]; then
	[ -n "$VERBOSE" ] && printf '%s[PASS]%s pane-functional -> pane received output: %s\n' \
		"$GREEN" "$RESET" "$actual"
else
	printf '%s[FAIL]%s pane-functional -> no output captured\n' \
		"$RED" "$RESET"
	exit_status=1
fi

$TMUX kill-server 2>/dev/null
exit $exit_status
