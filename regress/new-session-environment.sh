#!/bin/sh

# new session environment

PATH=/bin:/usr/bin

[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f ../tmux)
TMUX="$TEST_TMUX -Ltest"
$TMUX kill-server 2>/dev/null

TERM=$($TMUX start \; show -gv default-terminal)
TMP=$(mktemp)
OUT=$(mktemp)
SCRIPT=$(mktemp)
EXPECTED=$(mktemp)
trap "rm -f $TMP $OUT $SCRIPT $EXPECTED" 0 1 15

cat <<EOF >$SCRIPT
(
echo TERM=\$TERM
echo PWD=\$(pwd)
echo PATH=\$PATH
echo SHELL=\$SHELL
echo TEST=\$TEST
) >$OUT
EOF

cat <<EOF >$TMP
new -- /bin/sh $SCRIPT
EOF

exit_status=0

check_env() {
	label=$1
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

# Test 1: start with new session command in config.
(cd /; env -i TERM=ansi TEST=test1 PATH=1 SHELL=/bin/sh \
	$TMUX -f$TMP start) || exit 1
sleep 1
cat <<EOF >$EXPECTED
TERM=$TERM
PWD=/
PATH=1
SHELL=/bin/sh
TEST=test1
EOF
check_env "start with config new-session"

# Test 2: new -d with explicit command.
(cd /; env -i TERM=ansi TEST=test2 PATH=2 SHELL=/bin/sh \
	$TMUX -f$TMP new -d -- /bin/sh $SCRIPT) || exit 1
sleep 1
cat <<EOF >$EXPECTED
TERM=$TERM
PWD=/
PATH=2
SHELL=/bin/sh
TEST=test2
EOF
check_env "new -d with explicit command"

# Test 3: new -d source (inherits previous session env).
(cd /; env -i TERM=ansi TEST=test3 PATH=3 SHELL=/bin/sh \
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
