#!/bin/sh

PATH=/bin:/usr/bin
TERM=screen

[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f ../tmux)
TMUX="$TEST_TMUX -Ltest"
$TMUX kill-server 2>/dev/null
sleep 1
$TMUX -f/dev/null new -x20 -y2 -d || exit 1
sleep 1
$TMUX set -g escape-time 0

exit_status=0
n=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"; $TMUX kill-server 2>/dev/null' EXIT
RED=$(printf '\033[31m')
GREEN=$(printf '\033[32m')
RESET=$(printf '\033[0m')

add_test () {
	key=$1
	expected_code=$2

	W=$($TMUX new-window -PF '#{window_id}' -- sh -c 'stty raw -echo && cat -tv')
	printf '%s\n' "$W" > "$TMPDIR/win_$n"
	printf '%s\n' "$key" > "$TMPDIR/key_$n"
	printf '%s\n' "$expected_code" > "$TMPDIR/exp_$n"
	n=$((n + 1))

	shift
	shift

	if [ "$1" = "--" ]; then
		shift
		add_test "$@"
	fi
}

check_tests () {
	# Send all keys in a single tmux invocation.
	set --
	i=0
	while [ "$i" -lt "$n" ]; do
		IFS= read -r W < "$TMPDIR/win_$i"
		IFS= read -r key < "$TMPDIR/key_$i"
		if [ "$i" -gt 0 ]; then
			set -- "$@" ";"
		fi
		set -- "$@" send-keys -t"$W" "$key" EOL
		i=$((i + 1))
	done
	$TMUX "$@" 2>/dev/null

	# Let all outputs arrive.
	sleep 1

	# Capture all panes at once via source-file.
	i=0
	while [ "$i" -lt "$n" ]; do
		IFS= read -r W < "$TMPDIR/win_$i"
		printf 'capture-pane -t%s\nsave-buffer "%s/out_%d"\ndelete-buffer\n' \
			"$W" "$TMPDIR" "$i"
		i=$((i + 1))
	done > "$TMPDIR/capture_cmds"
	$TMUX source-file "$TMPDIR/capture_cmds"

	# Check all results from saved files.
	i=0
	while [ "$i" -lt "$n" ]; do
		IFS= read -r key < "$TMPDIR/key_$i"
		IFS= read -r expected_code < "$TMPDIR/exp_$i"
		IFS= read -r first_line < "$TMPDIR/out_$i" 2>/dev/null
		actual_code=${first_line%%EOL*}

		if [ "$actual_code" = "$expected_code" ]; then
			if [ -n "$VERBOSE" ]; then
				printf '%sPASS%s %s -> %s\n' "$GREEN" "$RESET" "$key" "$actual_code"
			fi
		else
			printf '%sFAIL%s %s -> %s (Got: %s)\n' "$RED" "$RESET" "$key" "$expected_code" "$actual_code"
			exit_status=1
		fi
		i=$((i + 1))
	done

	# Clean up batch files.
	rm -f "$TMPDIR"/out_* "$TMPDIR/capture_cmds"
	n=0
}

add_test 'C-Space' '^@'
add_test 'C-a' '^A'	 -- 'M-C-a' '^[^A'
add_test 'C-b' '^B'	 -- 'M-C-b' '^[^B'
add_test 'C-c' '^C'	 -- 'M-C-c' '^[^C'
add_test 'C-d' '^D'	 -- 'M-C-d' '^[^D'
add_test 'C-e' '^E'	 -- 'M-C-e' '^[^E'
add_test 'C-f' '^F'	 -- 'M-C-f' '^[^F'
add_test 'C-g' '^G'	 -- 'M-C-g' '^[^G'
add_test 'C-h' '^H'	 -- 'M-C-h' '^[^H'
add_test 'C-i' '^I'	 -- 'M-C-i' '^[^I'
add_test 'C-j' ''	 -- 'M-C-j' '^[' # NL
add_test 'C-k' '^K'	 -- 'M-C-k' '^[^K'
add_test 'C-l' '^L'	 -- 'M-C-l' '^[^L'
add_test 'C-m' '^M'	 -- 'M-C-m' '^[^M'
add_test 'C-n' '^N'	 -- 'M-C-n' '^[^N'
add_test 'C-o' '^O'	 -- 'M-C-o' '^[^O'
add_test 'C-p' '^P'	 -- 'M-C-p' '^[^P'
add_test 'C-q' '^Q'	 -- 'M-C-q' '^[^Q'
add_test 'C-r' '^R'	 -- 'M-C-r' '^[^R'
add_test 'C-s' '^S'	 -- 'M-C-s' '^[^S'
add_test 'C-t' '^T'	 -- 'M-C-t' '^[^T'
add_test 'C-u' '^U'	 -- 'M-C-u' '^[^U'
add_test 'C-v' '^V'	 -- 'M-C-v' '^[^V'
add_test 'C-w' '^W'	 -- 'M-C-w' '^[^W'
add_test 'C-x' '^X'	 -- 'M-C-x' '^[^X'
add_test 'C-y' '^Y'	 -- 'M-C-y' '^[^Y'
add_test 'C-z' '^Z'	 -- 'M-C-z' '^[^Z'
add_test 'Escape' '^[' -- 'M-Escape' '^[^['
add_test "C-\\" "^\\"	 -- "M-C-\\" "^[^\\"
add_test 'C-]' '^]'	 -- 'M-C-]' '^[^]'
add_test 'C-^' '^^'	 -- 'M-C-^' '^[^^'
add_test 'C-_' '^_'	 -- 'M-C-_' '^[^_'
add_test 'Space' ' '	 -- 'M-Space' '^[ '
add_test '!' '!'	 -- 'M-!' '^[!'
add_test '"' '"'	 -- 'M-"' '^["'
add_test '#' '#'	 -- 'M-#' '^[#'
add_test '$' '$'	 -- 'M-$' '^[$'
add_test '%' '%'	 -- 'M-%' '^[%'
add_test '&' '&'	 -- 'M-&' '^[&'
add_test "'" "'"	 -- "M-'" "^['"
add_test '(' '('	 -- 'M-(' '^[('
add_test ')' ')'	 -- 'M-)' '^[)'
add_test '*' '*'	 -- 'M-*' '^[*'
add_test '+' '+'	 -- 'M-+' '^[+'
add_test ',' ','	 -- 'M-,' '^[,'
add_test '-' '-'	 -- 'M--' '^[-'
add_test '.' '.'	 -- 'M-.' '^[.'
add_test '/' '/'	 -- 'M-/' '^[/'
add_test '0' '0'	 -- 'M-0' '^[0'
add_test '1' '1'	 -- 'M-1' '^[1'
add_test '2' '2'	 -- 'M-2' '^[2'
add_test '3' '3'	 -- 'M-3' '^[3'
add_test '4' '4'	 -- 'M-4' '^[4'
add_test '5' '5'	 -- 'M-5' '^[5'
add_test '6' '6'	 -- 'M-6' '^[6'
add_test '7' '7'	 -- 'M-7' '^[7'
add_test '8' '8'	 -- 'M-8' '^[8'
add_test '9' '9'	 -- 'M-9' '^[9'
add_test ':' ':'	 -- 'M-:' '^[:'
add_test '\;' ';'	 -- 'M-\;' '^[;'
add_test '<' '<'	 -- 'M-<' '^[<'
add_test '=' '='	 -- 'M-=' '^[='
add_test '>' '>'	 -- 'M->' '^[>'
add_test '?' '?'	 -- 'M-?' '^[?'
add_test '@' '@'	 -- 'M-@' '^[@'
add_test 'A' 'A'	 -- 'M-A' '^[A'
add_test 'B' 'B'	 -- 'M-B' '^[B'
add_test 'C' 'C'	 -- 'M-C' '^[C'
add_test 'D' 'D'	 -- 'M-D' '^[D'
add_test 'E' 'E'	 -- 'M-E' '^[E'
add_test 'F' 'F'	 -- 'M-F' '^[F'
add_test 'G' 'G'	 -- 'M-G' '^[G'
add_test 'H' 'H'	 -- 'M-H' '^[H'
add_test 'I' 'I'	 -- 'M-I' '^[I'
add_test 'J' 'J'	 -- 'M-J' '^[J'
add_test 'K' 'K'	 -- 'M-K' '^[K'
add_test 'L' 'L'	 -- 'M-L' '^[L'
add_test 'M' 'M'	 -- 'M-M' '^[M'
add_test 'N' 'N'	 -- 'M-N' '^[N'
add_test 'O' 'O'	 -- 'M-O' '^[O'
add_test 'P' 'P'	 -- 'M-P' '^[P'
add_test 'Q' 'Q'	 -- 'M-Q' '^[Q'
add_test 'R' 'R'	 -- 'M-R' '^[R'
add_test 'S' 'S'	 -- 'M-S' '^[S'
add_test 'T' 'T'	 -- 'M-T' '^[T'
add_test 'U' 'U'	 -- 'M-U' '^[U'
add_test 'V' 'V'	 -- 'M-V' '^[V'
add_test 'W' 'W'	 -- 'M-W' '^[W'
add_test 'X' 'X'	 -- 'M-X' '^[X'
add_test 'Y' 'Y'	 -- 'M-Y' '^[Y'
add_test 'Z' 'Z'	 -- 'M-Z' '^[Z'
add_test '[' '['	 -- 'M-[' '^[['
add_test "\\" "\\"	 -- "M-\\" "^[\\"
add_test ']' ']'	 -- 'M-]' '^[]'
add_test '^' '^'	 -- 'M-^' '^[^'
add_test '_' '_'	 -- 'M-_' '^[_'
add_test '`' '`'	 -- 'M-`' '^[`'
add_test 'a' 'a'	 -- 'M-a' '^[a'
add_test 'b' 'b'	 -- 'M-b' '^[b'
add_test 'c' 'c'	 -- 'M-c' '^[c'
add_test 'd' 'd'	 -- 'M-d' '^[d'
add_test 'e' 'e'	 -- 'M-e' '^[e'
add_test 'f' 'f'	 -- 'M-f' '^[f'
add_test 'g' 'g'	 -- 'M-g' '^[g'
add_test 'h' 'h'	 -- 'M-h' '^[h'
add_test 'i' 'i'	 -- 'M-i' '^[i'
add_test 'j' 'j'	 -- 'M-j' '^[j'
add_test 'k' 'k'	 -- 'M-k' '^[k'
add_test 'l' 'l'	 -- 'M-l' '^[l'
add_test 'm' 'm'	 -- 'M-m' '^[m'
add_test 'n' 'n'	 -- 'M-n' '^[n'
add_test 'o' 'o'	 -- 'M-o' '^[o'
add_test 'p' 'p'	 -- 'M-p' '^[p'
add_test 'q' 'q'	 -- 'M-q' '^[q'
add_test 'r' 'r'	 -- 'M-r' '^[r'
add_test 's' 's'	 -- 'M-s' '^[s'
add_test 't' 't'	 -- 'M-t' '^[t'
add_test 'u' 'u'	 -- 'M-u' '^[u'
add_test 'v' 'v'	 -- 'M-v' '^[v'
add_test 'w' 'w'	 -- 'M-w' '^[w'
add_test 'x' 'x'	 -- 'M-x' '^[x'
add_test 'y' 'y'	 -- 'M-y' '^[y'
add_test 'z' 'z'	 -- 'M-z' '^[z'
add_test '{' '{'	 -- 'M-{' '^[{'
add_test '|' '|'	 -- 'M-|' '^[|'
add_test '}' '}'	 -- 'M-}' '^[}'
add_test '~' '~'	 -- 'M-~' '^[~'

add_test 'Tab' '^I'    -- 'M-Tab' '^[^I'
add_test 'BSpace' '^?' -- 'M-BSpace' '^[^?'

## These cannot be sent, is that intentional?
## add_test 'PasteStart' "^[[200~"
## add_test 'PasteEnd' "^[[201~"

add_test 'F1' "^[OP"
add_test 'F2' "^[OQ"
add_test 'F3' "^[OR"
add_test 'F4' "^[OS"
add_test 'F5' "^[[15~"
add_test 'F6' "^[[17~"
add_test 'F8' "^[[19~"
add_test 'F9' "^[[20~"
add_test 'F10' "^[[21~"
add_test 'F11' "^[[23~"
add_test 'F12' "^[[24~"

add_test 'IC' '^[[2~'
add_test 'Insert' '^[[2~'
add_test 'DC' '^[[3~'
add_test 'Delete' '^[[3~'

## Why do these differ from tty-keys?
add_test 'Home' '^[[1~'
add_test 'End' '^[[4~'

add_test 'NPage' '^[[6~'
add_test 'PageDown' '^[[6~'
add_test 'PgDn' '^[[6~'
add_test 'PPage' '^[[5~'
add_test 'PageUp' '^[[5~'
add_test 'PgUp' '^[[5~'

add_test 'BTab' '^[[Z'
add_test 'C-S-Tab' '^I'

add_test 'Up' '^[[A'
add_test 'Down' '^[[B'
add_test 'Right' '^[[C'
add_test 'Left' '^[[D'

# add_test 'KPEnter'
add_test 'KP*' '*' -- 'M-KP*' '^[*'
add_test 'KP+' '+' -- 'M-KP+' '^[+'
add_test 'KP-' '-' -- 'M-KP-' '^[-'
add_test 'KP.' '.' -- 'M-KP.' '^[.'
add_test 'KP/' '/' -- 'M-KP/' '^[/'
add_test 'KP0' '0' -- 'M-KP0' '^[0'
add_test 'KP1' '1' -- 'M-KP1' '^[1'
add_test 'KP2' '2' -- 'M-KP2' '^[2'
add_test 'KP3' '3' -- 'M-KP3' '^[3'
add_test 'KP4' '4' -- 'M-KP4' '^[4'
add_test 'KP5' '5' -- 'M-KP5' '^[5'
add_test 'KP6' '6' -- 'M-KP6' '^[6'
add_test 'KP7' '7' -- 'M-KP7' '^[7'
add_test 'KP8' '8' -- 'M-KP8' '^[8'
add_test 'KP9' '9' -- 'M-KP9' '^[9'

# All windows created; wait for cat processes to start.
sleep 2

# Check first batch.
check_tests

# Extended keys
$TMUX set -g extended-keys always

add_extended_test () {
	extended_key=$1
	expected_code_pattern=$2

	expected_code=$(printf '%s' "$expected_code_pattern" | sed -e 's/;_/;2/')
	add_test "S-$extended_key" "$expected_code"

	expected_code=$(printf '%s' "$expected_code_pattern" | sed -e 's/;_/;3/')
	add_test "M-$extended_key" "$expected_code"

	expected_code=$(printf '%s' "$expected_code_pattern" | sed -e 's/;_/;4/')
	add_test "S-M-$extended_key" "$expected_code"

	expected_code=$(printf '%s' "$expected_code_pattern" | sed -e 's/;_/;5/')
	add_test "C-$extended_key" "$expected_code"

	expected_code=$(printf '%s' "$expected_code_pattern" | sed -e 's/;_/;6/')
	add_test "S-C-$extended_key" "$expected_code"

	expected_code=$(printf '%s' "$expected_code_pattern" | sed -e 's/;_/;7/')
	add_test "C-M-$extended_key" "$expected_code"

	expected_code=$(printf '%s' "$expected_code_pattern" | sed -e 's/;_/;8/')
	add_test "S-C-M-$extended_key" "$expected_code"
}

## Many of these pass without extended keys enabled -- are they extended keys?
add_extended_test 'F1' '^[[1;_P'
add_extended_test 'F2' "^[[1;_Q"
add_extended_test 'F3' "^[[1;_R"
add_extended_test 'F4' "^[[1;_S"
add_extended_test 'F5' "^[[15;_~"
add_extended_test 'F6' "^[[17;_~"
add_extended_test 'F8' "^[[19;_~"
add_extended_test 'F9' "^[[20;_~"
add_extended_test 'F10' "^[[21;_~"
add_extended_test 'F11' "^[[23;_~"
add_extended_test 'F12' "^[[24;_~"

add_extended_test 'Up' '^[[1;_A'
add_extended_test 'Down' '^[[1;_B'
add_extended_test 'Right' '^[[1;_C'
add_extended_test 'Left' '^[[1;_D'

add_extended_test 'Home' '^[[1;_H'
add_extended_test 'End' '^[[1;_F'

add_extended_test 'PPage' '^[[5;_~'
add_extended_test 'PageUp' '^[[5;_~'
add_extended_test 'PgUp' '^[[5;_~'
add_extended_test 'NPage' '^[[6;_~'
add_extended_test 'PageDown' '^[[6;_~'
add_extended_test 'PgDn' '^[[6;_~'

add_extended_test 'IC' '^[[2;_~'
add_extended_test 'Insert' '^[[2;_~'
add_extended_test 'DC' '^[[3;_~'
add_extended_test 'Delete' '^[[3;_~'

add_test 'C-Tab' "^[[27;5;9~"
add_test 'C-S-Tab' "^[[27;6;9~"

# All extended key windows created; wait for cat processes to start.
sleep 2

# Check second batch.
check_tests

exit $exit_status
