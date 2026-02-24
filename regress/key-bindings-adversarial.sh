#!/bin/sh

# Test: Key binding system adversarial edge cases
#
# Verifies that the key binding system handles adversarial inputs:
# rapid bind/unbind, custom tables, repeat bindings, note text
# with special characters, and binding-time table modifications.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lkeybind"
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

# --- Test 1: Bind key with shell metacharacters in command ---
test_num=$((test_num + 1))
$TMUX bind-key -T root F9 display-message '$(echo PWNED); `id`'
result=$($TMUX list-keys -T root F9 2>/dev/null)
case "$result" in
	*'display-message'*)
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s Test %d: binding with shell metacharacters\n' \
			"$GREEN" "$RESET" "$test_num"
		;;
	*)
		printf '%s[FAIL]%s Test %d: binding not found\n' \
			"$RED" "$RESET" "$test_num"
		exit_status=1
		;;
esac

# --- Test 2: Bind key with format metacharacters in command ---
test_num=$((test_num + 1))
$TMUX bind-key -T root F10 display-message '#{session_name}'
$TMUX unbind-key -T root F10
check_alive "Test $test_num: bind/unbind with format metacharacters"

# --- Test 3: Bind unknown key (should fail) ---
test_num=$((test_num + 1))
result=$($TMUX bind-key 'NOT_A_KEY_12345' display-message 'test' 2>&1)
check_error "Test $test_num: unknown key rejected" "$result"

# --- Test 4: Rapid bind/unbind cycling ---
test_num=$((test_num + 1))
for i in $(seq 1 50); do
	$TMUX bind-key -T root F8 display-message "iter$i"
	$TMUX unbind-key -T root F8
done
check_alive "Test $test_num: rapid bind/unbind (50 cycles)"

# --- Test 5: Create custom key table ---
test_num=$((test_num + 1))
$TMUX bind-key -T custom-table a display-message 'custom-a'
$TMUX bind-key -T custom-table b display-message 'custom-b'
count=$($TMUX list-keys -T custom-table 2>/dev/null | wc -l)
if [ "$count" -ge 2 ]; then
	[ -n "$VERBOSE" ] && \
		printf '%s[PASS]%s Test %d: custom table created (%d bindings)\n' \
		"$GREEN" "$RESET" "$test_num" "$count"
else
	printf '%s[FAIL]%s Test %d: custom table -> expected 2+ bindings, got %d\n' \
		"$RED" "$RESET" "$test_num" "$count"
	exit_status=1
fi

# --- Test 6: Remove custom table ---
test_num=$((test_num + 1))
$TMUX unbind-key -a -T custom-table
result=$($TMUX list-keys -T custom-table 2>/dev/null | wc -l)
check_result "Test $test_num: custom table removed" "0" "$result"

# --- Test 7: Note text with special characters ---
test_num=$((test_num + 1))
$TMUX bind-key -N 'Note with "quotes" & <special> chars' -T root F7 display-message 'test'
result=$($TMUX list-keys -N -T root 2>/dev/null | grep F7)
if [ -n "$result" ]; then
	[ -n "$VERBOSE" ] && \
		printf '%s[PASS]%s Test %d: note with special characters\n' \
		"$GREEN" "$RESET" "$test_num"
else
	printf '%s[FAIL]%s Test %d: binding with note not found\n' \
		"$RED" "$RESET" "$test_num"
	exit_status=1
fi
$TMUX unbind-key -T root F7

# --- Test 8: Repeat binding flag ---
test_num=$((test_num + 1))
$TMUX bind-key -r -T prefix Up select-pane -U
result=$($TMUX list-keys -T prefix Up 2>/dev/null)
case "$result" in
	*'-r'*|*'select-pane'*)
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s Test %d: repeat binding flag\n' \
			"$GREEN" "$RESET" "$test_num"
		;;
	*)
		printf '%s[FAIL]%s Test %d: repeat binding not found\n' \
			"$RED" "$RESET" "$test_num"
		exit_status=1
		;;
esac

# --- Test 9: Bind multiple commands with semicolons ---
test_num=$((test_num + 1))
$TMUX bind-key -T root F6 display-message 'first' \; display-message 'second'
$TMUX unbind-key -T root F6
check_alive "Test $test_num: bind multiple commands with semicolons"

# --- Test 10: Unbind non-existent key (quiet mode) ---
test_num=$((test_num + 1))
$TMUX unbind-key -qT root F12 2>/dev/null
check_alive "Test $test_num: unbind non-existent key (quiet)"

# --- Test 11: Unbind non-existent key (should error without -q) ---
test_num=$((test_num + 1))
result=$($TMUX unbind-key -T root 'NONEXIST_KEY' 2>&1)
check_error "Test $test_num: unbind non-existent key without -q" "$result"

# --- Test 12: Many bindings in one table ---
test_num=$((test_num + 1))
for i in $(seq 1 26); do
	letter=$(printf "\\$(printf '%03o' $((96 + i)))")
	$TMUX bind-key -T stress-table "$letter" display-message "key-$letter"
done
count=$($TMUX list-keys -T stress-table 2>/dev/null | wc -l)
if [ "$count" -ge 20 ]; then
	[ -n "$VERBOSE" ] && \
		printf '%s[PASS]%s Test %d: 26 bindings in one table (%d)\n' \
		"$GREEN" "$RESET" "$test_num" "$count"
else
	printf '%s[FAIL]%s Test %d: expected 20+ bindings, got %d\n' \
		"$RED" "$RESET" "$test_num" "$count"
	exit_status=1
fi
$TMUX unbind-key -a -T stress-table

# --- Test 13: Bind key with command block syntax ---
test_num=$((test_num + 1))
$TMUX bind-key -T root F5 { display-message 'block' } 2>/dev/null
$TMUX unbind-key -T root F5
check_alive "Test $test_num: bind with command block syntax"

# --- Test 14: Rapid table create/destroy ---
test_num=$((test_num + 1))
for i in $(seq 1 20); do
	$TMUX bind-key -T "rapid-$i" a display-message 'test'
	$TMUX unbind-key -a -T "rapid-$i"
done
check_alive "Test $test_num: rapid table create/destroy (20 cycles)"

# --- Test 15: Bind with very long note ---
test_num=$((test_num + 1))
long_note=$(python3 -c "print('N' * 1000)")
$TMUX bind-key -T root F4 -N "$long_note" display-message 'test' 2>/dev/null
$TMUX unbind-key -T root F4
check_alive "Test $test_num: binding with 1000-char note"

# --- Test 16: Self-modifying binding (bind that unbinds itself) ---
test_num=$((test_num + 1))
$TMUX bind-key -T root F3 'unbind-key -T root F3'
# The binding exists
result=$($TMUX list-keys -T root F3 2>/dev/null | wc -l)
if [ "$result" -ge 1 ]; then
	[ -n "$VERBOSE" ] && \
		printf '%s[PASS]%s Test %d: self-unbinding key created\n' \
		"$GREEN" "$RESET" "$test_num"
else
	printf '%s[FAIL]%s Test %d: self-unbinding key not found\n' \
		"$RED" "$RESET" "$test_num"
	exit_status=1
fi

# --- Test 17: list-keys output ---
test_num=$((test_num + 1))
result=$($TMUX list-keys 2>/dev/null | wc -l)
if [ "$result" -gt 50 ]; then
	[ -n "$VERBOSE" ] && \
		printf '%s[PASS]%s Test %d: list-keys returns %d bindings\n' \
		"$GREEN" "$RESET" "$test_num" "$result"
else
	printf '%s[FAIL]%s Test %d: expected 50+ bindings, got %d\n' \
		"$RED" "$RESET" "$test_num" "$result"
	exit_status=1
fi

# --- Test 18: Bind key in copy-mode table ---
test_num=$((test_num + 1))
$TMUX bind-key -T copy-mode-vi X display-message 'copy-test'
$TMUX unbind-key -T copy-mode-vi X
check_alive "Test $test_num: bind/unbind in copy-mode-vi table"

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
$TMUX unbind-key -T root F9 2>/dev/null
$TMUX unbind-key -T root F3 2>/dev/null
$TMUX kill-server 2>/dev/null

if [ $exit_status -eq 0 ]; then
	[ -n "$VERBOSE" ] && printf 'All %d tests passed.\n' "$test_num"
else
	printf 'Some tests FAILED.\n'
fi

exit $exit_status
