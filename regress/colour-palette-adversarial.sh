#!/bin/sh

# Test: Colour and palette system adversarial edge cases
#
# Verifies that the colour/palette subsystem handles adversarial inputs:
# invalid colour values, out-of-range palette indices, OSC 4/10/11/12
# colour sequences, rapid palette changes, and malformed colour strings.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lcolour"
$TMUX kill-server 2>/dev/null
sleep 1

RED=$(printf '\033[31m')
GREEN=$(printf '\033[32m')
RESET=$(printf '\033[0m')

exit_status=0
test_num=0

check_alive () {
	label=$1
	result=$($TMUX list-sessions 2>&1)
	if [ $? -eq 0 ]; then
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s %s (server alive)\n' \
			"$GREEN" "$RESET" "$label"
	else
		printf '%s[FAIL]%s %s (server DEAD: %s)\n' \
			"$RED" "$RESET" "$label" "$result"
		exit_status=1
	fi
}

check_result () {
	label=$1
	expected=$2
	actual=$3

	if [ "$actual" = "$expected" ]; then
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s %s\n' \
			"$GREEN" "$RESET" "$label"
	else
		printf '%s[FAIL]%s %s -> expected "%s" (Got: "%s")\n' \
			"$RED" "$RESET" "$label" "$expected" "$actual"
		exit_status=1
	fi
}

check_error () {
	label=$1
	result=$2
	if [ -n "$result" ]; then
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s %s (rejected: %s)\n' \
			"$GREEN" "$RESET" "$label" "$result"
	else
		printf '%s[FAIL]%s %s (expected error, got none)\n' \
			"$RED" "$RESET" "$label"
		exit_status=1
	fi
}

$TMUX -f/dev/null new -x80 -y24 -d || exit 1
sleep 1

# --- Test 1: Valid colour names ---
test_num=$((test_num + 1))
$TMUX set -g status-style 'fg=red,bg=blue'
check_alive "Test $test_num: valid colour names"
$TMUX set -g status-style 'default'

# --- Test 2: Valid RGB hex colour ---
test_num=$((test_num + 1))
$TMUX set -g status-style 'fg=#ff0000,bg=#00ff00'
check_alive "Test $test_num: valid RGB hex colours"
$TMUX set -g status-style 'default'

# --- Test 3: Valid 256-colour index ---
test_num=$((test_num + 1))
$TMUX set -g status-style 'fg=colour255,bg=colour0'
check_alive "Test $test_num: valid 256-colour indices"
$TMUX set -g status-style 'default'

# --- Test 4: Invalid colour name rejected ---
test_num=$((test_num + 1))
result=$($TMUX set -g status-style 'fg=not_a_colour' 2>&1)
check_error "Test $test_num: invalid colour name rejected" "$result"

# --- Test 5: Colour index boundary (colour255) ---
test_num=$((test_num + 1))
$TMUX set -g status-style 'fg=colour255'
check_alive "Test $test_num: colour index at max boundary (255)"
$TMUX set -g status-style 'default'

# --- Test 6: Colour index 0 ---
test_num=$((test_num + 1))
$TMUX set -g status-style 'fg=colour0'
check_alive "Test $test_num: colour index 0"
$TMUX set -g status-style 'default'

# --- Test 7: OSC 4 set palette entry (valid) ---
test_num=$((test_num + 1))
# Set palette index 1 to red via escape sequence
$TMUX send-keys "printf '\\033]4;1;rgb:ff/00/00\\033\\\\'" Enter
sleep 0.3
check_alive "Test $test_num: OSC 4 set palette entry"

# --- Test 8: OSC 4 with invalid colour string ---
test_num=$((test_num + 1))
$TMUX send-keys "printf '\\033]4;1;not_a_colour\\033\\\\'" Enter
sleep 0.3
check_alive "Test $test_num: OSC 4 invalid colour string"

# --- Test 9: OSC 4 with out-of-range index (negative via large number) ---
test_num=$((test_num + 1))
$TMUX send-keys "printf '\\033]4;999;rgb:ff/00/00\\033\\\\'" Enter
sleep 0.3
check_alive "Test $test_num: OSC 4 out-of-range index (999)"

# --- Test 10: OSC 4 with index 256 (just past boundary) ---
test_num=$((test_num + 1))
$TMUX send-keys "printf '\\033]4;256;rgb:ff/00/00\\033\\\\'" Enter
sleep 0.3
check_alive "Test $test_num: OSC 4 index 256 (past boundary)"

# --- Test 11: OSC 4 query mode ---
test_num=$((test_num + 1))
$TMUX send-keys "printf '\\033]4;0;?\\033\\\\'" Enter
sleep 0.3
check_alive "Test $test_num: OSC 4 palette query"

# --- Test 12: OSC 104 reset palette entry ---
test_num=$((test_num + 1))
$TMUX send-keys "printf '\\033]104;1\\033\\\\'" Enter
sleep 0.3
check_alive "Test $test_num: OSC 104 reset palette entry"

# --- Test 13: OSC 104 reset with invalid index ---
test_num=$((test_num + 1))
$TMUX send-keys "printf '\\033]104;999\\033\\\\'" Enter
sleep 0.3
check_alive "Test $test_num: OSC 104 invalid index"

# --- Test 14: OSC 10 set foreground colour ---
test_num=$((test_num + 1))
$TMUX send-keys "printf '\\033]10;rgb:ff/ff/ff\\033\\\\'" Enter
sleep 0.3
check_alive "Test $test_num: OSC 10 set foreground"

# --- Test 15: OSC 11 set background colour ---
test_num=$((test_num + 1))
$TMUX send-keys "printf '\\033]11;rgb:00/00/00\\033\\\\'" Enter
sleep 0.3
check_alive "Test $test_num: OSC 11 set background"

# --- Test 16: OSC 12 set cursor colour ---
test_num=$((test_num + 1))
$TMUX send-keys "printf '\\033]12;rgb:ff/ff/00\\033\\\\'" Enter
sleep 0.3
check_alive "Test $test_num: OSC 12 set cursor colour"

# --- Test 17: OSC 10/11/12 query mode ---
test_num=$((test_num + 1))
$TMUX send-keys "printf '\\033]10;?\\033\\\\'" Enter
sleep 0.3
$TMUX send-keys "printf '\\033]11;?\\033\\\\'" Enter
sleep 0.3
$TMUX send-keys "printf '\\033]12;?\\033\\\\'" Enter
sleep 0.3
check_alive "Test $test_num: OSC 10/11/12 query mode"

# --- Test 18: Rapid palette changes ---
test_num=$((test_num + 1))
for i in $(seq 0 20); do
	$TMUX send-keys "printf '\\033]4;$i;rgb:ff/00/00\\033\\\\'" Enter
done
sleep 0.5
# Reset them all
for i in $(seq 0 20); do
	$TMUX send-keys "printf '\\033]104;$i\\033\\\\'" Enter
done
sleep 0.5
check_alive "Test $test_num: rapid palette changes (21 set + 21 reset)"

# --- Test 19: OSC 4 with multiple palette entries ---
test_num=$((test_num + 1))
# OSC 4 supports multiple entries: idx;colour;idx;colour...
$TMUX send-keys "printf '\\033]4;0;rgb:ff/00/00;1;rgb:00/ff/00;2;rgb:00/00/ff\\033\\\\'" Enter
sleep 0.3
check_alive "Test $test_num: OSC 4 multiple palette entries"

# --- Test 20: SGR 256-colour in pane ---
test_num=$((test_num + 1))
$TMUX send-keys "printf '\\033[38;5;196mRED\\033[0m'" Enter
sleep 0.3
$TMUX send-keys "printf '\\033[48;5;21mBLUE_BG\\033[0m'" Enter
sleep 0.3
check_alive "Test $test_num: SGR 256-colour sequences"

# --- Test 21: SGR truecolour (24-bit) in pane ---
test_num=$((test_num + 1))
$TMUX send-keys "printf '\\033[38;2;255;128;0mORANGE\\033[0m'" Enter
sleep 0.3
$TMUX send-keys "printf '\\033[48;2;0;128;255mTEAL_BG\\033[0m'" Enter
sleep 0.3
check_alive "Test $test_num: SGR truecolour sequences"

# --- Test 22: SGR with invalid colour index ---
test_num=$((test_num + 1))
# 38;5;999 is out of range (valid is 0-255)
$TMUX send-keys "printf '\\033[38;5;999mTEST\\033[0m'" Enter
sleep 0.3
check_alive "Test $test_num: SGR invalid colour index (999)"

# --- Test 23: Rapid SGR colour cycling ---
test_num=$((test_num + 1))
# Generate rapid colour changes
$TMUX send-keys "for i in \$(seq 0 255); do printf '\\033[38;5;\${i}m#\\033[0m'; done" Enter
sleep 1
check_alive "Test $test_num: rapid SGR 256-colour cycling"

# --- Test 24: Display-panes colour options ---
test_num=$((test_num + 1))
$TMUX set -g display-panes-colour '#ff0000'
$TMUX set -g display-panes-active-colour '#00ff00'
check_alive "Test $test_num: display-panes colour options"

# --- Test 25: OSC with very long number (overflow attempt) ---
test_num=$((test_num + 1))
# Send OSC with a very long number that could overflow u_int
$TMUX send-keys "printf '\\033]99999999999;test\\033\\\\'" Enter
sleep 0.3
check_alive "Test $test_num: OSC with large number (overflow attempt)"

# --- Test 26: Colon-separated SGR colours ---
test_num=$((test_num + 1))
# CSI 38:2::R:G:B m (colon-separated truecolour)
$TMUX send-keys "printf '\\033[38:2::255:0:0mRED\\033[0m'" Enter
sleep 0.3
check_alive "Test $test_num: colon-separated SGR truecolour"

# --- Final: Verify pane still functional ---
test_num=$((test_num + 1))
$TMUX send-keys 'echo ALIVE' Enter
sleep 0.3
alive_check=$($TMUX capture-pane -p | grep ALIVE | tail -1)
case "$alive_check" in
	*ALIVE*)
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s Test %d: pane still functional\n' \
			"$GREEN" "$RESET" "$test_num"
		;;
	*)
		printf '%s[FAIL]%s Test %d: pane not functional (got: "%s")\n' \
			"$RED" "$RESET" "$test_num" "$alive_check"
		exit_status=1
		;;
esac

# Cleanup
$TMUX kill-server 2>/dev/null

if [ $exit_status -eq 0 ]; then
	[ -n "$VERBOSE" ] && printf 'All %d tests passed.\n' "$test_num"
else
	printf 'Some tests FAILED.\n'
fi

exit $exit_status
