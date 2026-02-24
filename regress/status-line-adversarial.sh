#!/bin/sh

# Test: Status line rendering adversarial edge cases
#
# Verifies that the status line rendering system handles adversarial
# inputs without crashing: format expansion edge cases, #() command
# substitution, style parsing, prompt handling, and user-controlled
# data injection attempts.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lstatus"
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

$TMUX -f/dev/null new -x80 -y24 -d || exit 1
sleep 1

# Clear shell prompt hooks that reset the pane title (e.g. PROMPT_COMMAND
# on Meta devservers sets OSC 0 to hostname+cwd after every command).
$TMUX send-keys 'unset PROMPT_COMMAND; PS1="$ "' Enter
sleep 0.3

# --- Test 1: Status line with format variables ---
test_num=$((test_num + 1))
$TMUX set -g status-left '#{session_name} #{window_index}'
sleep 0.3
check_alive "Test $test_num: status-left with format variables"

# --- Test 2: Status line with nested format ---
test_num=$((test_num + 1))
$TMUX set -g status-left '#{?client_prefix,PREFIX,NORMAL}'
sleep 0.3
check_alive "Test $test_num: status-left with conditional format"

# --- Test 3: Status line with #() command substitution ---
test_num=$((test_num + 1))
$TMUX set -g status-right '#(echo hello)'
sleep 1.5
check_alive "Test $test_num: status-right with #() command"

# --- Test 4: Very long status format string ---
test_num=$((test_num + 1))
long_fmt=$(python3 -c "print('#[fg=red]' + 'A' * 5000 + '#[default]')")
$TMUX set -g status-left "$long_fmt"
sleep 0.5
$TMUX set -g status-left '[#{session_name}]'
check_alive "Test $test_num: very long status format (5000 chars)"

# --- Test 5: Status with many format variables ---
test_num=$((test_num + 1))
$TMUX set -g status-left '#{session_name}#{window_index}#{pane_index}#{host}#{pid}#{client_width}#{client_height}'
sleep 0.3
check_alive "Test $test_num: many format variables in status"

# --- Test 6: Rapid status-left changes ---
test_num=$((test_num + 1))
for i in $(seq 1 30); do
	$TMUX set -g status-left "iter-$i"
done
check_alive "Test $test_num: rapid status-left changes (30 cycles)"

# --- Test 7: Status style with complex attributes ---
test_num=$((test_num + 1))
$TMUX set -g status-style 'fg=red,bg=blue,bold,italics'
sleep 0.3
$TMUX set -g status-style 'fg=#ff00ff,bg=#00ff00'
sleep 0.3
$TMUX set -g status-style 'default'
check_alive "Test $test_num: complex status styles"

# --- Test 8: Status with format modifiers ---
test_num=$((test_num + 1))
$TMUX set -g status-left '#{=10:session_name}'
sleep 0.3
$TMUX set -g status-left '#{=-10:session_name}'
sleep 0.3
check_alive "Test $test_num: format truncation modifiers"

# --- Test 9: Session name with shell metacharacters in status ---
test_num=$((test_num + 1))
$TMUX rename-session '$(echo PWNED)'
sleep 0.3
name=$($TMUX display-message -p '#{session_name}')
check_result "Test $test_num: session name with shell metacharacters" '$(echo PWNED)' "$name"

# --- Test 10: Format expansion in rename-session (by design) ---
test_num=$((test_num + 1))
# rename-session expands format strings in its argument — this is by design
# Verify the expansion happens and server stays alive
$TMUX rename-session '#{host}'
sleep 0.3
name=$($TMUX display-message -p '#{session_name}')
# The session name should be the expanded hostname, not literal #{host}
if [ -n "$name" ] && [ "$name" != '#{host}' ]; then
	[ -n "$VERBOSE" ] && \
		printf '%s[PASS]%s Test %d: format expansion in rename-session (%s)\n' \
		"$GREEN" "$RESET" "$test_num" "$name"
else
	printf '%s[FAIL]%s Test %d: format expansion in rename-session (got: "%s")\n' \
		"$RED" "$RESET" "$test_num" "$name"
	exit_status=1
fi

# --- Test 11: Pane title not re-expanded via display-message ---
test_num=$((test_num + 1))
# Set pane title via escape sequence (not expanded by tmux)
$TMUX send-keys "printf '\\033]0;TITLE_TEST_LITERAL\\007'" Enter
sleep 0.5
name=$($TMUX display-message -p '#{pane_title}')
# pane_title should contain the literal value, proving no re-expansion
check_result "Test $test_num: pane title literal via display-message" 'TITLE_TEST_LITERAL' "$name"

# --- Test 12: Status-interval stress ---
test_num=$((test_num + 1))
$TMUX set -g status-interval 1
sleep 2
$TMUX set -g status-interval 15
check_alive "Test $test_num: status-interval stress"

# --- Test 13: Status toggle on/off ---
test_num=$((test_num + 1))
for i in $(seq 1 10); do
	$TMUX set -g status off
	$TMUX set -g status on
done
check_alive "Test $test_num: rapid status on/off toggle (10 cycles)"

# --- Test 14: Status position cycling ---
test_num=$((test_num + 1))
for pos in top bottom; do
	$TMUX set -g status-position "$pos"
done
$TMUX set -g status-position bottom
check_alive "Test $test_num: status position cycling"

# --- Test 15: Status with style ranges ---
test_num=$((test_num + 1))
$TMUX set -g status-left '#[range=left]left#[norange] mid #[range=right]right#[norange]'
sleep 0.3
$TMUX set -g status-left '[#{session_name}]'
check_alive "Test $test_num: status with style ranges"

# --- Test 16: Display-message with format injection ---
test_num=$((test_num + 1))
result=$($TMUX display-message -p '#{session_name}' 2>/dev/null)
if [ -n "$result" ]; then
	[ -n "$VERBOSE" ] && \
		printf '%s[PASS]%s Test %d: display-message format expansion\n' \
		"$GREEN" "$RESET" "$test_num"
else
	printf '%s[FAIL]%s Test %d: display-message returned empty\n' \
		"$RED" "$RESET" "$test_num"
	exit_status=1
fi

# --- Test 17: Status format with multiple lines (status 2-5) ---
test_num=$((test_num + 1))
$TMUX set -g status 2
sleep 0.3
$TMUX set -g status 3
sleep 0.3
$TMUX set -g status on
check_alive "Test $test_num: multi-line status (2, 3)"

# --- Test 18: Empty status format strings ---
test_num=$((test_num + 1))
$TMUX set -g status-left ''
$TMUX set -g status-right ''
sleep 0.3
$TMUX set -g status-left '[#{session_name}]'
$TMUX set -g status-right ''
check_alive "Test $test_num: empty status format strings"

# --- Test 19: Status with UTF-8 content ---
test_num=$((test_num + 1))
$TMUX rename-session '日本語セッション'
$TMUX set -g status-left '[#{session_name}]'
sleep 0.3
check_alive "Test $test_num: UTF-8 in status line"

# --- Test 20: #() with failing command ---
test_num=$((test_num + 1))
$TMUX set -g status-right '#(nonexistent_cmd_12345 2>/dev/null)'
sleep 1.5
$TMUX set -g status-right ''
check_alive "Test $test_num: #() with failing command"

# --- Test 21: Status with deeply nested conditionals ---
test_num=$((test_num + 1))
$TMUX set -g status-left '#{?client_prefix,#{?mouse_any_flag,A,B},#{?mouse_any_flag,C,D}}'
sleep 0.3
check_alive "Test $test_num: deeply nested conditionals"

# --- Test 22: Format loop limit test ---
test_num=$((test_num + 1))
# Create a user option that references itself (would loop without limit)
$TMUX set -g @loop '#{E:@loop}'
# Expanding this would recurse, but FORMAT_LOOP_LIMIT should stop it
$TMUX display-message -p '#{E:@loop}' 2>/dev/null
check_alive "Test $test_num: format recursion loop limit"

# --- Test 23: Pane title injection attempt via status ---
test_num=$((test_num + 1))
# Set pane title with format metacharacters
$TMUX send-keys "printf '\\033]0;#(echo INJECTED)\\007'" Enter
sleep 0.5
# pane_title should contain literal "#(echo INJECTED)", not "INJECTED"
title=$($TMUX display-message -p '#{pane_title}')
case "$title" in
	*'#(echo INJECTED)'*)
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s Test %d: pane title #() not expanded in display\n' \
			"$GREEN" "$RESET" "$test_num"
		;;
	*INJECTED*)
		printf '%s[FAIL]%s Test %d: pane title #() was expanded!\n' \
			"$RED" "$RESET" "$test_num"
		exit_status=1
		;;
	*)
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s Test %d: pane title set (title: "%s")\n' \
			"$GREEN" "$RESET" "$test_num" "$title"
		;;
esac

# --- Test 24: Multiple #() commands in status ---
test_num=$((test_num + 1))
$TMUX set -g status-right '#(echo A)#(echo B)#(echo C)#(echo D)#(echo E)'
sleep 2
check_alive "Test $test_num: multiple #() commands in status"
$TMUX set -g status-right ''

# --- Final: Verify pane still functional ---
test_num=$((test_num + 1))
$TMUX rename-session '0'
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
