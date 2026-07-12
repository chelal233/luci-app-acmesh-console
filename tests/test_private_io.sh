#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
TMP="$ROOT/tests/.tmp/io"

rm -rf "$TMP"
mkdir -p "$TMP"
chmod 700 "$TMP"
. "$ROOT/tests/lib/host_flock.sh"
acmesh_test_install_flock_shim "$TMP/host-flock"

. "$ACMESH_LIB_DIR/io.sh"

acmesh_test_mode() {
	if command -v stat >/dev/null 2>&1; then
		stat -c %a "$1"
	elif busybox stat -c %a "$1" >/dev/null 2>&1; then
		busybox stat -c %a "$1"
	else
		permissions="$(ls -ld "$1")"
		permissions=${permissions%% *}
		case "$permissions" in
			drwx------) printf '700\n' ;;
			drwxr-xr-x) printf '755\n' ;;
			drwxrwxr-x) printf '775\n' ;;
			drwxrwxrwx) printf '777\n' ;;
			drwxr-x---) printf '750\n' ;;
			-rw-------) printf '600\n' ;;
			*) printf 'unknown\n' ;;
		esac
	fi
}

acmesh_test_process_details() {
	pid="${1:-}"
	case "$pid" in
		''|0|*[!0-9]*) return 1 ;;
	esac
	IFS= read -r stat_line 2>/dev/null < "/proc/$pid/stat" || return 1
	stat_tail=${stat_line##*) }
	[ "$stat_tail" != "$stat_line" ] || return 1
	set -- $stat_tail
	[ "$#" -ge 20 ] || return 1
	state=$1
	parent=$2
	shift 19
	printf '%s %s %s\n' "$state" "$parent" "$1"
}

acmesh_test_self_pid() {
	IFS=' ' read -r self_pid _ < /proc/self/stat
	ACMESH_TEST_SELF_PID=$self_pid
}

acmesh_test_process_starttime() {
	details="$(acmesh_test_process_details "$1")" || return 1
	set -- $details
	printf '%s\n' "$3"
}

acmesh_test_process_matches() {
	pid="$1"
	expected_start="$2"
	expected_parent="${3:-}"
	details="$(acmesh_test_process_details "$pid")" || return 1
	set -- $details
	[ "$1" != Z ] || return 1
	[ "$3" = "$expected_start" ] || return 1
	[ -z "$expected_parent" ] || [ "$2" = "$expected_parent" ]
}

acmesh_test_kill_owned_child() {
	pid="$1"
	starttime="$2"
	parent="$3"
	signal="${4:-TERM}"
	[ -n "$parent" ] || return 1
	acmesh_test_process_matches "$pid" "$starttime" "$parent" || return 1
	command kill "-$signal" "$pid" 2>/dev/null
}

acmesh_test_process_running() {
	pid="${1:-}"
	details="$(acmesh_test_process_details "$pid")" || return 1
	set -- $details
	[ "$1" != Z ]
}

acmesh_test_wait_for_file() {
	path="$1"
	label="$2"
	attempt=0
	while [ ! -s "$path" ]; do
		attempt=$((attempt + 1))
		[ "$attempt" -lt 20 ] || {
			echo "$label did not start"
			return 1
		}
		sleep 1
	done
}

acmesh_test_wait_for_exit() {
	pid="$1"
	limit="$2"
	attempt=0
	while acmesh_test_process_running "$pid"; do
		attempt=$((attempt + 1))
		[ "$attempt" -lt "$limit" ] || return 1
		sleep 1
	done
}

acmesh_test_caller_term_trap() {
	trap_dir="$TMP/caller-trap"
	trap_marker="$trap_dir/term.marker"
	trap_path="$trap_dir/state.json"
	trap_input="$trap_dir/input"
	trap_before="$trap_dir/before"
	trap_after="$trap_dir/after"
	mkdir "$trap_dir"
	chmod 700 "$trap_dir"
	printf '%s\n' trap-preserved > "$trap_input"
	trap 'printf "%s\n" preserved > "$trap_marker"' TERM
	trap > "$trap_before"
	if acmesh_atomic_write "$trap_path" 600 < "$trap_input"; then
		trap > "$trap_after"
		trap - TERM
	else
		trap - TERM
		echo "successful atomic writes should preserve the caller TERM trap"
		return 1
	fi
	if cmp -s "$trap_before" "$trap_after"; then
		return 0
	fi
	echo "successful atomic writes should preserve the caller TERM trap"
	return 1
}

acmesh_test_bounded_atomic_cancel() (
	bounded_dir="$TMP/bounded-cancel"
	bounded_path="$bounded_dir/interrupted.json"
	bounded_ready="$bounded_dir/writer.ready"
	bounded_killed="$bounded_dir/writer.killed"
	bounded_waited="$bounded_dir/post-kill.wait"
	mkdir "$bounded_dir"
	chmod 700 "$bounded_dir"

	cat() {
		trap '' TERM
		printf '%s\n' ready > "$bounded_ready"
		while :; do sleep 1; done
	}
	kill() {
		if [ "${1:-}" = -KILL ]; then
			printf '%s\n' "${2:-}" > "$bounded_killed"
		fi
		command kill "$@"
	}
	wait() {
		if [ -s "$bounded_killed" ] &&
			[ "$(command cat "$bounded_killed")" = "${1:-}" ]; then
			: > "$bounded_waited"
			sleep 30
			return 0
		fi
		command wait "$@"
	}

	acmesh_atomic_write "$bounded_path" 600 < /dev/null &
	bounded_pid=$!
	acmesh_test_self_pid
	bounded_parent=$ACMESH_TEST_SELF_PID
	bounded_start="$(acmesh_test_process_starttime "$bounded_pid")"
	bounded_fixture_cleanup() {
		acmesh_test_kill_owned_child "$bounded_pid" "$bounded_start" "$bounded_parent" KILL 2>/dev/null || :
		command wait "$bounded_pid" 2>/dev/null || :
	}
	trap 'bounded_fixture_cleanup' 0
	trap 'exit 1' HUP INT TERM
	acmesh_test_wait_for_file "$bounded_ready" "TERM-ignoring atomic writer"
	acmesh_test_kill_owned_child "$bounded_pid" "$bounded_start" "$bounded_parent" TERM || {
		echo "bounded cancellation should signal only the original writer process"
		return 1
	}
	bounded_failures=0
	if ! acmesh_test_wait_for_exit "$bounded_pid" 7; then
		echo "atomic cancellation should remain bounded after KILL"
		bounded_failures=$((bounded_failures + 1))
		acmesh_test_kill_owned_child "$bounded_pid" "$bounded_start" "$bounded_parent" KILL || :
	fi
	command wait "$bounded_pid" 2>/dev/null || :
	[ ! -e "$bounded_waited" ] || {
		echo "atomic cancellation should not wait after KILL"
		bounded_failures=$((bounded_failures + 1))
	}
	bounded_tmp=
	for candidate in "$bounded_dir"/.interrupted.json.*; do
		[ -e "$candidate" ] || continue
		bounded_tmp="$candidate"
		break
	done
	[ -z "$bounded_tmp" ] || {
		echo "atomic cancellation should unlink the temporary file before returning"
		bounded_failures=$((bounded_failures + 1))
	}
	bounded_fixture_cleanup
	trap - 0 HUP INT TERM
	[ "$bounded_failures" = 0 ]
)

acmesh_test_cleanup_identity_guard() (
	acmesh_test_self_pid
	identity_parent=$ACMESH_TEST_SELF_PID
	sleep 30 &
	identity_pid=$!
	identity_start="$(acmesh_test_process_starttime "$identity_pid")"
	identity_fixture_cleanup() {
		acmesh_test_kill_owned_child "$identity_pid" "$identity_start" "$identity_parent" KILL 2>/dev/null || :
		wait "$identity_pid" 2>/dev/null || :
	}
	trap 'identity_fixture_cleanup' 0
	trap 'exit 1' HUP INT TERM
	if acmesh_test_kill_owned_child "$identity_pid" "${identity_start}0" "$identity_parent" TERM; then
		echo "cleanup should reject a reused PID with a different starttime"
		return 1
	fi
	acmesh_test_process_matches "$identity_pid" "$identity_start" "$identity_parent" || {
		echo "the starttime guard should not signal the live fixture"
		return 1
	}
	if acmesh_test_kill_owned_child "$identity_pid" "$identity_start" 1 TERM; then
		echo "cleanup should reject a PID with an unrelated current parent"
		return 1
	fi
	acmesh_test_process_matches "$identity_pid" "$identity_start" "$identity_parent" || {
		echo "the parent guard should not signal the live fixture"
		return 1
	}
	acmesh_test_kill_owned_child "$identity_pid" "$identity_start" "$identity_parent" TERM
	wait "$identity_pid" 2>/dev/null || :
	identity_fixture_cleanup
	trap - 0 HUP INT TERM
)

case "${ACMESH_PRIVATE_IO_FOCUS:-}" in
	caller-trap)
		acmesh_test_caller_term_trap
		rm -rf "$ROOT/tests/.tmp"
		echo "test_private_io caller-trap: ok"
		exit 0
		;;
	bounded-cancel)
		acmesh_test_bounded_atomic_cancel
		rm -rf "$ROOT/tests/.tmp"
		echo "test_private_io bounded-cancel: ok"
		exit 0
		;;
	cleanup-identity)
		acmesh_test_cleanup_identity_guard
		rm -rf "$ROOT/tests/.tmp"
		echo "test_private_io cleanup-identity: ok"
		exit 0
		;;
	'') ;;
	*) echo "unknown ACMESH_PRIVATE_IO_FOCUS"; exit 2 ;;
esac

acmesh_test_caller_term_trap
acmesh_test_bounded_atomic_cancel
acmesh_test_cleanup_identity_guard

workspace="$(acmesh_task_workspace 20260710120000-123)"
[ "$(acmesh_test_mode "$workspace")" = 700 ]
printf '%s\n' first | acmesh_atomic_write "$TMP/state.json" 600
printf '%s\n' second | acmesh_atomic_write "$TMP/state.json" 600
[ "$(cat "$TMP/state.json")" = second ]
[ "$(acmesh_test_mode "$TMP/state.json")" = 600 ]
printf '%s\n' textual-mode | acmesh_atomic_write "$TMP/textual-mode.json" 0600
[ "$(cat "$TMP/textual-mode.json")" = textual-mode ]
[ "$(acmesh_test_mode "$TMP/textual-mode.json")" = 600 ]

for rejected_mode in 0644 0666; do
	rejected_dir="$TMP/rejected-$rejected_mode"
	if printf '%s\n' rejected | acmesh_atomic_write "$rejected_dir/state.json" "$rejected_mode"; then
		echo "atomic writes should reject mode $rejected_mode"
		exit 1
	else
		rc=$?
		[ "$rc" = 2 ] || { echo "rejected atomic write mode should return 2"; exit 1; }
	fi
	[ ! -e "$rejected_dir" ] || {
		echo "rejected atomic write modes should not create a temporary directory"
		exit 1
	}
done

unsafe_dir="$TMP/unsafe-existing"
mkdir "$unsafe_dir"
chmod 755 "$unsafe_dir"
unsafe_before="$(ls -ld "$unsafe_dir")"
if acmesh_private_dir "$unsafe_dir"; then
	echo "existing non-private directories should be rejected"
	exit 1
fi
[ "$(ls -ld "$unsafe_dir")" = "$unsafe_before" ] || {
	echo "existing non-private directories should not be changed"
	exit 1
}

race_dir="$TMP/chmod-race"
race_target="$TMP/chmod-race-target"
mkdir "$race_dir" "$race_target"
chmod 700 "$race_dir"
chmod 755 "$race_target"
race_target_before="$(ls -ld "$race_target")"
chmod() {
	case "$1" in
		"$race_dir")
			rmdir "$race_dir"
			ln -s "$race_target" "$race_dir"
			;;
	esac
	command chmod "$@"
}
acmesh_private_dir "$race_dir" || { echo "existing private directories should be accepted"; exit 1; }
unset -f chmod
[ "$(ls -ld "$race_target")" = "$race_target_before" ] || {
	echo "private directory setup followed a replaced pathname"
	exit 1
}
[ ! -L "$race_dir" ] || { echo "private directory setup followed a replaced pathname"; exit 1; }

outside_dir="$TMP/outside"
linked_parent="$TMP/linked-parent"
mkdir "$outside_dir"
chmod 700 "$outside_dir"
ln -s "$outside_dir" "$linked_parent"
if printf '%s\n' blocked | acmesh_atomic_write "$linked_parent/created/state.json" 600; then
	echo "atomic writes should reject symlinked parent directories"
	exit 1
fi
[ ! -e "$outside_dir/created/state.json" ] || {
	echo "atomic writes followed a symlinked parent directory"
	exit 1
}

atomic_dir="$TMP/atomic"
mkdir "$atomic_dir"
chmod 700 "$atomic_dir"
atomic_path="$atomic_dir/state.json"
atomic_stop="$atomic_dir/monitor.stop"
atomic_error="$atomic_dir/monitor.error"
printf '%s' old-content > "$atomic_path"
(
	while [ ! -e "$atomic_stop" ]; do
		content="$(cat "$atomic_path" 2>/dev/null || true)"
		case "$content" in
			old-content|new-first-new-second) ;;
			*) printf '%s\n' "$content" > "$atomic_error"; exit 1 ;;
		esac
	done
) &
atomic_monitor=$!
(
	printf '%s' new-first
	sleep 1
	printf '%s' -new-second
) | acmesh_atomic_write "$atomic_path" 600
touch "$atomic_stop"
wait "$atomic_monitor" || { echo "atomic readers observed partial content"; exit 1; }
[ ! -s "$atomic_error" ] || { echo "atomic readers observed partial content"; exit 1; }
[ "$(cat "$atomic_path")" = new-first-new-second ] || {
	echo "atomic write should publish the complete replacement"
	exit 1
}

cleanup_dir="$TMP/cleanup"
cleanup_fifo="$cleanup_dir/input.fifo"
cleanup_path="$cleanup_dir/interrupted.json"
mkdir "$cleanup_dir"
chmod 700 "$cleanup_dir"
mkfifo "$cleanup_fifo"
(sleep 30) > "$cleanup_fifo" &
cleanup_writer=$!
acmesh_atomic_write "$cleanup_path" 600 < "$cleanup_fifo" &
cleanup_pid=$!
cleanup_tmp=
acmesh_test_self_pid
cleanup_parent=$ACMESH_TEST_SELF_PID
cleanup_writer_start="$(acmesh_test_process_starttime "$cleanup_writer")"
cleanup_start="$(acmesh_test_process_starttime "$cleanup_pid")"
atomic_cancel_fixture_cleanup() {
	acmesh_test_kill_owned_child "$cleanup_pid" "$cleanup_start" "$cleanup_parent" KILL 2>/dev/null || :
	acmesh_test_kill_owned_child "$cleanup_writer" "$cleanup_writer_start" "$cleanup_parent" KILL 2>/dev/null || :
	wait "$cleanup_pid" 2>/dev/null || :
	wait "$cleanup_writer" 2>/dev/null || :
}
trap 'atomic_cancel_fixture_cleanup' 0 HUP INT TERM
cleanup_wait=0
while [ -z "$cleanup_tmp" ]; do
	for candidate in "$cleanup_dir"/.interrupted.json.*; do
		[ -e "$candidate" ] || continue
		cleanup_tmp="$candidate"
		break
	done
	[ -n "$cleanup_tmp" ] && break
	cleanup_wait=$((cleanup_wait + 1))
	[ "$cleanup_wait" -lt 20 ] || { echo "atomic write did not create a temporary file"; exit 1; }
	sleep 1
done
cleanup_direct_child=
cleanup_wait=0
while [ -z "$cleanup_direct_child" ]; do
	for process_stat in /proc/[0-9]*/stat; do
		[ -r "$process_stat" ] || continue
		candidate=${process_stat#/proc/}
		candidate=${candidate%%/*}
		parent="$(awk '{ print $4 }' "$process_stat" 2>/dev/null || :)"
		[ "$parent" = "$cleanup_pid" ] || continue
		cleanup_direct_child="$candidate"
		break
	done
	[ -n "$cleanup_direct_child" ] && break
	cleanup_wait=$((cleanup_wait + 1))
	[ "$cleanup_wait" -lt 20 ] || { echo "atomic write caller did not expose its child"; exit 1; }
	sleep 1
done
cleanup_direct_child_start="$(acmesh_test_process_starttime "$cleanup_direct_child")"

cleanup_failures=0
if ! acmesh_test_kill_owned_child "$cleanup_pid" "$cleanup_start" "$cleanup_parent" TERM; then
	echo "atomic cancellation should signal only the original public writer"
	cleanup_failures=$((cleanup_failures + 1))
fi
if acmesh_test_wait_for_exit "$cleanup_pid" 5; then
	if wait "$cleanup_pid"; then
		cleanup_rc=0
	else
		cleanup_rc=$?
	fi
	[ "$cleanup_rc" -ne 0 ] || {
		echo "cancelled atomic writes should fail"
		cleanup_failures=$((cleanup_failures + 1))
	}
else
	echo "the public atomic-write caller should terminate after TERM"
	cleanup_failures=$((cleanup_failures + 1))
fi
sleep 1
if acmesh_test_process_matches "$cleanup_direct_child" "$cleanup_direct_child_start"; then
	echo "cancelled atomic-write descendants should terminate"
	cleanup_failures=$((cleanup_failures + 1))
fi
[ ! -e "$cleanup_tmp" ] || {
	echo "cancelled atomic writes should remove temporary files"
	cleanup_failures=$((cleanup_failures + 1))
}
[ ! -e "$cleanup_path" ] || {
	echo "cancelled atomic writes should not publish a destination"
	cleanup_failures=$((cleanup_failures + 1))
}
atomic_cancel_fixture_cleanup
trap - 0 HUP INT TERM
[ "$cleanup_failures" = 0 ] || exit 1

lock_failures=0
marker="$TMP/lock-marker"
lock_file="$TMP/request.lock"
(umask 022 && acmesh_lock_run "$lock_file" sh -c 'printf locked > "$1"' sh "$marker")
[ "$(cat "$marker")" = locked ] || {
	echo "lock command should run"
	lock_failures=$((lock_failures + 1))
}
if [ ! -f "$lock_file" ] || [ -L "$lock_file" ] || [ "$(acmesh_test_mode "$lock_file")" != 600 ]; then
	echo "lock path should remain a private regular file"
	lock_failures=$((lock_failures + 1))
fi

pending_public="$TMP/pending-public"
(
	umask 022
	chmod() {
		case "${2:-}" in
			*/pid.pending)
				[ "$(acmesh_test_mode "$2")" = 600 ] || printf '%s\n' public > "$pending_public"
				;;
		esac
		command chmod "$@"
	}
	acmesh_lock_run "$TMP/pending.lock" true
)
if [ -e "$pending_public" ]; then
	echo "lock publication should never expose inherited-umask metadata"
	lock_failures=$((lock_failures + 1))
fi

crash_lock="$TMP/crash-before-publication.lock"
(
	acmesh_lock_publish_owner() {
		sh -c 'kill -KILL "$PPID"'
	}
	acmesh_lock_run "$crash_lock" true
) >/dev/null 2>&1 &
crash_injector=$!
wait "$crash_injector" 2>/dev/null || :
if ! acmesh_lock_run "$crash_lock" true; then
	echo "a crash before owner publication should not strand a lock"
	lock_failures=$((lock_failures + 1))
fi
rm -rf "$crash_lock" "$crash_lock.recover"

forced_lock="$TMP/forced.lock"
forced_child_file="$TMP/forced-child"
forced_parent_file="$TMP/forced-parent"
acmesh_lock_run "$forced_lock" sh -c '
	printf "%s\n" "$$" > "$1"
	printf "%s\n" "$PPID" > "$2"
	while :; do sleep 1; done
' sh "$forced_child_file" "$forced_parent_file" 2>/dev/null &
forced_runner=$!
acmesh_test_wait_for_file "$forced_child_file" "forced lock holder"
acmesh_test_wait_for_file "$forced_parent_file" "forced lock supervisor"
forced_child="$(cat "$forced_child_file")"
forced_parent="$(cat "$forced_parent_file")"
acmesh_test_self_pid
forced_test_parent=$ACMESH_TEST_SELF_PID
forced_child_start="$(acmesh_test_process_starttime "$forced_child")"
forced_runner_start="$(acmesh_test_process_starttime "$forced_runner")"
if [ "$forced_parent" != "$forced_runner" ] ||
	! acmesh_test_process_matches "$forced_child" "$forced_child_start" "$forced_runner" ||
	! acmesh_test_process_matches "$forced_runner" "$forced_runner_start" "$forced_test_parent"; then
	echo "forced lock fixture should capture the original process tree"
	lock_failures=$((lock_failures + 1))
else
	acmesh_test_kill_owned_child "$forced_child" "$forced_child_start" "$forced_runner" KILL || :
	acmesh_test_kill_owned_child "$forced_runner" "$forced_runner_start" "$forced_test_parent" KILL || :
fi
wait "$forced_runner" 2>/dev/null || :
if ! acmesh_lock_run "$forced_lock" true; then
	echo "forced termination should release the kernel lock"
	lock_failures=$((lock_failures + 1))
fi

term_lock="$TMP/term.lock"
term_child_file="$TMP/term-child"
term_parent_file="$TMP/term-parent"
term_runner=
term_child=
term_parent=
term_test_parent=
term_runner_start=
term_child_start=
term_child_orphan_parent=
lock_test_cleanup() {
	acmesh_test_kill_owned_child "$term_child" "$term_child_start" "$term_runner" KILL 2>/dev/null || :
	acmesh_test_kill_owned_child "$term_child" "$term_child_start" "$term_child_orphan_parent" KILL 2>/dev/null || :
	acmesh_test_kill_owned_child "$term_runner" "$term_runner_start" "$term_test_parent" KILL 2>/dev/null || :
}
trap 'lock_test_cleanup' 0 HUP INT TERM
acmesh_lock_run "$term_lock" sh -c '
	trap "" TERM
	printf "%s\n" "$$" > "$1"
	printf "%s\n" "$PPID" > "$2"
	while :; do sleep 1; done
' sh "$term_child_file" "$term_parent_file" 2>/dev/null &
term_runner=$!
acmesh_test_wait_for_file "$term_child_file" "TERM-ignoring lock holder"
acmesh_test_wait_for_file "$term_parent_file" "lock supervisor"
term_child="$(cat "$term_child_file")"
term_parent="$(cat "$term_parent_file")"
acmesh_test_self_pid
term_test_parent=$ACMESH_TEST_SELF_PID
term_child_start="$(acmesh_test_process_starttime "$term_child")"
term_runner_start="$(acmesh_test_process_starttime "$term_runner")"
if [ "$term_parent" != "$term_runner" ] ||
	! acmesh_test_process_matches "$term_child" "$term_child_start" "$term_runner" ||
	! acmesh_test_process_matches "$term_runner" "$term_runner_start" "$term_test_parent"; then
	echo "TERM lock fixture should capture the original process tree"
	lock_failures=$((lock_failures + 1))
else
	acmesh_test_kill_owned_child "$term_runner" "$term_runner_start" "$term_test_parent" TERM || {
		echo "TERM should signal only the original lock supervisor"
		lock_failures=$((lock_failures + 1))
	}
fi
if ! acmesh_test_wait_for_exit "$term_runner" 5; then
	echo "TERM should not hang while a protected command ignores it"
	lock_failures=$((lock_failures + 1))
	acmesh_test_kill_owned_child "$term_runner" "$term_runner_start" "$term_test_parent" KILL 2>/dev/null || :
fi
if ! acmesh_test_process_running "$term_child"; then
	echo "the still-running protected command should retain the inherited lock"
	lock_failures=$((lock_failures + 1))
fi
term_child_details="$(acmesh_test_process_details "$term_child")" || term_child_details=
set -- $term_child_details
if [ "$#" -ne 3 ] || [ "$1" = Z ] || [ "$3" != "$term_child_start" ]; then
	echo "TERM-ignoring lock holder should retain its original process identity"
	lock_failures=$((lock_failures + 1))
else
	term_child_orphan_parent=$2
fi
contention_start="$(date +%s)"
if acmesh_lock_run "$term_lock" true; then
	echo "concurrent lock acquisition should not enter the protected command"
	lock_failures=$((lock_failures + 1))
else
	rc=$?
	[ "$rc" = 75 ] || {
		echo "bounded lock contention should return 75"
		lock_failures=$((lock_failures + 1))
	}
fi
contention_elapsed=$(( $(date +%s) - contention_start ))
if [ "$contention_elapsed" -lt 8 ] || [ "$contention_elapsed" -gt 15 ]; then
	echo "lock contention should remain bounded"
	lock_failures=$((lock_failures + 1))
fi
acmesh_test_kill_owned_child "$term_child" "$term_child_start" "$term_child_orphan_parent" KILL 2>/dev/null || :
wait "$term_runner" 2>/dev/null || :
term_child=
term_parent=
term_runner=
sleep 1
if ! acmesh_lock_run "$term_lock" true; then
	echo "the lock should be reusable after the inherited descriptor closes"
	lock_failures=$((lock_failures + 1))
fi
trap - 0 HUP INT TERM

hostile_lock="$TMP/hostile-content.lock"
printf '%s\n' 999999 > "$hostile_lock"
chmod 600 "$hostile_lock"
if ! acmesh_lock_run "$hostile_lock" true; then
	echo "lock-file content should not be treated as process identity"
	lock_failures=$((lock_failures + 1))
fi

if acmesh_lock_run "$TMP/failing.lock" false; then
	echo "lock command failures should propagate"
	lock_failures=$((lock_failures + 1))
else
	rc=$?
	[ "$rc" = 1 ] || {
		echo "lock command failure should return 1"
		lock_failures=$((lock_failures + 1))
	}
fi

[ "$lock_failures" = 0 ] || exit 1

init_root="$TMP/init"
export ACMESH_CONSOLE_LIB_DIR="$ACMESH_LIB_DIR"
export ACMESH_RUNTIME_DIR="$init_root/run"
export ACMESH_LOG_DIR="$init_root/log"
export ACMESH_TASK_STATE_DIR="$ACMESH_RUNTIME_DIR/tasks"
export ACMESH_TASK_LOG_DIR="$ACMESH_LOG_DIR/tasks"
init_default_touched="$init_root/default-path-used"
mkdir -p "$ACMESH_RUNTIME_DIR/tasks" "$ACMESH_LOG_DIR/tasks"
chmod 700 "$ACMESH_RUNTIME_DIR" "$ACMESH_LOG_DIR"
chmod 755 "$ACMESH_RUNTIME_DIR/tasks" "$ACMESH_LOG_DIR/tasks"
mkdir() {
	if [ "$1" = -p ]; then
		case "$2" in
			/var/run/acmesh-console) printf '%s\n' default > "$init_default_touched"; command mkdir -p "$ACMESH_RUNTIME_DIR"; return ;;
			/var/run/acmesh-console/requests) printf '%s\n' default > "$init_default_touched"; command mkdir -p "$ACMESH_RUNTIME_DIR/requests"; return ;;
			/var/run/acmesh-console/challenges) printf '%s\n' default > "$init_default_touched"; command mkdir -p "$ACMESH_RUNTIME_DIR/challenges"; return ;;
			/var/run/acmesh-console/pending-import) printf '%s\n' default > "$init_default_touched"; command mkdir -p "$ACMESH_RUNTIME_DIR/pending-import"; return ;;
			/var/run/acmesh-console/tasks) printf '%s\n' default > "$init_default_touched"; command mkdir -p "$ACMESH_RUNTIME_DIR/tasks"; return ;;
			/var/log/acmesh-console) printf '%s\n' default > "$init_default_touched"; command mkdir -p "$ACMESH_LOG_DIR"; return ;;
			/var/log/acmesh-console/tasks) printf '%s\n' default > "$init_default_touched"; command mkdir -p "$ACMESH_LOG_DIR/tasks"; return ;;
		esac
	fi
	command mkdir "$@"
}
chmod() {
	case "$2" in
		/var/run/acmesh-console) command chmod "$1" "$ACMESH_RUNTIME_DIR"; return ;;
		/var/run/acmesh-console/requests) command chmod "$1" "$ACMESH_RUNTIME_DIR/requests"; return ;;
		/var/run/acmesh-console/challenges) command chmod "$1" "$ACMESH_RUNTIME_DIR/challenges"; return ;;
		/var/run/acmesh-console/pending-import) command chmod "$1" "$ACMESH_RUNTIME_DIR/pending-import"; return ;;
		/var/run/acmesh-console/tasks) command chmod "$1" "$ACMESH_RUNTIME_DIR/tasks"; return ;;
		/var/log/acmesh-console) command chmod "$1" "$ACMESH_LOG_DIR"; return ;;
		/var/log/acmesh-console/tasks) command chmod "$1" "$ACMESH_LOG_DIR/tasks"; return ;;
	esac
	command chmod "$@"
}
. "$ROOT/root/etc/init.d/acmesh-console"
command -v acmesh_task_private_dir_upgrade >/dev/null 2>&1 || {
	echo "init should provide a task-directory upgrade helper"
	exit 1
}
if ! start_service; then
	echo "start_service should safely tighten legacy root-owned 0755 task directories"
	exit 1
fi
[ ! -e "$init_default_touched" ] || {
	echo "start_service should use configured test directories"
	exit 1
}
unset -f mkdir chmod
for runtime_dir in \
	"$ACMESH_RUNTIME_DIR" \
	"$ACMESH_RUNTIME_DIR/requests" \
	"$ACMESH_RUNTIME_DIR/challenges" \
	"$ACMESH_RUNTIME_DIR/pending-import" \
	"$ACMESH_RUNTIME_DIR/tasks" \
	"$ACMESH_LOG_DIR" \
	"$ACMESH_LOG_DIR/tasks"; do
	[ "$(acmesh_test_mode "$runtime_dir")" = 700 ] || {
		echo "start_service should create private directory $runtime_dir"
		exit 1
	}
done

symlink_target="$init_root/symlink-target"
rm -rf "$symlink_target"
mkdir "$symlink_target"
chmod 755 "$symlink_target"
rm -rf "$ACMESH_RUNTIME_DIR/tasks"
ln -s "$symlink_target" "$ACMESH_RUNTIME_DIR/tasks"
if acmesh_task_private_dir_upgrade "$ACMESH_RUNTIME_DIR/tasks"; then
	echo "task-directory upgrade should reject symlinks"
	exit 1
fi
[ "$(acmesh_test_mode "$symlink_target")" = 755 ] || {
	echo "task-directory upgrade should not chmod a symlink target"
	exit 1
}
rm -f "$ACMESH_RUNTIME_DIR/tasks"
mkdir "$ACMESH_RUNTIME_DIR/tasks"
chmod 700 "$ACMESH_RUNTIME_DIR/tasks"

mode_probe="$init_root/mode-probe"
mkdir "$mode_probe"
chmod 775 "$mode_probe"
if [ "$(acmesh_test_mode "$mode_probe")" = 775 ]; then
	for unsafe_mode in 775 777 750; do
		unsafe_dir="$init_root/unsafe-mode-$unsafe_mode"
		mkdir "$unsafe_dir"
		chmod "$unsafe_mode" "$unsafe_dir"
		if acmesh_task_private_dir_upgrade "$unsafe_dir"; then
			echo "task-directory upgrade should reject mode 0$unsafe_mode"
			exit 1
		fi
		[ "$(acmesh_test_mode "$unsafe_dir")" = "$unsafe_mode" ] || {
			echo "task-directory upgrade should leave mode 0$unsafe_mode unchanged"
			exit 1
		}
	done
else
	printf '%s\n' "test_private_io: SKIP unsafe legacy mode assertions (host filesystem does not expose chmod modes)" >&2
fi
rm -rf "$mode_probe"

if [ "$(id -u)" = 0 ]; then
	untrusted_dir="$init_root/untrusted-owner"
	mkdir "$untrusted_dir"
	chmod 755 "$untrusted_dir"
	chown 65534 "$untrusted_dir"
	if acmesh_task_private_dir_upgrade "$untrusted_dir"; then
		echo "task-directory upgrade should reject non-root ownership"
		chown 0 "$untrusted_dir"
		exit 1
	fi
	[ "$(acmesh_test_mode "$untrusted_dir")" = 755 ] || {
		echo "task-directory upgrade should not chmod an untrusted owner directory"
		chown 0 "$untrusted_dir"
		exit 1
	}
	chown 0 "$untrusted_dir"
fi

rm -rf "$workspace" "$ROOT/tests/.tmp"
echo "test_private_io: ok"
