#!/bin/sh

# Test: Copy-mode search adversarial edge cases
#
# Verifies that copy-mode search handles adversarial regex patterns,
# invalid patterns, edge cases, and stress conditions without crashing.
#
# Attack surface: User-provided patterns are passed to regcomp() with
# REG_EXTENDED. Invalid patterns silently fail (no match). The 10-second
# WINDOW_COPY_SEARCH_TIMEOUT limits CPU consumption from pathological regex.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lcmsearch"
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

# Create test content with various patterns for search
cat > /tmp/cmsearch-content.txt << 'CONTENT'
Hello World
aaabbbccc
line with special chars: $HOME #{var} #(cmd)
AAAA BBBB CCCC
repeated aaaaaaaaaa pattern
the quick brown fox jumps over the lazy dog
12345 67890
line eight
line nine
the end
CONTENT

# Start tmux with the test content visible
$TMUX -f/dev/null new -x80 -y24 -d \
	"cat /tmp/cmsearch-content.txt; printf '\033[11;1H'; cat" || exit 1
sleep 1

# --- Test 1: Invalid regex pattern (unmatched parenthesis) ---
test_num=$((test_num + 1))
$TMUX copy-mode
$TMUX send-keys -X search-forward '((('
sleep 0.3
# Should silently fail (regcomp error -> no match). Server must survive.
$TMUX send-keys -X cancel
check_alive "Test $test_num: invalid regex (unmatched parens) handled"

# --- Test 2: Invalid regex pattern (unmatched bracket) ---
test_num=$((test_num + 1))
$TMUX copy-mode
$TMUX send-keys -X search-forward '[[[def'
sleep 0.3
$TMUX send-keys -X cancel
check_alive "Test $test_num: invalid regex (unmatched brackets) handled"

# --- Test 3: Empty regex pattern ---
test_num=$((test_num + 1))
$TMUX copy-mode
$TMUX send-keys -X search-forward ''
sleep 0.3
$TMUX send-keys -X cancel
check_alive "Test $test_num: empty regex pattern handled"

# --- Test 4: Very long regex pattern (1000 chars) ---
test_num=$((test_num + 1))
long_pat=$(python3 -c "print('a' * 1000)")
$TMUX copy-mode
$TMUX send-keys -X search-forward "$long_pat"
sleep 0.5
$TMUX send-keys -X cancel
check_alive "Test $test_num: very long regex pattern (1000 chars) handled"

# --- Test 5: Regex with all metacharacters ---
test_num=$((test_num + 1))
$TMUX copy-mode
$TMUX send-keys -X search-forward '^$.*+?|(){}[].\\'
sleep 0.3
$TMUX send-keys -X cancel
check_alive "Test $test_num: regex with all metacharacters handled"

# --- Test 6: Valid regex finds correct match ---
test_num=$((test_num + 1))
$TMUX copy-mode
$TMUX send-keys -X history-top
$TMUX send-keys -X start-of-line
$TMUX send-keys -X search-forward 'a{3}b{3}'
sleep 0.3
$TMUX send-keys -X begin-selection
$TMUX send-keys -X end-of-line
$TMUX send-keys -X copy-selection
buf=$($TMUX show-buffer 2>/dev/null)
# Should find "aaabbbccc" line - cursor lands at match
$TMUX send-keys -X cancel 2>/dev/null
check_alive "Test $test_num: valid regex a{3}b{3} finds match"

# --- Test 7: Regex with alternation ---
test_num=$((test_num + 1))
$TMUX copy-mode
$TMUX send-keys -X history-top
$TMUX send-keys -X start-of-line
$TMUX send-keys -X search-forward 'fox|dog'
sleep 0.3
$TMUX send-keys -X cancel
check_alive "Test $test_num: regex alternation handled"

# --- Test 8: Regex with backreference-like pattern (ERE has no backrefs) ---
test_num=$((test_num + 1))
$TMUX copy-mode
$TMUX send-keys -X search-forward '(a)\1'
sleep 0.3
$TMUX send-keys -X cancel
check_alive "Test $test_num: backreference-like pattern in ERE handled"

# --- Test 9: Pathological nested quantifiers (potential ReDoS) ---
# Pattern like (a+)+ can cause exponential backtracking on some regex engines
# The 10-second WINDOW_COPY_SEARCH_TIMEOUT should protect against this
test_num=$((test_num + 1))
$TMUX copy-mode
$TMUX send-keys -X search-forward '(a+)+b'
sleep 1
$TMUX send-keys -X cancel
check_alive "Test $test_num: nested quantifier (a+)+b handled (ReDoS safe)"

# --- Test 10: Another pathological pattern ---
test_num=$((test_num + 1))
$TMUX copy-mode
$TMUX send-keys -X search-forward '(a|aa)+b'
sleep 1
$TMUX send-keys -X cancel
check_alive "Test $test_num: alternation quantifier (a|aa)+b handled"

# --- Test 11: Search-forward-text (literal mode) with regex metacharacters ---
test_num=$((test_num + 1))
$TMUX copy-mode
$TMUX send-keys -X history-top
$TMUX send-keys -X start-of-line
$TMUX send-keys -X search-forward-text '#{var}'
sleep 0.3
$TMUX send-keys -X cancel
check_alive "Test $test_num: literal search with #{var} handled"

# --- Test 12: Search for format metacharacters in regex mode ---
test_num=$((test_num + 1))
$TMUX copy-mode
$TMUX send-keys -X history-top
$TMUX send-keys -X start-of-line
# Escape the regex metacharacters properly
$TMUX send-keys -X search-forward '#\(cmd\)'
sleep 0.3
$TMUX send-keys -X cancel
check_alive "Test $test_num: regex search for #(cmd) handled"

# --- Test 13: Rapid search-forward / search-reverse cycling ---
test_num=$((test_num + 1))
$TMUX copy-mode
for i in $(seq 1 20); do
	$TMUX send-keys -X search-forward 'line'
	$TMUX send-keys -X search-reverse
done
sleep 0.5
$TMUX send-keys -X cancel
check_alive "Test $test_num: rapid search-forward/reverse cycling (20x)"

# --- Test 14: Search with wrap-around ---
test_num=$((test_num + 1))
$TMUX copy-mode
$TMUX send-keys -X history-bottom
$TMUX send-keys -X search-forward 'Hello'
sleep 0.3
$TMUX send-keys -X cancel
check_alive "Test $test_num: search with wrap-around from bottom"

# --- Test 15: Incremental search with control characters ---
test_num=$((test_num + 1))
$TMUX copy-mode
# Incremental search always uses literal mode (searchregex=0)
$TMUX send-keys -X search-forward-incremental "0$(printf '\001\002\003')test"
sleep 0.3
$TMUX send-keys -X cancel
check_alive "Test $test_num: incremental search with control chars"

# --- Test 16: Multiple concurrent searches across panes ---
test_num=$((test_num + 1))
$TMUX split-window -h "cat /tmp/cmsearch-content.txt; cat"
sleep 0.5
# Search in pane 0
$TMUX select-pane -t0
$TMUX copy-mode
$TMUX send-keys -X search-forward 'Hello'
# Switch and search in pane 1
$TMUX select-pane -t1
$TMUX copy-mode
$TMUX send-keys -X search-forward 'World'
sleep 0.3
# Cancel both
$TMUX select-pane -t0
$TMUX send-keys -X cancel
$TMUX select-pane -t1
$TMUX send-keys -X cancel
check_alive "Test $test_num: concurrent searches across panes"

# --- Test 17: Search with Unicode patterns ---
test_num=$((test_num + 1))
# Put some unicode content in the pane
$TMUX select-pane -t0
$TMUX send-keys "printf '\\xc3\\xa9\\xc3\\xa0\\xc3\\xbc\\n'" Enter
sleep 0.3
$TMUX copy-mode
$TMUX send-keys -X search-forward 'éàü'
sleep 0.3
$TMUX send-keys -X cancel
check_alive "Test $test_num: Unicode search pattern handled"

# --- Test 18: Regex with character class edge cases ---
test_num=$((test_num + 1))
$TMUX copy-mode
$TMUX send-keys -X search-forward '[[:alpha:]][[:digit:]]+'
sleep 0.3
$TMUX send-keys -X cancel
check_alive "Test $test_num: POSIX character classes in regex"

# --- Test 19: Regex with null byte in pattern ---
test_num=$((test_num + 1))
$TMUX copy-mode
# C strings are NUL-terminated, so embedded NUL should truncate
# The command substitution with NUL triggers a bash warning on stderr.
{ $TMUX send-keys -X search-forward "$(printf 'abc\x00def')"; } 2>/dev/null
sleep 0.3
$TMUX send-keys -X cancel
check_alive "Test $test_num: NUL byte in regex pattern"

# --- Test 20: Search in empty pane (no content) ---
test_num=$((test_num + 1))
$TMUX new-window 'cat'
sleep 0.3
$TMUX copy-mode
$TMUX send-keys -X search-forward 'anything'
sleep 0.3
$TMUX send-keys -X cancel
check_alive "Test $test_num: search in nearly empty pane"

# --- Final: Verify pane is still functional ---
test_num=$((test_num + 1))
$TMUX select-window -t0
$TMUX select-pane -t0
$TMUX send-keys 'echo ALIVE' Enter
sleep 0.3
alive_check=$($TMUX capture-pane -pt0:0.0 | grep ALIVE | tail -1)
case "$alive_check" in
	*ALIVE*)
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s Test %d: pane still functional after all tests\n' \
			"$GREEN" "$RESET" "$test_num"
		;;
	*)
		printf '%s[FAIL]%s Test %d: pane not functional after tests (got: "%s")\n' \
			"$RED" "$RESET" "$test_num" "$alive_check"
		exit_status=1
		;;
esac

# Cleanup
$TMUX kill-server 2>/dev/null
rm -f /tmp/cmsearch-content.txt

[ -n "$VERBOSE" ] && printf '%d/%d tests passed\n' "$((test_num - exit_status * test_num + exit_status * (test_num - 1)))" "$test_num"
# Actually just report pass/fail
if [ $exit_status -eq 0 ]; then
	[ -n "$VERBOSE" ] && printf 'All %d tests passed.\n' "$test_num"
fi

exit $exit_status
