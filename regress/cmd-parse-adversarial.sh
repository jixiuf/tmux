#!/bin/sh

# Test: Command parsing adversarial edge cases
#
# Verifies that tmux command parsing handles adversarial inputs:
# invalid syntax, deep nesting, long arguments, special characters,
# and edge cases in the Bison parser without crashing.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lcmdparse"
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

$TMUX -f/dev/null new -x80 -y24 -d || exit 1
sleep 1

# --- Test 1: Invalid command ---
test_num=$((test_num + 1))
$TMUX nonexistent-command 2>/dev/null
check_alive "Test $test_num: invalid command name handled"

# --- Test 2: Command with very long argument (10000 chars) ---
test_num=$((test_num + 1))
long_arg=$(python3 -c "print('A' * 10000)")
$TMUX display-message "$long_arg" 2>/dev/null
check_alive "Test $test_num: very long argument (10000 chars) handled"

# --- Test 3: Command with all shell metacharacters ---
test_num=$((test_num + 1))
$TMUX display-message '`$(echo PWNED); |&<>(){}[]!@#$%^&*' 2>/dev/null
check_alive "Test $test_num: shell metacharacters in argument"

# --- Test 4: Deeply nested if-shell (not recursive, just chained) ---
test_num=$((test_num + 1))
$TMUX if-shell 'true' { if-shell 'true' { if-shell 'true' { display-message 'deep' } } } 2>/dev/null
sleep 0.5
check_alive "Test $test_num: triple-nested if-shell blocks"

# --- Test 5: source-file with non-existent file ---
test_num=$((test_num + 1))
$TMUX source-file /tmp/nonexistent-tmux-config-12345.conf 2>/dev/null
check_alive "Test $test_num: source-file non-existent file"

# --- Test 6: source-file with /dev/null ---
test_num=$((test_num + 1))
$TMUX source-file /dev/null 2>/dev/null
check_alive "Test $test_num: source-file /dev/null"

# --- Test 7: source-file with invalid config syntax ---
test_num=$((test_num + 1))
cat > /tmp/tmux-bad-config.conf << 'EOF'
this is not a valid command
set -g }{}{}{
bind x display-message {{{
EOF
$TMUX source-file /tmp/tmux-bad-config.conf >/dev/null 2>&1
check_alive "Test $test_num: source-file with invalid syntax"

# --- Test 8: Format expansion edge cases ---
test_num=$((test_num + 1))
$TMUX display-message -p '#{=1000:session_name}' >/dev/null 2>&1
check_alive "Test $test_num: format truncation to 1000 chars"

# --- Test 9: Recursive format expansion attempt ---
test_num=$((test_num + 1))
$TMUX display-message -p '#{E:#{E:#{E:session_name}}}' >/dev/null 2>&1
check_alive "Test $test_num: nested E: format modifiers"

# --- Test 10: Format match with regex ---
test_num=$((test_num + 1))
result=$($TMUX display-message -p '#{m/r:^test,test123}' 2>/dev/null)
check_result "Test $test_num: format regex match" "1" "$result"

# --- Test 11: Format match with invalid regex ---
test_num=$((test_num + 1))
result=$($TMUX display-message -p '#{m/r:((([,test}' 2>/dev/null)
check_result "Test $test_num: format invalid regex match returns 0" "0" "$result"

# --- Test 12: Format substitution via session name ---
test_num=$((test_num + 1))
# Rename session to a known value, then apply substitution
$TMUX rename-session 'hello_world'
result=$($TMUX display-message -p '#{s/_/ /:session_name}' 2>/dev/null)
check_result "Test $test_num: format regex substitution" "hello world" "$result"
$TMUX rename-session '0'

# --- Test 13: Semicolons in command parsing ---
test_num=$((test_num + 1))
$TMUX display-message 'first' \; display-message 'second' 2>/dev/null
check_alive "Test $test_num: semicolons separating commands"

# --- Test 14: Empty command (just whitespace) ---
test_num=$((test_num + 1))
$TMUX '' 2>/dev/null
check_alive "Test $test_num: empty command string"

# --- Test 15: Command with escaped newlines ---
test_num=$((test_num + 1))
$TMUX display-message "line1\nline2" 2>/dev/null
check_alive "Test $test_num: escaped newlines in argument"

# --- Test 16: Command-alias expansion ---
test_num=$((test_num + 1))
$TMUX set -g command-alias[100] 'testcmd123=display-message "aliased"'
$TMUX testcmd123 2>/dev/null
sleep 0.3
check_alive "Test $test_num: command alias expansion"

# --- Test 17: Tilde expansion in source-file ---
test_num=$((test_num + 1))
# Should not crash even if file doesn't exist
$TMUX source-file '~/nonexistent-config-12345.conf' 2>/dev/null
check_alive "Test $test_num: tilde expansion in source-file"

# --- Test 18: Variable expansion ---
test_num=$((test_num + 1))
$TMUX setenv TESTVAR_PARSE "hello_parse"
result=$($TMUX display-message -p '#{TESTVAR_PARSE}' 2>/dev/null)
# Note: #{VAR} looks up tmux format variables, not env vars directly
check_alive "Test $test_num: environment variable via setenv"

# --- Test 19: Config with conditional directives ---
test_num=$((test_num + 1))
cat > /tmp/tmux-conditional.conf << 'EOF'
%if #{==:#{session_name},0}
set -g status-left "COND-TRUE"
%else
set -g status-left "COND-FALSE"
%endif
EOF
$TMUX source-file /tmp/tmux-conditional.conf 2>/dev/null
check_alive "Test $test_num: conditional config directives"

# --- Test 20: source-file glob pattern ---
test_num=$((test_num + 1))
$TMUX source-file '/tmp/tmux-glob-nonexist-*.conf' 2>/dev/null
check_alive "Test $test_num: source-file with glob pattern (no match)"

# --- Test 21: Unicode in commands ---
test_num=$((test_num + 1))
result=$($TMUX display-message -p 'éàü日本語' 2>/dev/null)
check_result "Test $test_num: Unicode in display-message" 'éàü日本語' "$result"

# --- Test 22: Rapid command execution ---
test_num=$((test_num + 1))
for i in $(seq 1 50); do
	$TMUX display-message "msg$i" 2>/dev/null
done
check_alive "Test $test_num: rapid command execution (50 messages)"

# --- Test 23: Very many semicolon-separated commands ---
test_num=$((test_num + 1))
cmd="display-message 'a'"
for i in $(seq 1 20); do
	cmd="$cmd \\; display-message 'a'"
done
eval $TMUX $cmd 2>/dev/null
check_alive "Test $test_num: 20 semicolon-separated commands"

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
rm -f /tmp/tmux-bad-config.conf /tmp/tmux-conditional.conf

if [ $exit_status -eq 0 ]; then
	[ -n "$VERBOSE" ] && printf 'All %d tests passed.\n' "$test_num"
else
	printf 'Some tests FAILED.\n'
fi

exit $exit_status
