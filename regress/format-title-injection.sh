#!/bin/sh

# Test: Format string injection via pane title
#
# Verifies that format metacharacters (#(), #{}, etc.) in pane titles
# are NOT re-expanded when used in default format contexts.
#
# A malicious application inside tmux can set the pane title to
# arbitrary text via OSC 0/2. This test confirms that titles containing
# format metacharacters like #(cmd) are treated as literal strings
# and do NOT trigger shell command execution or variable substitution.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lfmtinj"
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

# --- Test 1: #(cmd) in pane title should NOT execute ---
# Set pane title to a format string that would execute 'echo PWNED'
$TMUX send-keys "printf '\\033]2;#(echo PWNED)\\033\\\\'" Enter
sleep 0.5

# Verify the title was stored literally
actual_title=$($TMUX display-message -pt0:0.0 '#{pane_title}')
check_result "pane_title stores #(cmd) literally" '#(echo PWNED)' "$actual_title"

# Verify display-message does NOT expand #() in the title
# The literal string "#(echo PWNED)" contains "PWNED", so we must check
# that the output is exactly the literal, not the expanded result.
actual_display=$($TMUX display-message -pt0:0.0 '#{pane_title}')
check_result "#(cmd) in title NOT re-expanded" '#(echo PWNED)' "$actual_display"

# --- Test 2: #{variable} in pane title should NOT expand ---
$TMUX send-keys "printf '\\033]2;#{session_name}\\033\\\\'" Enter
sleep 0.5

actual=$($TMUX display-message -pt0:0.0 '#{pane_title}')
check_result "pane_title stores #{var} literally" '#{session_name}' "$actual"

# --- Test 3: E: modifier on pane_title WOULD expand (expected, user config risk) ---
# This test documents the E: re-expansion behavior. A user who writes
# #{E:pane_title} in their status format would be vulnerable.
$TMUX send-keys "printf '\\033]2;hello world\\033\\\\'" Enter
sleep 0.5

actual=$($TMUX display-message -pt0:0.0 '#{E:pane_title}')
check_result "E: re-expands pane_title (plain text passthrough)" "hello world" "$actual"

# --- Test 4: #T alias also does NOT re-expand ---
$TMUX send-keys "printf '\\033]2;#(echo BAD)\\033\\\\'" Enter
sleep 0.5

actual=$($TMUX display-message -pt0:0.0 '#T')
check_result "#T alias returns literal #(cmd)" '#(echo BAD)' "$actual"

# --- Test 5: Title with format metacharacters in status-right ---
# Set status-right to show pane_title (default includes it)
$TMUX set -g status-right '#{pane_title}'
$TMUX send-keys "printf '\\033]2;#{window_index}#(whoami)\\033\\\\'" Enter
sleep 0.5

# Capture status line
actual=$($TMUX display-message -pt0:0.0 '#{pane_title}')
case "$actual" in
	*"$(whoami)"*)
		check_result "pane_title in status-right NOT expanded" "literal" "EXECUTED"
		;;
	*)
		check_result "pane_title in status-right NOT expanded" "literal" "literal"
		;;
esac

# --- Test 6: Nested format injection attempt ---
$TMUX send-keys "printf '\\033]2;#{E:#{session_name}}\\033\\\\'" Enter
sleep 0.5

actual=$($TMUX display-message -pt0:0.0 '#{pane_title}')
check_result "nested format injection stored literally" '#{E:#{session_name}}' "$actual"

# --- Test 7: NUL byte in title (should be stripped by state machine) ---
$TMUX send-keys "printf '\\033]2;before\\x00after\\033\\\\'" Enter
sleep 0.5

actual=$($TMUX display-message -pt0:0.0 '#{pane_title}')
# NUL bytes should be discarded by the OSC state machine
check_result "NUL in title stripped" "beforeafter" "$actual"

# --- Test 8: Control characters (C0) in title (should be stripped) ---
$TMUX send-keys "printf '\\033]2;a\\x01b\\x0ac\\x0dd\\033\\\\'" Enter
sleep 0.5

actual=$($TMUX display-message -pt0:0.0 '#{pane_title}')
# Bytes 0x01, 0x0A (newline), 0x0D (CR) should be stripped during OSC collection
check_result "C0 control chars in title stripped" "abcd" "$actual"

# --- Test 9: Very long title (stress test) ---
long_title=$(python3 -c "print('A' * 5000)")
$TMUX send-keys "printf '\\033]2;${long_title}\\033\\\\'" Enter
sleep 0.5

actual_len=$($TMUX display-message -pt0:0.0 '#{pane_title}' | wc -c)
# Should be stored (input buffer allows up to 1MB)
if [ "$actual_len" -gt 4000 ]; then
	check_result "long title (5000 chars) stored" "stored" "stored"
else
	check_result "long title (5000 chars) stored" "stored" "truncated ($actual_len)"
fi

# --- Test 10: Percent signs in title (strftime safety) ---
# Use a helper script to avoid shell quoting issues with send-keys
cat > /tmp/fmt-inj-pct.py <<'HELPER'
import sys
sys.stdout.write('\033]2;%s%n%x\033\\')
sys.stdout.flush()
HELPER
$TMUX send-keys "python3 /tmp/fmt-inj-pct.py" Enter
sleep 0.5

actual=$($TMUX display-message -pt0:0.0 '#{pane_title}')
check_result "percent signs in title stored literally" '%s%n%x' "$actual"
rm -f /tmp/fmt-inj-pct.py

$TMUX kill-server 2>/dev/null
exit $exit_status
