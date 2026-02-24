#!/bin/sh

# new session environment

PATH=/bin:/usr/bin

TESTDIR=$(cd -- "$(dirname "$0")" && pwd)
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f "$TESTDIR/../tmux")
TMUX="$TEST_TMUX -Ltest"
$TMUX kill-server 2>/dev/null

TERM=$($TMUX start \; show -gv default-terminal)
TMP=$(mktemp)
OUT=$(mktemp)
SCRIPT=$(mktemp)
EXPECTED=$(mktemp)
DONE=$(mktemp -u)
trap "rm -f $TMP $OUT $SCRIPT $EXPECTED $DONE" 0 1 15

cat <<EOF >$SCRIPT
(
echo TERM=\$TERM
echo PWD=\$(pwd)
echo PATH=\$PATH
echo SHELL=\$SHELL
echo TEST=\$TEST
) >$OUT
: >$DONE
EOF

cat <<EOF >$TMP
new -- /bin/sh $SCRIPT
EOF

exit_status=0

wait_for_output() {
	for _i in $(seq 1 50); do
		[ -f "$DONE" ] && return 0
		sleep 0.1
	done
	return 1
}

check_env() {
	label=$1
	if ! wait_for_output; then
		echo "[FAIL] $label (timed out waiting for output)"
		exit_status=1
		return
	fi
	if cmp -s "$EXPECTED" "$OUT"; then
		[ -n "$VERBOSE" ] && echo "[PASS] $label"
	else
		echo "[FAIL] $label"
		echo "  expected:"
		sed 's/^/    /' < "$EXPECTED"
		echo "  got:"
		sed 's/^/    /' < "$OUT"
		exit_status=1
	fi
}

# Preserve TMUX_TMPDIR through env -i so parallel runs stay isolated.
TMPDIR_ENV=
[ -n "$TMUX_TMPDIR" ] && TMPDIR_ENV="TMUX_TMPDIR=$TMUX_TMPDIR"

# Test 1: start with new session command in config.
rm -f $DONE
(cd /; env -i TERM=ansi TEST=test1 PATH=1 SHELL=/bin/sh $TMPDIR_ENV \
	$TMUX -f$TMP start) || exit 1
cat <<EOF >$EXPECTED
TERM=$TERM
PWD=/
PATH=1
SHELL=/bin/sh
TEST=test1
EOF
check_env "start with config new-session"

# Test 2: new -d with explicit command.
rm -f $DONE
(cd /; env -i TERM=ansi TEST=test2 PATH=2 SHELL=/bin/sh $TMPDIR_ENV \
	$TMUX -f$TMP new -d -- /bin/sh $SCRIPT) || exit 1
cat <<EOF >$EXPECTED
TERM=$TERM
PWD=/
PATH=2
SHELL=/bin/sh
TEST=test2
EOF
check_env "new -d with explicit command"

# Test 3: new -d source (inherits previous session env).
# This test sources the tmux config (which runs `new` as a shell command
# and fails), but verifies $OUT still has test 2's values — meaning the
# new session inherited test 2's environment. The SCRIPT is not re-run,
# so we just wait for the session to start.
(cd /; env -i TERM=ansi TEST=test3 PATH=3 SHELL=/bin/sh $TMPDIR_ENV \
	$TMUX -f/dev/null new -d source $TMP) || exit 1
sleep 1
cat <<EOF >$EXPECTED
TERM=$TERM
PWD=/
PATH=2
SHELL=/bin/sh
TEST=test2
EOF
check_env "new -d source (inherits previous env)"

$TMUX kill-server 2>/dev/null

exit $exit_status
