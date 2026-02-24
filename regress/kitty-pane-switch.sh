#!/bin/sh

# Test: Outer terminal kitty state tracks active pane on switch (T-027)
#
# Bug: When switching between panes with different kitty keyboard flags,
# the outer terminal's kitty mode was not updated.
#
# Fix: Added kitty state sync to server_client_reset_state().
#
# Test 1: Pane with kitty flags pushed → BTab = CSI 9;2u
# Test 2: Split to pane with no flags → BTab = CSI Z (legacy)

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")

RED=$(printf '\033[31m')
GREEN=$(printf '\033[32m')
RESET=$(printf '\033[0m')

exit_status=0

# Per-run temp directory to avoid collisions in parallel.
TMPD=$(mktemp -d /tmp/t027-XXXXXX)
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

# Parametric helper: optionally push kitty flags, read stdin with timeout.
cat > "$TMPD/reader.py" << 'PYEOF'
import sys, os, select, termios, tty, time

outfile = sys.argv[1] if len(sys.argv) > 1 else '/tmp/t027-out.txt'
push_flags = int(sys.argv[2]) if len(sys.argv) > 2 else 0

if push_flags > 0:
    sys.stdout.buffer.write(('\033[>%du' % push_flags).encode())
    sys.stdout.buffer.flush()

time.sleep(0.5)

fd = sys.stdin.fileno()
old_attrs = termios.tcgetattr(fd)
tty.setraw(fd)

# Signal that we are ready to receive input.
with open(outfile + '.ready', 'w') as f:
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
	_tmux=$1
	_n=0
	while [ $_n -lt 50 ]; do
		$_tmux list-sessions >/dev/null 2>&1 && return 0
		sleep 0.2
		_n=$((_n + 1))
	done
	return 1
}

# wait_for_shell: poll until pane is running a shell (up to 10 seconds)
wait_for_shell () {
	_tmux=$1
	_pane=${2:-0}
	_n=0
	while [ $_n -lt 50 ]; do
		_cmd=$($_tmux display -pt"$_pane" -F '#{pane_current_command}' 2>/dev/null)
		case "$_cmd" in
			bash|sh|zsh|ksh|dash|fish) return 0 ;;
		esac
		sleep 0.2
		_n=$((_n + 1))
	done
	return 1
}

# --- Test 1: Pane with kitty flags → BTab = CSI 9;2u ---
TMUX1="$TEST_TMUX -Lt027a$$"
$TMUX1 kill-server 2>/dev/null >/dev/null
sleep 0.5

$TMUX1 -f/dev/null new -x80 -y24 -d || exit 1
wait_for_server "$TMUX1"
$TMUX1 set -g escape-time 0
$TMUX1 set -g kitty-keys on

wait_for_shell "$TMUX1"
$TMUX1 send-keys "python3 $TMPD/reader.py $TMPD/p0.txt 1" Enter
wait_ready "$TMPD/p0.txt.ready"
$TMUX1 send-keys BTab
sleep 1
sleep 4

output1=$(cat "$TMPD/p0.txt" 2>/dev/null)

case "$output1" in
	*1b5b393b3275*)
		check_result "kitty pane: BTab uses CSI 9;2u" "kitty" "kitty"
		;;
	*1b5b5a*)
		check_result "kitty pane: BTab uses CSI 9;2u" "kitty" "legacy"
		;;
	*)
		check_result "kitty pane: BTab uses CSI 9;2u" "kitty" \
			"unknown ($output1)"
		;;
esac

$TMUX1 kill-server 2>/dev/null >/dev/null

# --- Test 2: Split to pane with no flags → BTab = legacy ---
TMUX2="$TEST_TMUX -Lt027b$$"
$TMUX2 kill-server 2>/dev/null >/dev/null
sleep 0.5

$TMUX2 -f/dev/null new -x80 -y24 -d || exit 1
wait_for_server "$TMUX2"
$TMUX2 set -g escape-time 0
$TMUX2 set -g kitty-keys on

# Pane 0: push kitty flags and stay alive
wait_for_shell "$TMUX2"
$TMUX2 send-keys 'printf '"'"'\033[>1u'"'"' && sleep 120' Enter
sleep 2

# Split to create pane 1 (active, no kitty flags)
$TMUX2 split-window || { echo "split-window failed"; exit 1; }
wait_for_shell "$TMUX2"

# Pane 1: no kitty push, read keys
$TMUX2 send-keys "python3 $TMPD/reader.py $TMPD/p1.txt 0" Enter
wait_ready "$TMPD/p1.txt.ready"
$TMUX2 send-keys BTab
sleep 1
sleep 4

output2=$(cat "$TMPD/p1.txt" 2>/dev/null)

case "$output2" in
	*1b5b5a*)
		check_result "plain pane after switch: BTab = legacy CSI Z" \
			"legacy" "legacy"
		;;
	*1b5b393b3275*)
		check_result "plain pane after switch: BTab = legacy CSI Z" \
			"legacy" "kitty"
		;;
	*)
		check_result "plain pane after switch: BTab = legacy CSI Z" \
			"legacy" "unknown ($output2)"
		;;
esac

$TMUX2 kill-server 2>/dev/null >/dev/null

exit $exit_status
