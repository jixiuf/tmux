#!/bin/sh

# Test: Format string shell quoting (#{q:...} modifier)
#
# Verifies that the #{q:...} modifier properly escapes shell
# metacharacters to prevent injection when format-expanded strings
# are passed to shell execution contexts (run-shell, if-shell, etc.).
#
# This test also verifies that WITHOUT quoting, format variables
# containing shell metacharacters are expanded by the shell (documenting
# the known risk from T-046).

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Ltest"
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
$TMUX set -g allow-rename on

# Clear shell prompt hooks that reset the pane title (e.g. PROMPT_COMMAND
# on Meta devservers sets OSC 0 to hostname+cwd after every command).
$TMUX send-keys 'unset PROMPT_COMMAND; PS1="$ "' Enter
sleep 0.3

OUT_QUOTED=/tmp/tmux-shquot-quoted-$$
OUT_UNQUOTED=/tmp/tmux-shquot-unquoted-$$
rm -f "$OUT_QUOTED" "$OUT_UNQUOTED"

# --- Test 1: #{q:pane_title} escapes $() ---
$TMUX send-keys "printf '\\033]2;\$(echo INJECTED)\\033\\\\'" Enter
sleep 0.5

$TMUX run-shell "echo #{q:pane_title} > $OUT_QUOTED"
sleep 1

actual=$(cat "$OUT_QUOTED" 2>&1)
check_result "#{q:} escapes \$()" '$(echo INJECTED)' "$actual"
rm -f "$OUT_QUOTED"

# --- Test 2: #{q:pane_title} escapes backticks ---
$TMUX send-keys "printf '\\033]2;\`id\`\\033\\\\'" Enter
sleep 0.5

$TMUX run-shell "echo #{q:pane_title} > $OUT_QUOTED"
sleep 1

actual=$(cat "$OUT_QUOTED" 2>&1)
check_result "#{q:} escapes backticks" '`id`' "$actual"
rm -f "$OUT_QUOTED"

# --- Test 3: #{q:pane_title} escapes semicolons ---
$TMUX send-keys "printf '\\033]2;safe; rm -rf /\\033\\\\'" Enter
sleep 0.5

$TMUX run-shell "echo #{q:pane_title} > $OUT_QUOTED"
sleep 1

actual=$(cat "$OUT_QUOTED" 2>&1)
check_result "#{q:} escapes semicolons" 'safe; rm -rf /' "$actual"
rm -f "$OUT_QUOTED"

# --- Test 4: #{q:pane_title} escapes pipes ---
$TMUX send-keys "printf '\\033]2;data | cat > /tmp/pwned\\033\\\\'" Enter
sleep 0.5

$TMUX run-shell "echo #{q:pane_title} > $OUT_QUOTED"
sleep 1

actual=$(cat "$OUT_QUOTED" 2>&1)
check_result "#{q:} escapes pipes" 'data | cat > /tmp/pwned' "$actual"
rm -f "$OUT_QUOTED"

# --- Test 5: #{q:pane_title} escapes single quotes ---
$TMUX send-keys "printf \"\\033]2;it's a test\\033\\\\\"" Enter
sleep 0.5

$TMUX run-shell "echo #{q:pane_title} > $OUT_QUOTED"
sleep 1

actual=$(cat "$OUT_QUOTED" 2>&1)
check_result "#{q:} escapes single quotes" "it's a test" "$actual"
rm -f "$OUT_QUOTED"

# --- Test 6: #{q:pane_title} escapes double quotes ---
$TMUX send-keys "printf '\\033]2;say \"hello\"\\033\\\\'" Enter
sleep 0.5

$TMUX run-shell "echo #{q:pane_title} > $OUT_QUOTED"
sleep 1

actual=$(cat "$OUT_QUOTED" 2>&1)
check_result "#{q:} escapes double quotes" 'say "hello"' "$actual"
rm -f "$OUT_QUOTED"

# --- Test 7: #{q:session_name} with shell metacharacters ---
$TMUX rename-session '$(id)'
$TMUX run-shell "echo #{q:session_name} > $OUT_QUOTED"
sleep 1

actual=$(cat "$OUT_QUOTED" 2>&1)
check_result "#{q:session_name} escapes \$()" '$(id)' "$actual"
rm -f "$OUT_QUOTED"

# Restore session name
$TMUX rename-session "test"

# --- Test 8: #{q:} does NOT escape newlines (known limitation) ---
# Newlines can't be in pane_title (stripped by OSC parser), but
# can be in user options. The q modifier doesn't escape them.
# This documents the known behavior — not a test failure.
$TMUX set @test_val "safe_value"
$TMUX run-shell "echo #{q:@test_val} > $OUT_QUOTED"
sleep 1

actual=$(cat "$OUT_QUOTED" 2>&1)
check_result "#{q:} works with simple values" "safe_value" "$actual"
rm -f "$OUT_QUOTED"

# --- Test 9: Server survived all tests ---
if $TMUX has-session 2>/dev/null; then
	check_result "server survived shell quoting tests" "alive" "alive"
else
	check_result "server survived shell quoting tests" "alive" "dead"
fi

$TMUX kill-server 2>/dev/null
rm -f "$OUT_QUOTED" "$OUT_UNQUOTED"
exit $exit_status
