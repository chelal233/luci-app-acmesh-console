#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
export ACMESH_TASK_STATE_DIR="$ROOT/tests/.tmp/tasks-state"
export ACMESH_TASK_LOG_DIR="$ROOT/tests/.tmp/tasks-log"
rm -rf "$ROOT/tests/.tmp"
mkdir "$ROOT/tests/.tmp"
chmod 700 "$ROOT/tests/.tmp"
. "$ROOT/tests/lib/host_flock.sh"
acmesh_test_install_flock_shim "$ROOT/tests/.tmp/task-flock"
printf '%s\n' '11111111-2222-3333-4444-555555555555' > "$ROOT/tests/.tmp/boot_id"
ACMESH_BOOT_ID_FILE="$ROOT/tests/.tmp/boot_id"
export ACMESH_BOOT_ID_FILE

. "$ACMESH_LIB_DIR/task.sh"

acmesh_task_worker_identity_load || { echo "worker identity should load from procfs"; exit 1; }
[ -n "$acmesh_worker_pid" ] && [ -n "$acmesh_worker_starttime" ] && [ -n "$acmesh_worker_boot_id" ] || {
	echo "worker identity fields should be populated"
	exit 1
}
acmesh_task_worker_is_alive "$acmesh_worker_pid" "$acmesh_worker_starttime" "$acmesh_worker_boot_id" || {
	echo "current worker identity should be alive"
	exit 1
}

task_mode() {
	if command -v stat >/dev/null 2>&1; then
		stat -c %a "$1"
	elif busybox stat -c %a "$1" >/dev/null 2>&1; then
		busybox stat -c %a "$1"
	else
		permissions="$(ls -ld "$1")"
		permissions=${permissions%% *}
		case "$permissions" in
			drwx------) printf '700\n' ;;
			-rw-------) printf '600\n' ;;
			*) printf 'unknown\n' ;;
		esac
	fi
}

TASK_POSIX_MODE_CHECKS=1
if [ "$(task_mode "$ROOT/tests/.tmp")" != 700 ]; then
	TASK_POSIX_MODE_CHECKS=0
	acmesh_private_dir() (
		candidate="${1:-}"
		[ -n "$candidate" ] && [ "$candidate" != / ] || exit 2
		[ ! -L "$candidate" ] || exit 1
		mkdir -p "$candidate" && [ -d "$candidate" ] && [ ! -L "$candidate" ]
	)
	acmesh_lock_file_prepare() (
		lock_file="${1:-}"
		[ -n "$lock_file" ] || exit 1
		[ ! -L "$lock_file" ] || exit 1
		if [ ! -e "$lock_file" ]; then
			(umask 077; set -C; : > "$lock_file") 2>/dev/null || exit 1
		fi
		[ -f "$lock_file" ] && [ ! -L "$lock_file" ]
	)
	acmesh_private_file_is_secure() (
		candidate="${1:-}"
		[ -n "$candidate" ] && [ -f "$candidate" ] && [ ! -L "$candidate" ]
	)
	printf '%s\n' "test_task: SKIP POSIX mode assertions (host filesystem does not expose chmod modes)" >&2
fi

probe_id=20260101000000-700
newline_id="$(printf '20260101000000-1\n20260101000000-2')"
if acmesh_task_validate_id "$newline_id"; then
	echo "task id validation should reject embedded newlines"
	exit 1
fi
rm -rf "$ACMESH_TASK_STATE_DIR" "$ACMESH_TASK_LOG_DIR"
acmesh_task_status "$probe_id" >/dev/null 2>&1 || true
[ -d "$ACMESH_TASK_STATE_DIR" ] || { echo "task status should initialize the private state directory"; exit 1; }
acmesh_task_log "$probe_id" >/dev/null 2>&1 || true
[ -d "$ACMESH_TASK_LOG_DIR" ] || { echo "task log should initialize the private log directory"; exit 1; }
acmesh_task_list >/dev/null
if [ "$TASK_POSIX_MODE_CHECKS" = 1 ]; then
	[ "$(task_mode "$ACMESH_TASK_STATE_DIR")" = 700 ] || { echo "task list should create a 0700 state directory"; exit 1; }
fi

date() {
	case "${1:-}:${2:-}" in
		-u:+%Y%m%d%H%M%S) printf '20260101010101\n' ;;
		*) command date "$@" ;;
	esac
}
collision_id_a="$(acmesh_task_create collision-a)"
collision_id_b="$(acmesh_task_create collision-b)"
unset -f date
[ "$collision_id_a" != "$collision_id_b" ] || { echo "same-shell same-second task creates should not collide"; exit 1; }
acmesh_task_validate_id "$collision_id_a" || { echo "first collision-safe task id should retain the public grammar"; exit 1; }
acmesh_task_validate_id "$collision_id_b" || { echo "second collision-safe task id should retain the public grammar"; exit 1; }

id="$(acmesh_task_create renew)"
state="$ACMESH_TASK_STATE_DIR/$id.json"
log="$ACMESH_TASK_LOG_DIR/$id.log"
if [ "$TASK_POSIX_MODE_CHECKS" = 1 ]; then
	[ "$(task_mode "$ACMESH_TASK_STATE_DIR")" = 700 ] || { echo "task state directory should be 0700"; exit 1; }
	[ "$(task_mode "$ACMESH_TASK_LOG_DIR")" = 700 ] || { echo "task log directory should be 0700"; exit 1; }
	[ "$(task_mode "$state")" = 600 ] || { echo "task state file should be 0600"; exit 1; }
	[ "$(task_mode "$log")" = 600 ] || { echo "task log file should be 0600"; exit 1; }
fi
created_state="$(acmesh_task_status "$id")"
created_at="$(printf '%s\n' "$created_state" | sed -n 's/.*"createdAt":"\([^"]*\)".*/\1/p')"
printf '%s\n' "$created_state" | grep '"status":"created"' >/dev/null
printf '%s\n' "$created_state" | grep '"createdAt":"[^"]*"' >/dev/null || { echo "created task should include createdAt"; exit 1; }
printf '%s\n' "$created_state" | grep '"startedAt":""' >/dev/null || { echo "created task should have an empty startedAt"; exit 1; }
printf '%s\n' "$created_state" | grep '"finishedAt":""' >/dev/null || { echo "created task should have an empty finishedAt"; exit 1; }
acmesh_task_run "$id" renew preview printf '%s\n' "hello task"
success_state="$(acmesh_task_status "$id")"
success_created_at="$(printf '%s\n' "$success_state" | sed -n 's/.*"createdAt":"\([^"]*\)".*/\1/p')"
[ "$success_created_at" = "$created_at" ] || { echo "task state transitions should preserve createdAt"; exit 1; }
printf '%s\n' "$success_state" | grep '"status":"success"' >/dev/null
printf '%s\n' "$success_state" | grep '"startedAt":"[^"]*"' >/dev/null || { echo "completed task should include startedAt"; exit 1; }
printf '%s\n' "$success_state" | grep '"finishedAt":"[^"]*"' >/dev/null || { echo "completed task should include finishedAt"; exit 1; }
acmesh_task_log "$id" | grep 'hello task' >/dev/null

acmesh_task_write_state_atomic "$id" renew failed preview 1 "2026-01-01T00:00:00Z" "2026-01-01T00:00:01Z" "CF_Token='task-secret'"
masked_state="$(acmesh_task_status "$id")"
case "$masked_state" in
	*task-secret*) echo "task lastError should not expose secrets"; exit 1 ;;
	*"CF_Token='***'"*) ;;
	*) echo "task lastError should retain a masked diagnostic"; exit 1 ;;
esac

atomic_error="$ROOT/tests/.tmp/task-atomic.error"
: > "$atomic_error"
acmesh_task_write_state_atomic "$id" renew running atomic 0 "2026-01-01T00:00:00Z" '' ''
reader=1
while [ "$reader" -le 20 ]; do
	(
		reads=0
		while [ "$reads" -lt 10 ]; do
			content="$(cat "$state" 2>/dev/null || true)"
			case "$content" in
				'{'*'"taskId":"'*'"status":"running"'*'}'|'{'*'"taskId":"'*'"status":"success"'*'}') ;;
				*) printf '%s\n' "$content" >> "$atomic_error"; exit 1 ;;
			esac
			reads=$((reads + 1))
		done
	) &
	reader=$((reader + 1))
done
writer=1
while [ "$writer" -le 10 ]; do
	acmesh_task_write_state_atomic "$id" renew success atomic 0 "2026-01-01T00:00:00Z" "2026-01-01T00:00:01Z" ''
	acmesh_task_write_state_atomic "$id" renew running atomic 0 "2026-01-01T00:00:00Z" '' ''
	writer=$((writer + 1))
done
wait || { echo "concurrent task reader observed partial JSON"; exit 1; }
[ ! -s "$atomic_error" ] || { echo "concurrent task reader observed partial JSON"; exit 1; }

direct_id=20260101000000-701
rm -rf "$ACMESH_TASK_STATE_DIR" "$ACMESH_TASK_LOG_DIR"
acmesh_task_run "$direct_id" direct-run direct printf '%s\n' "direct task"
acmesh_task_status "$direct_id" | grep '"status":"success"' >/dev/null || { echo "task run should initialize and publish state without create"; exit 1; }
acmesh_task_log "$direct_id" | grep 'direct task' >/dev/null || { echo "task run should initialize its private log directory without create"; exit 1; }
if [ "$TASK_POSIX_MODE_CHECKS" = 1 ]; then
	[ "$(task_mode "$ACMESH_TASK_STATE_DIR")" = 700 ] || { echo "standalone task run state directory should be 0700"; exit 1; }
	[ "$(task_mode "$ACMESH_TASK_LOG_DIR")" = 700 ] || { echo "standalone task run log directory should be 0700"; exit 1; }
	[ "$(task_mode "$ACMESH_TASK_STATE_DIR/$direct_id.json")" = 600 ] || { echo "standalone task run state should be 0600"; exit 1; }
	[ "$(task_mode "$ACMESH_TASK_LOG_DIR/$direct_id.log")" = 600 ] || { echo "standalone task run log should be 0600"; exit 1; }
fi

background_failure() {
	printf '%s\n' "background command failed"
	return 23
}
failure_id=20260101000000-702
set +e
acmesh_task_run "$failure_id" background-failure execute background_failure &
failure_pid=$!
wait "$failure_pid"
failure_rc=$?
set -e
[ "$failure_rc" = 23 ] || { echo "background task should return the real command failure"; exit 1; }
failure_state="$(acmesh_task_status "$failure_id")"
case "$failure_state" in
	*'"status":"failed"'*'"exitCode":23'*'"lastError":"task exited with status 23"'*) ;;
	*) echo "background task failure should publish failed, exitCode, and lastError"; echo "$failure_state"; exit 1 ;;
esac

bad_status="$(acmesh_task_status '../escape' 2>/dev/null || true)"
case "$bad_status" in
	*'"ok":false'*'"invalid task id"'*) ;;
	*) echo "task status should reject unsafe ids"; echo "$bad_status"; exit 1 ;;
esac

bad_log="$(acmesh_task_log '../escape' 2>/dev/null || true)"
case "$bad_log" in
	*"invalid task id"*) ;;
	*) echo "task log should reject unsafe ids"; echo "$bad_log"; exit 1 ;;
esac

symlink_id=20260101000000-703
symlink_state_target="$ROOT/tests/.tmp/task-state-symlink-target"
symlink_log_target="$ROOT/tests/.tmp/task-log-symlink-target"
printf '%s\n' 'state symlink sentinel' > "$symlink_state_target"
printf '%s\n' 'log symlink sentinel' > "$symlink_log_target"
rm -f "$ACMESH_TASK_STATE_DIR/$symlink_id.json" "$ACMESH_TASK_LOG_DIR/$symlink_id.log"
ln -s "$symlink_state_target" "$ACMESH_TASK_STATE_DIR/$symlink_id.json" 2>/dev/null || true
ln -s "$symlink_log_target" "$ACMESH_TASK_LOG_DIR/$symlink_id.log" 2>/dev/null || true
if [ -L "$ACMESH_TASK_STATE_DIR/$symlink_id.json" ] && [ -L "$ACMESH_TASK_LOG_DIR/$symlink_id.log" ]; then
	symlink_status="$(acmesh_task_status "$symlink_id" 2>/dev/null || true)"
	symlink_log="$(acmesh_task_log "$symlink_id" 2>/dev/null || true)"
	case "$symlink_status" in
		*"state symlink sentinel"*) echo "task status should reject state-file symlinks"; exit 1 ;;
	esac
	case "$symlink_log" in
		*"log symlink sentinel"*) echo "task log should reject log-file symlinks"; exit 1 ;;
	esac
else
	printf '%s\n' "test_task: SKIP symlink assertions (host filesystem does not expose POSIX symlinks)" >&2
fi
rm -f "$ACMESH_TASK_STATE_DIR/$symlink_id.json" "$ACMESH_TASK_LOG_DIR/$symlink_id.log"

export ACMESH_CONSOLE_UCI_CONFIG="$ROOT/tests/.tmp/task-uci"
cat > "$ACMESH_CONSOLE_UCI_CONFIG" <<EOF
config acmesh-console 'main'
	option task_state_dir '$ROOT/tests/.tmp/tasks-state-from-uci'
	option task_log_dir '$ROOT/tests/.tmp/tasks-log-from-uci'
EOF
unset ACMESH_TASK_STATE_DIR
unset ACMESH_TASK_LOG_DIR
. "$ACMESH_LIB_DIR/config.sh"
. "$ACMESH_LIB_DIR/task.sh"
uci_id="$(acmesh_task_create uci-task)"
case "$uci_id" in
	[0-9]*) ;;
	*) echo "uci task id invalid"; echo "$uci_id"; exit 1 ;;
esac
[ -f "$ROOT/tests/.tmp/tasks-state-from-uci/$uci_id.json" ] || { echo "task state dir should use UCI default"; exit 1; }
[ -f "$ROOT/tests/.tmp/tasks-log-from-uci/$uci_id.log" ] || { echo "task log dir should use UCI default"; exit 1; }

echo "test_task: ok"
