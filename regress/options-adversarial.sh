#!/bin/sh

# Test: Options system adversarial edge cases
#
# Verifies that the tmux options system handles adversarial inputs:
# invalid values, type mismatches, user options, style parsing,
# array operations, and rapid option changes without crashing.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Loptadv"
$TMUX kill-server 2>/dev/null
sleep 1

RED=$(printf '\033[31m')
GREEN=$(printf '\033[32m')
RESET=$(printf '\033[0m')

exit_status=0
test_num=0

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

check_error () {
	label=$1
	result=$2
	# Expect non-empty error output
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

# --- Test 1: Set number option with invalid value ---
test_num=$((test_num + 1))
result=$($TMUX set -g history-limit 'not_a_number' 2>&1)
check_error "Test $test_num: number option rejects non-numeric" "$result"

# --- Test 2: Set number option at boundary ---
test_num=$((test_num + 1))
$TMUX set -g history-limit 0
val=$($TMUX show -gv history-limit 2>/dev/null)
check_result "Test $test_num: history-limit accepts 0" "0" "$val"

# --- Test 3: Set number option at max boundary ---
test_num=$((test_num + 1))
# history-limit max is typically very large, set a high value
$TMUX set -g history-limit 999999
val=$($TMUX show -gv history-limit 2>/dev/null)
check_result "Test $test_num: history-limit accepts 999999" "999999" "$val"
$TMUX set -g history-limit 2000  # restore default

# --- Test 4: Set flag option with invalid value ---
test_num=$((test_num + 1))
result=$($TMUX set -g mouse 'invalid' 2>&1)
check_error "Test $test_num: flag option rejects invalid value" "$result"

# --- Test 5: Toggle flag option ---
test_num=$((test_num + 1))
$TMUX set -g mouse off
$TMUX set -g mouse  # toggle
val=$($TMUX show -gv mouse 2>/dev/null)
check_result "Test $test_num: flag toggle from off" "on" "$val"
$TMUX set -g mouse off  # restore

# --- Test 6: Set choice option with invalid value ---
test_num=$((test_num + 1))
result=$($TMUX set -g status 'invalid_choice' 2>&1)
check_error "Test $test_num: choice option rejects invalid" "$result"

# --- Test 7: Set choice option with valid values ---
test_num=$((test_num + 1))
for val in on off 2 3 4 5; do
	$TMUX set -g status "$val" 2>/dev/null
done
$TMUX set -g status on  # restore
check_alive "Test $test_num: choice option cycling"

# --- Test 8: User option with shell metacharacters ---
test_num=$((test_num + 1))
$TMUX set -g @test_user '$(echo PWNED); `id`'
val=$($TMUX show -gv @test_user 2>/dev/null)
check_result "Test $test_num: user option stores shell metacharacters" \
	'$(echo PWNED); `id`' "$val"

# --- Test 9: User option with format metacharacters ---
test_num=$((test_num + 1))
$TMUX set -g @test_fmt '#{session_name}#(echo BAD)'
val=$($TMUX show -gv @test_fmt 2>/dev/null)
check_result "Test $test_num: user option stores format metacharacters" \
	'#{session_name}#(echo BAD)' "$val"

# --- Test 10: User option with very long value ---
test_num=$((test_num + 1))
long_val=$(python3 -c "print('O' * 10000)")
$TMUX set -g @test_long "$long_val"
check_alive "Test $test_num: user option with 10000-char value"

# --- Test 11: Many user options ---
test_num=$((test_num + 1))
for i in $(seq 1 50); do
	$TMUX set -g "@stress_opt_$i" "value_$i"
done
check_alive "Test $test_num: 50 user options set"

# --- Test 12: Style option with shell injection attempt ---
test_num=$((test_num + 1))
result=$($TMUX set -g status-style '$(echo PWNED)' 2>&1)
check_error "Test $test_num: style option rejects shell injection" "$result"

# --- Test 13: Style option with format expansion ---
test_num=$((test_num + 1))
# Format expansion in styles bypasses validation (by design)
$TMUX set -g status-style '#{?client_prefix,bg=red,bg=green}'
check_alive "Test $test_num: style with format expansion accepted"
$TMUX set -g status-style 'default'  # restore

# --- Test 14: Style option with valid complex style ---
test_num=$((test_num + 1))
$TMUX set -g status-style 'fg=red,bg=blue,bold,italics'
val=$($TMUX show -gv status-style 2>/dev/null)
check_alive "Test $test_num: complex style accepted"
$TMUX set -g status-style 'default'

# --- Test 15: Colour option with invalid value ---
test_num=$((test_num + 1))
result=$($TMUX set -g display-panes-colour 'not_a_colour' 2>&1)
check_error "Test $test_num: colour option rejects invalid" "$result"

# --- Test 16: Colour option with RGB value ---
test_num=$((test_num + 1))
$TMUX set -g display-panes-colour '#ff0000'
check_alive "Test $test_num: colour option accepts RGB hex"

# --- Test 17: Key option with invalid key ---
test_num=$((test_num + 1))
result=$($TMUX set -g prefix 'not_a_key_!!!' 2>&1)
# This might actually parse as something — check alive regardless
check_alive "Test $test_num: key option with odd string"

# --- Test 18: Command option with invalid syntax ---
test_num=$((test_num + 1))
result=$($TMUX set -g remain-on-exit-format '#{' 2>&1)
# This is a string option, not command, so it should accept it
check_alive "Test $test_num: string option accepts incomplete format"

# --- Test 19: Array option append and delete ---
test_num=$((test_num + 1))
$TMUX set -ga update-environment 'TEST_APPEND_VAR'
$TMUX set -gu update-environment  # unset to restore default
check_alive "Test $test_num: array option append and unset"

# --- Test 20: Rapid option changes ---
test_num=$((test_num + 1))
for i in $(seq 1 50); do
	$TMUX set -g status-interval "$i" 2>/dev/null
done
$TMUX set -g status-interval 15  # restore default
check_alive "Test $test_num: rapid option changes (50 cycles)"

# --- Test 21: Set non-existent option (should fail) ---
test_num=$((test_num + 1))
result=$($TMUX set -g nonexistent-option-12345 'value' 2>&1)
check_error "Test $test_num: non-existent option rejected" "$result"

# --- Test 22: Unset built-in option ---
test_num=$((test_num + 1))
$TMUX set -gu status-style  # unset to inherit default
check_alive "Test $test_num: unset built-in option"

# --- Test 23: Set default-shell to invalid path ---
test_num=$((test_num + 1))
result=$($TMUX set -g default-shell '/nonexistent/shell' 2>&1)
check_error "Test $test_num: default-shell rejects invalid path" "$result"

# --- Test 24: Pane option ---
test_num=$((test_num + 1))
$TMUX set -p allow-passthrough on
val=$($TMUX show -pv allow-passthrough 2>/dev/null)
check_result "Test $test_num: pane option set" "on" "$val"
$TMUX set -p allow-passthrough off  # restore safe default

# --- Test 25: Unicode in user option name ---
test_num=$((test_num + 1))
$TMUX set -g '@日本語' 'unicode_name'
val=$($TMUX show -gv '@日本語' 2>/dev/null)
check_result "Test $test_num: Unicode in user option name" 'unicode_name' "$val"

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
