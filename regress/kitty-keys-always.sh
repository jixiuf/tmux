#!/bin/sh

# Test: kitty-keys "always" (==2) forces disambiguate mode (T-026)
#
# Bug: The kitty-keys option accepts off/on/always, but the code never
# distinguishes "on" from "always". Every check uses
# options_get_number(global_options, "kitty-keys") which is truthy for
# both. There are zero == 2 checks.
#
# Fix: Added == 2 checks modeled after extended-keys always:
#  1. screen_reinit() — re-apply KITTY_KBD_DISAMBIGUATE after reset
#  2. screen_write_reset() — clear+re-apply after RIS
#  3. input_csi_dispatch_kitk_pop() — prevent base from going to 0
#  4. tty_start_tty() — force push without TTY_HAVEDA_KITTY
#  5. options_push_changes() — skip TTY_HAVEDA_KITTY guard for always
#
# Test 1: kitty-keys always → pane pushes flags → pop all → base flags
#          should still have DISAMBIGUATE (0x01) due to always override
# Test 2: kitty-keys always → RIS (\033c) → base flags should be
#          re-applied (DISAMBIGUATE still active)

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lt026$$"
$TMUX kill-server 2>/dev/null
sleep 0.5

RED=$(printf '\033[31m')
GREEN=$(printf '\033[32m')
RESET=$(printf '\033[0m')

exit_status=0

# Per-run temp directory to avoid collisions in parallel.
TMPD=$(mktemp -d /tmp/t026-XXXXXX)
trap 'rm -rf "$TMPD"' EXIT

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

# wait_ready: poll for a .ready signal file (up to 15 seconds)
wait_ready () {
	_f=$1
	_n=0
	while [ ! -f "$_f" ] && [ $_n -lt 150 ]; do
		sleep 0.1
		_n=$((_n + 1))
	done
	[ -f "$_f" ] || return 1
	rm -f "$_f"
	return 0
}

# wait_for_server: poll until tmux server responds
wait_for_server () {
	_n=0
	while [ $_n -lt 50 ]; do
		$TMUX list-sessions >/dev/null 2>&1 && return 0
		sleep 0.2
		_n=$((_n + 1))
	done
	return 1
}

# wait_for_shell: poll until pane is running a shell (up to 10 seconds)
wait_for_shell () {
	_n=0
	while [ $_n -lt 50 ]; do
		_cmd=$($TMUX display -pt0:0.0 -F '#{pane_current_command}' 2>/dev/null)
		case "$_cmd" in
			bash|sh|zsh|ksh|dash|fish) return 0 ;;
		esac
		sleep 0.2
		_n=$((_n + 1))
	done
	return 1
}

# Helper: push kitty flags, then pop all, read stdin bytes with timeout.
# After pop, "always" should have re-applied DISAMBIGUATE at base.
# Args: <output_file> <ready_file>
cat > "$TMPD/helper-pop.py" << 'PYEOF'
import sys, os, select, termios, tty, time

outfile = sys.argv[1] if len(sys.argv) > 1 else '/tmp/t026-pop-out.txt'
readyfile = sys.argv[2] if len(sys.argv) > 2 else outfile + '.ready'

# Push kitty keyboard flags (disambiguate=1).
sys.stdout.buffer.write(b'\033[>1u')
sys.stdout.buffer.flush()

time.sleep(0.5)

# Pop all kitty flags — without "always", base goes to 0.
# With "always", base should be re-applied to DISAMBIGUATE.
sys.stdout.buffer.write(b'\033[<u')
sys.stdout.buffer.flush()

time.sleep(0.5)

# Switch to raw mode and read input.
fd = sys.stdin.fileno()
old_attrs = termios.tcgetattr(fd)
tty.setraw(fd)

# Signal that we are ready to receive input.
with open(readyfile, 'w') as f:
    f.write('1')

data = b''
if select.select([fd], [], [], 5.0)[0]:
    data = os.read(fd, 1024)
    while select.select([fd], [], [], 0.3)[0]:
        more = os.read(fd, 1024)
        if not more:
            break
        data += more

termios.tcsetattr(fd, termios.TCSANOW, old_attrs)

with open(outfile, 'w') as f:
    f.write(data.hex())
PYEOF

# Helper: push kitty flags, send RIS, read stdin bytes with timeout.
# After RIS, "always" should re-apply DISAMBIGUATE.
# Args: <output_file> <ready_file>
cat > "$TMPD/helper-ris.py" << 'PYEOF'
import sys, os, select, termios, tty, time

outfile = sys.argv[1] if len(sys.argv) > 1 else '/tmp/t026-ris-out.txt'
readyfile = sys.argv[2] if len(sys.argv) > 2 else outfile + '.ready'

# Push kitty keyboard flags (disambiguate=1).
sys.stdout.buffer.write(b'\033[>1u')
sys.stdout.buffer.flush()
time.sleep(0.5)

# Send RIS (hard reset) — clears kitty state.
# With "always", DISAMBIGUATE should be re-applied after reset.
sys.stdout.buffer.write(b'\033c')
sys.stdout.buffer.flush()
time.sleep(1)

# Switch to raw mode and read input.
fd = sys.stdin.fileno()
old_attrs = termios.tcgetattr(fd)
tty.setraw(fd)

# Signal that we are ready to receive input.
with open(readyfile, 'w') as f:
    f.write('1')

data = b''
if select.select([fd], [], [], 5.0)[0]:
    data = os.read(fd, 1024)
    while select.select([fd], [], [], 0.3)[0]:
        more = os.read(fd, 1024)
        if not more:
            break
        data += more

termios.tcsetattr(fd, termios.TCSANOW, old_attrs)

with open(outfile, 'w') as f:
    f.write(data.hex())
PYEOF

# --- Test 1: kitty-keys always → pop all → BTab should still use kitty ---
$TMUX -f/dev/null new -x80 -y24 -d || exit 1
wait_for_server
$TMUX set -g escape-time 0
$TMUX set -g kitty-keys always

wait_for_shell
$TMUX send-keys "python3 $TMPD/helper-pop.py $TMPD/pop-out.txt $TMPD/pop-ready" Enter
wait_ready "$TMPD/pop-ready"
$TMUX send-keys BTab
sleep 1
sleep 4

output1=$(cat "$TMPD/pop-out.txt" 2>/dev/null)

# CSI 9;2u = 1b5b393b3275 (kitty encoding for Shift+Tab)
# CSI Z = 1b5b5a (legacy encoding for BTab)
case "$output1" in
	*1b5b393b3275*)
		check_result "always: pop all → BTab still kitty (CSI 9;2u)" \
			"kitty" "kitty"
		;;
	*1b5b5a*)
		check_result "always: pop all → BTab still kitty (CSI 9;2u)" \
			"kitty" "legacy"
		;;
	*)
		check_result "always: pop all → BTab still kitty (CSI 9;2u)" \
			"kitty" "unknown ($output1)"
		;;
esac

$TMUX kill-server 2>/dev/null
sleep 0.5

# --- Test 2: kitty-keys always → RIS → BTab should still use kitty ---
$TMUX -f/dev/null new -x80 -y24 -d || exit 1
wait_for_server
$TMUX set -g escape-time 0
$TMUX set -g kitty-keys always

wait_for_shell
$TMUX send-keys "python3 $TMPD/helper-ris.py $TMPD/ris-out.txt $TMPD/ris-ready" Enter
wait_ready "$TMPD/ris-ready"
$TMUX send-keys BTab
sleep 1
sleep 4

output2=$(cat "$TMPD/ris-out.txt" 2>/dev/null)

case "$output2" in
	*1b5b393b3275*)
		check_result "always: RIS → BTab still kitty (CSI 9;2u)" \
			"kitty" "kitty"
		;;
	*1b5b5a*)
		check_result "always: RIS → BTab still kitty (CSI 9;2u)" \
			"kitty" "legacy"
		;;
	*)
		check_result "always: RIS → BTab still kitty (CSI 9;2u)" \
			"kitty" "unknown ($output2)"
		;;
esac

$TMUX kill-server 2>/dev/null

exit $exit_status
