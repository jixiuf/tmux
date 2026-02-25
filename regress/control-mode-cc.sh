#!/bin/sh

# Test: Control mode (-CC) startup and basic operations
#
# Verifies that tmux -CC (control-control mode) starts correctly,
# creates sessions, attaches to sessions, and handles detach cleanly.

PATH=/bin:/usr/bin
TERM=screen

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Lcontrolcc"
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

# Start server first so -CC tests don't have to wait for config loading
$TMUX -f/dev/null new -x80 -y24 -d -s background || exit 1
sleep 1

# Helper: run tmux -CC with a command and capture control mode output
run_cc () {
	python3 -c "
import pty, os, select, time, signal, sys

pid, fd = pty.openpty()
child = os.fork()
if child == 0:
    os.close(fd)
    os.setsid()
    os.dup2(pid, 0)
    os.dup2(pid, 1)
    os.dup2(pid, 2)
    os.close(pid)
    args = sys.argv[1:]
    os.execvp(args[0], args)
else:
    os.close(pid)
    output = b''
    start = time.time()
    while time.time() - start < 5:
        r, _, _ = select.select([fd], [], [], 0.5)
        if r:
            try:
                data = os.read(fd, 4096)
                if not data:
                    break
                output += data
            except OSError:
                break
        # Stop early if we got %exit
        if b'%exit' in output:
            break
    try:
        os.kill(child, signal.SIGTERM)
    except:
        pass
    try:
        os.waitpid(child, 0)
    except:
        pass
    os.close(fd)
    sys.stdout.write(output.decode('utf-8', errors='replace'))
" "$@" 2>/dev/null
}

# --- Test 1: -CC new-session -d creates session ---
test_num=$((test_num + 1))
output=$(run_cc $TEST_TMUX -Lcontrolcc -CC new-session -d -s cctest1)
case "$output" in
	*"%begin"*|*"%sessions-changed"*|*"%exit"*)
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s Test %d: -CC new-session -d produces control output\n' \
			"$GREEN" "$RESET" "$test_num"
		;;
	*)
		printf '%s[FAIL]%s Test %d: -CC new-session -d -> got "%s"\n' \
			"$RED" "$RESET" "$test_num" "$(echo "$output" | head -3)"
		exit_status=1
		;;
esac

# --- Test 2: -CC shows DCS escape (P1000p) ---
test_num=$((test_num + 1))
case "$output" in
	*"P1000p"*)
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s Test %d: -CC outputs DCS escape P1000p\n' \
			"$GREEN" "$RESET" "$test_num"
		;;
	*)
		printf '%s[FAIL]%s Test %d: -CC DCS escape -> got "%s"\n' \
			"$RED" "$RESET" "$test_num" "$(echo "$output" | head -1)"
		exit_status=1
		;;
esac

# --- Test 3: Session was actually created ---
test_num=$((test_num + 1))
sleep 0.5
result=$($TMUX list-sessions -F '#{session_name}' 2>/dev/null | grep 'cctest1')
check_result "Test $test_num: session cctest1 exists" "cctest1" "$result"

# --- Test 4: -CC attach to existing session ---
test_num=$((test_num + 1))
output=$(run_cc $TEST_TMUX -Lcontrolcc -CC attach -t cctest1)
case "$output" in
	*"P1000p"*"%begin"*|*"P1000p"*"%session-changed"*)
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s Test %d: -CC attach produces control output\n' \
			"$GREEN" "$RESET" "$test_num"
		;;
	*)
		printf '%s[FAIL]%s Test %d: -CC attach -> got "%s"\n' \
			"$RED" "$RESET" "$test_num" "$(echo "$output" | head -3)"
		exit_status=1
		;;
esac

# --- Test 5: -CC new-session -A (attach-or-create) ---
test_num=$((test_num + 1))
output=$(run_cc $TEST_TMUX -Lcontrolcc -CC new-session -A -s cctest1)
case "$output" in
	*"P1000p"*"%begin"*|*"P1000p"*"%session-changed"*)
		[ -n "$VERBOSE" ] && \
			printf '%s[PASS]%s Test %d: -CC new-session -A attaches\n' \
			"$GREEN" "$RESET" "$test_num"
		;;
	*)
		printf '%s[FAIL]%s Test %d: -CC new-session -A -> got "%s"\n' \
			"$RED" "$RESET" "$test_num" "$(echo "$output" | head -3)"
		exit_status=1
		;;
esac

# --- Test 6: Single -C mode (no DCS escape) ---
test_num=$((test_num + 1))
output=$(run_cc $TEST_TMUX -Lcontrolcc -C new-session -d -s cctest2)
case "$output" in
	*"%begin"*|*"%sessions-changed"*|*"%exit"*)
		# Check no DCS escape
		case "$output" in
			*"P1000p"*)
				printf '%s[FAIL]%s Test %d: -C should not output DCS P1000p\n' \
					"$RED" "$RESET" "$test_num"
				exit_status=1
				;;
			*)
				[ -n "$VERBOSE" ] && \
					printf '%s[PASS]%s Test %d: -C mode works without DCS\n' \
					"$GREEN" "$RESET" "$test_num"
				;;
		esac
		;;
	*)
		printf '%s[FAIL]%s Test %d: -C mode -> got "%s"\n' \
			"$RED" "$RESET" "$test_num" "$(echo "$output" | head -3)"
		exit_status=1
		;;
esac

# --- Test 7: Multiple -CC sessions ---
test_num=$((test_num + 1))
for i in 3 4 5; do
	run_cc $TEST_TMUX -Lcontrolcc -CC new-session -d -s "cctest$i" >/dev/null
	sleep 0.3
done
count=$($TMUX list-sessions 2>/dev/null | wc -l)
if [ "$count" -ge 5 ]; then
	[ -n "$VERBOSE" ] && \
		printf '%s[PASS]%s Test %d: multiple -CC sessions (%d sessions)\n' \
		"$GREEN" "$RESET" "$test_num" "$count"
else
	printf '%s[FAIL]%s Test %d: expected >= 5 sessions, got %d\n' \
		"$RED" "$RESET" "$test_num" "$count"
	exit_status=1
fi

# --- Test 8: Server still alive after all operations ---
test_num=$((test_num + 1))
result=$($TMUX list-sessions 2>&1)
if [ $? -eq 0 ]; then
	[ -n "$VERBOSE" ] && \
		printf '%s[PASS]%s Test %d: server alive after -CC operations\n' \
		"$GREEN" "$RESET" "$test_num"
else
	printf '%s[FAIL]%s Test %d: server DEAD after -CC operations\n' \
		"$RED" "$RESET" "$test_num"
	exit_status=1
fi

# Cleanup
$TMUX kill-server 2>/dev/null

if [ $exit_status -eq 0 ]; then
	[ -n "$VERBOSE" ] && printf 'All %d tests passed.\n' "$test_num"
else
	printf 'Some tests FAILED.\n'
fi

exit $exit_status
