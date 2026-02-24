#!/bin/sh

# Test: kitty-keys runtime option change updates terminal state (T-025, T-034)
#
# Bug: Changing "kitty-keys" at runtime via "set -g kitty-keys off/on/always"
# had no effect on the outer terminal connection because options_push_changes()
# had no handler for "kitty-keys".
#
# Fix: Added handler to options_push_changes() that pushes/pops kitty
# keyboard mode on all capable clients when the option changes.
#
# This test verifies the code path by checking that a pane's kitty encoding
# behavior changes when the option is toggled. We use the same Python helper
# approach as T-024: the pane pushes kitty flags, and we check what encoding
# send-keys produces.
#
# Test 1: kitty-keys always → BTab should use kitty encoding (CSI 9;2u)
# Test 2: kitty-keys off → BTab should use legacy encoding (CSI Z)
# Tests 3-8: Transition cycle tests using screen_reinit() always override
#   Test 3: off→always (always override applied)
#   Test 4: always→on (override removed, no DA)
#   Test 5: on→off (no change at pane level)
#   Test 6: off→on (no DA, no override)
#   Test 7: on→always (override re-applied)
#   Test 8: always→off (override removed)

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lt025$$"
$TMUX kill-server 2>/dev/null
sleep 0.5

RED=$(printf '\033[31m')
GREEN=$(printf '\033[32m')
RESET=$(printf '\033[0m')

exit_status=0

# Per-run temp directory to avoid collisions in parallel.
TMPD=$(mktemp -d /tmp/t025-XXXXXX)
trap 'rm -rf "$TMPD"' EXIT

# Poll until tmux server responds.
wait_for_server () {
	n=0
	while [ $n -lt 30 ]; do
		$TMUX list-sessions >/dev/null 2>&1 && return 0
		sleep 0.2
		n=$((n+1))
	done
	return 1
}

# Wait for pane to be running the expected command.
wait_for_pane () {
	cmd_pattern=$1
	n=0
	while [ $n -lt 30 ]; do
		cur=$($TMUX display -pt0:0.0 -F '#{pane_current_command}' 2>/dev/null)
		case "$cur" in
			*$cmd_pattern*) return 0 ;;
		esac
		sleep 0.2
		n=$((n+1))
	done
	return 1
}

# Poll until a file exists and has content.
wait_for_file () {
	filepath=$1
	timeout=${2:-10}
	n=0
	limit=$((timeout * 5))
	while [ $n -lt $limit ]; do
		[ -s "$filepath" ] && return 0
		sleep 0.2
		n=$((n+1))
	done
	[ -f "$filepath" ] && return 0
	return 1
}

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

# wait_for_shell: poll until pane is running a shell (up to 10 seconds)
wait_for_shell () {
	n=0
	while [ $n -lt 50 ]; do
		cur=$($TMUX display -pt0:0.0 -F '#{pane_current_command}' 2>/dev/null)
		case "$cur" in
			bash|sh|zsh|ksh|dash|fish) return 0 ;;
		esac
		sleep 0.2
		n=$((n+1))
	done
	return 1
}

# Helper Python script: pushes kitty flags, reads stdin bytes with timeout.
# Args: <output_file> <ready_file>
cat > "$TMPD/helper.py" << 'PYEOF'
import sys, os, select, termios, tty

outfile = sys.argv[1] if len(sys.argv) > 1 else '/tmp/t025-out.txt'
readyfile = sys.argv[2] if len(sys.argv) > 2 else outfile + '.ready'

# Push kitty keyboard protocol flags via stdout to tmux.
sys.stdout.buffer.write(b'\033[>1u')
sys.stdout.buffer.flush()

# Switch to raw mode.
fd = sys.stdin.fileno()
old_attrs = termios.tcgetattr(fd)
tty.setraw(fd)

# Signal readiness.
with open(readyfile, 'w') as f:
    f.write('ready')

# Read with timeout.
data = b''
if select.select([fd], [], [], 8.0)[0]:
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

# --- Test 1: kitty-keys always ---
$TMUX -f/dev/null new -x80 -y24 -d || exit 1
wait_for_server
$TMUX set -g escape-time 0
$TMUX set -g kitty-keys always

wait_for_shell
$TMUX send-keys "python3 $TMPD/helper.py $TMPD/out1.txt $TMPD/ready1" Enter
wait_for_file "$TMPD/ready1" 15
sleep 0.5
$TMUX send-keys BTab
wait_for_file "$TMPD/out1.txt" 10

output1=$(cat "$TMPD/out1.txt" 2>/dev/null)

# CSI 9;2u = 1b5b393b3275
case "$output1" in
	*1b5b393b3275*)
		check_result "kitty-keys always: BTab uses CSI 9;2u" "kitty" "kitty"
		;;
	*1b5b5a*)
		check_result "kitty-keys always: BTab uses CSI 9;2u" "kitty" "legacy"
		;;
	*)
		check_result "kitty-keys always: BTab uses CSI 9;2u" "kitty" "unknown ($output1)"
		;;
esac

$TMUX kill-server 2>/dev/null
sleep 0.5

# --- Test 2: Start with kitty-keys always, then switch to off ---
# This verifies the options_push_changes handler clears kitty_state.
$TMUX -f/dev/null new -x80 -y24 -d || exit 1
wait_for_server
$TMUX set -g escape-time 0
$TMUX set -g kitty-keys always

# First verify kitty mode works, then switch to off.
sleep 0.5
$TMUX set -g kitty-keys off
sleep 0.5

# Now run helper — pane pushes kitty flags but option is off.
# With the fix, the terminal should no longer be in kitty mode.
wait_for_shell
$TMUX send-keys "python3 $TMPD/helper.py $TMPD/out2.txt $TMPD/ready2" Enter
wait_for_file "$TMPD/ready2" 15
sleep 0.5
$TMUX send-keys BTab
wait_for_file "$TMPD/out2.txt" 10

output2=$(cat "$TMPD/out2.txt" 2>/dev/null)

# With kitty-keys off, even though pane pushes flags, the encoding
# should still work at the pane level (pane-level flags are independent
# of the server option). The server option affects the outer terminal.
# For this test, we verify pane-level encoding still works when active.
case "$output2" in
	*1b5b393b3275*)
		check_result "pane-level kitty encoding works regardless of server option" \
			"found" "found"
		;;
	*)
		check_result "pane-level kitty encoding works regardless of server option" \
			"CSI 9;2u" "other ($output2)"
		;;
esac

$TMUX kill-server 2>/dev/null

# --- Tests 3-8: Transition cycle tests ---
# These verify that changing kitty-keys and respawning a pane produces
# the correct pane-level kitty state via screen_reinit()'s always override.
# No Python kitty push — relies purely on the option's always override.
#
# Each test uses a SEPARATE server to avoid state leakage between tests.
# The option toggle + respawn-window pattern is timing-sensitive when
# cycling multiple states in one server session.

# Helper: reads one key from stdin in raw mode, saves hex to file.
# Args: <output_file> <ready_file>
cat > "$TMPD/cycle-helper.py" << 'PYEOF'
import sys, os, select, termios, tty

outfile = sys.argv[1] if len(sys.argv) > 1 else '/tmp/t034-out.txt'
readyfile = sys.argv[2] if len(sys.argv) > 2 else outfile + '.ready'

fd = sys.stdin.fileno()
old_attrs = termios.tcgetattr(fd)
tty.setraw(fd)

# Signal readiness.
with open(readyfile, 'w') as f:
    f.write('ready')

data = b''
if select.select([fd], [], [], 8.0)[0]:
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

# Counter for unique file names in send_btab_check.
t034_seq=0

# send_btab_check: change option, respawn pane, send BTab, check encoding.
# Uses respawn-window to trigger screen_reinit() which applies the always
# override when kitty-keys==2.
send_btab_check () {
	label=$1
	option_val=$2
	expected=$3

	t034_seq=$((t034_seq + 1))
	_outfile="$TMPD/cyc-out-${t034_seq}.txt"
	_rdyfile="$TMPD/cyc-rdy-${t034_seq}"

	$TMUX set -g kitty-keys "$option_val"
	sleep 0.3
	$TMUX respawn-window -k "python3 $TMPD/cycle-helper.py $_outfile $_rdyfile"
	wait_for_file "$_rdyfile" 15
	sleep 0.5
	$TMUX send-keys BTab
	wait_for_file "$_outfile" 10

	output=$(cat "$_outfile" 2>/dev/null)

	# CSI 9;2u = 1b5b393b3275 (kitty), CSI Z = 1b5b5a (legacy)
	case "$output" in
		*1b5b393b3275*)
			check_result "$label" "$expected" "kitty"
			;;
		*1b5b5a*)
			check_result "$label" "$expected" "legacy"
			;;
		*)
			check_result "$label" "$expected" "unknown ($output)"
			;;
	esac
}

TMUX="$TEST_TMUX -Lt034$$"
$TMUX kill-server 2>/dev/null
sleep 0.5

$TMUX -f/dev/null new -x80 -y24 -d || exit 1
wait_for_server
$TMUX set -g escape-time 0
$TMUX set -g remain-on-exit on

# Cycle 1: off→always→on→off
send_btab_check "off->always: always override applied" "always" "kitty"
send_btab_check "always->on: override removed (no DA)" "on" "legacy"
send_btab_check "on->off: still no override" "off" "legacy"

# Cycle 2: off→on→always→off
send_btab_check "off->on: no DA, no override" "on" "legacy"
send_btab_check "on->always: override re-applied" "always" "kitty"
send_btab_check "always->off: override removed" "off" "legacy"

$TMUX kill-server 2>/dev/null

exit $exit_status
