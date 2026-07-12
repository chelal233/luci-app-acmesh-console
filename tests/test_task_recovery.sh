#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
export ACMESH_TASK_STATE_DIR="$ROOT/tests/.tmp/recovery-state"
export ACMESH_TASK_LOG_DIR="$ROOT/tests/.tmp/recovery-log"
TASK_JSON_BIN="$ROOT/tests/.tmp/task-json-bin"
rm -rf "$ACMESH_TASK_STATE_DIR" "$ACMESH_TASK_LOG_DIR" "$TASK_JSON_BIN"
mkdir -p "$ROOT/tests/.tmp"
chmod 700 "$ROOT/tests/.tmp"
. "$ROOT/tests/lib/host_flock.sh"
acmesh_test_install_flock_shim "$ROOT/tests/.tmp/recovery-flock"
printf '%s\n' '11111111-2222-3333-4444-555555555555' > "$ROOT/tests/.tmp/boot_id"
ACMESH_BOOT_ID_FILE="$ROOT/tests/.tmp/boot_id"
export ACMESH_BOOT_ID_FILE

if ! command -v jsonfilter >/dev/null 2>&1; then
	command -v node >/dev/null 2>&1 || { echo "jsonfilter or node is required for task recovery tests"; exit 1; }
	mkdir -p "$TASK_JSON_BIN"
	cat > "$TASK_JSON_BIN/jsonfilter" <<'JS'
#!/usr/bin/env node
const fs = require('fs');
const args = process.argv.slice(2);
const inputIndex = args.indexOf('-i');
const typeIndex = args.indexOf('-t');
const valueIndex = args.indexOf('-e');
if (inputIndex < 0 || (typeIndex < 0 && valueIndex < 0)) process.exit(2);
let data;
try { data = JSON.parse(fs.readFileSync(args[inputIndex + 1], 'utf8')); }
catch (_) { process.exit(1); }
const expr = args[(typeIndex >= 0 ? typeIndex : valueIndex) + 1];
const field = expr.match(/^@\.([A-Za-z0-9_]+)$/);
const value = expr === '@' ? data : (field ? data[field[1]] : undefined);
if (typeIndex >= 0) {
	if (value === undefined) process.exit(0);
	if (value === null) process.stdout.write('null\n');
	else if (Array.isArray(value)) process.stdout.write('array\n');
	else if (Number.isInteger(value)) process.stdout.write('int\n');
	else if (typeof value === 'number') process.stdout.write('double\n');
	else process.stdout.write(typeof value + '\n');
} else if (value !== undefined && value !== null) {
	process.stdout.write(typeof value === 'object' ? JSON.stringify(value) : String(value));
}
JS
	chmod +x "$TASK_JSON_BIN/jsonfilter"
	PATH="$TASK_JSON_BIN:$PATH"
	export PATH
fi

. "$ACMESH_LIB_DIR/task.sh"

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

if [ "$(task_mode "$ROOT/tests/.tmp")" != 700 ]; then
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
	printf '%s\n' "test_task_recovery: SKIP POSIX mode assertions (host filesystem does not expose chmod modes)" >&2
fi

acmesh_task_fixture() {
	id="$1" status="$2" created_at="${3:-2026-01-01T00:00:00Z}"
	acmesh_private_dir "$ACMESH_TASK_STATE_DIR"
	acmesh_private_dir "$ACMESH_TASK_LOG_DIR"
	(umask 077; printf '{"ok":true,"taskId":"%s","operation":"renew","createdAt":"%s","status":"%s","stage":"fixture","exitCode":0,"startedAt":"","finishedAt":"","lastError":""}\n' "$id" "$created_at" "$status" > "$ACMESH_TASK_STATE_DIR/$id.json")
	(umask 077; printf '%s\n' "$id" > "$ACMESH_TASK_LOG_DIR/$id.log")
	chmod 600 "$ACMESH_TASK_STATE_DIR/$id.json" "$ACMESH_TASK_LOG_DIR/$id.log"
}

export ACMESH_TASK_RECOVERY_NOW_EPOCH=1767226000
export ACMESH_TASK_CREATED_STALE_SECONDS=300
running_id=20260101000000-900
stale_created_id=20260101000000-901
fresh_created_id=20260101000500-902
whitespace_id=20260101000001-903
terminal_id=20260101000002-904
mismatch_file_id=20260101000003-905
numeric_status_id=20260101000004-906
malformed_id=20260101000005-907
newline_id="$(printf '20260101000006-908\n20260101000007-909')"

acmesh_task_fixture "$running_id" running
acmesh_task_fixture "$stale_created_id" created 2025-12-31T23:59:00Z
acmesh_task_fixture "$fresh_created_id" created 2026-01-01T00:05:00Z
acmesh_private_dir "$ACMESH_TASK_STATE_DIR"
acmesh_private_dir "$ACMESH_TASK_LOG_DIR"
printf ' { \n "ok" : true, "taskId" : "%s", "operation" : "renew", "createdAt" : "2026-01-01T00:00:01Z", "status" : "running", "stage" : "fixture", "exitCode" : 0, "startedAt" : "", "finishedAt" : "", "lastError" : "" \n } \n' "$whitespace_id" > "$ACMESH_TASK_STATE_DIR/$whitespace_id.json"
printf '%s\n' "$whitespace_id" > "$ACMESH_TASK_LOG_DIR/$whitespace_id.log"
printf '%s\n' '{"ok":true,"taskId":"20260101000002-904","operation":"renew","createdAt":"2026-01-01T00:00:02Z","status":"success","stage":"fixture","exitCode":0,"startedAt":"","finishedAt":"","lastError":"diagnostic: \"status\":\"running\""}' > "$ACMESH_TASK_STATE_DIR/$terminal_id.json"
printf '%s\n' '{"ok":true,"taskId":"20260101000003-999","operation":"renew","createdAt":"2026-01-01T00:00:03Z","status":"running","stage":"fixture","exitCode":0,"startedAt":"","finishedAt":"","lastError":""}' > "$ACMESH_TASK_STATE_DIR/$mismatch_file_id.json"
printf '%s\n' '{"ok":true,"taskId":"20260101000004-906","operation":"renew","createdAt":"2026-01-01T00:00:04Z","status":1,"stage":"fixture","exitCode":0,"startedAt":"","finishedAt":"","lastError":""}' > "$ACMESH_TASK_STATE_DIR/$numeric_status_id.json"
printf '%s\n' '{"taskId":"20260101000005-907","status":"running"' > "$ACMESH_TASK_STATE_DIR/$malformed_id.json"
printf '%s\n' '{"ok":true,"taskId":"20260101000006-908","operation":"renew","createdAt":"2026-01-01T00:00:06Z","status":"running","stage":"fixture","exitCode":0,"startedAt":"","finishedAt":"","lastError":""}' > "$ACMESH_TASK_STATE_DIR/$newline_id.json"
chmod 600 "$ACMESH_TASK_STATE_DIR"/*.json "$ACMESH_TASK_LOG_DIR"/*.log

terminal_before="$(cat "$ACMESH_TASK_STATE_DIR/$terminal_id.json")"
mismatch_before="$(cat "$ACMESH_TASK_STATE_DIR/$mismatch_file_id.json")"
numeric_before="$(cat "$ACMESH_TASK_STATE_DIR/$numeric_status_id.json")"
malformed_before="$(cat "$ACMESH_TASK_STATE_DIR/$malformed_id.json")"
newline_before="$(cat "$ACMESH_TASK_STATE_DIR/$newline_id.json")"

acmesh_task_recover_interrupted
grep '"status":"interrupted"' "$ACMESH_TASK_STATE_DIR/$running_id.json" >/dev/null || { echo "running task should recover as interrupted"; exit 1; }
grep '"status":"interrupted"' "$ACMESH_TASK_STATE_DIR/$stale_created_id.json" >/dev/null || { echo "stale created task should recover as interrupted"; exit 1; }
grep '"createdAt":"2025-12-31T23:59:00Z"' "$ACMESH_TASK_STATE_DIR/$stale_created_id.json" >/dev/null || { echo "recovery should preserve createdAt"; exit 1; }
grep '"status":"created"' "$ACMESH_TASK_STATE_DIR/$fresh_created_id.json" >/dev/null || { echo "fresh created task should remain nonterminal"; exit 1; }
grep '"status":"interrupted"' "$ACMESH_TASK_STATE_DIR/$whitespace_id.json" >/dev/null || { echo "recovery should accept valid JSON whitespace"; exit 1; }
grep '"finishedAt":"[^"]*"' "$ACMESH_TASK_STATE_DIR/$running_id.json" >/dev/null || { echo "recovered task should include finishedAt"; exit 1; }
grep '"exitCode":1' "$ACMESH_TASK_STATE_DIR/$running_id.json" >/dev/null || { echo "recovered task should fail with exitCode 1"; exit 1; }

live_id=20260101000012-912
acmesh_task_worker_identity_load || { echo "test shell worker identity should be available"; exit 1; }
acmesh_task_write_state_atomic "$live_id" renew running worker 0 \
	"2026-01-01T00:00:12Z" '' '' \
	"$acmesh_worker_pid" "$acmesh_worker_starttime" "$acmesh_worker_boot_id"
acmesh_task_recover_interrupted
grep '"status":"running"' "$ACMESH_TASK_STATE_DIR/$live_id.json" >/dev/null || {
	echo "recovery should preserve a running task whose worker identity is alive"
	exit 1
}

dead_id=20260101000013-913
acmesh_task_write_state_atomic "$dead_id" renew running worker 0 \
	"2026-01-01T00:00:13Z" '' '' \
	"999999" "1" "$acmesh_worker_boot_id"
acmesh_task_recover_interrupted
grep '"status":"interrupted"' "$ACMESH_TASK_STATE_DIR/$dead_id.json" >/dev/null || {
	echo "recovery should interrupt a running task whose worker identity is gone"
	exit 1
}
[ "$(cat "$ACMESH_TASK_STATE_DIR/$terminal_id.json")" = "$terminal_before" ] || { echo "terminal diagnostic text should not trigger recovery"; exit 1; }
[ "$(cat "$ACMESH_TASK_STATE_DIR/$mismatch_file_id.json")" = "$mismatch_before" ] || { echo "recovery should reject taskId and filename mismatch"; exit 1; }
[ "$(cat "$ACMESH_TASK_STATE_DIR/$numeric_status_id.json")" = "$numeric_before" ] || { echo "recovery should reject non-string status"; exit 1; }
[ "$(cat "$ACMESH_TASK_STATE_DIR/$malformed_id.json")" = "$malformed_before" ] || { echo "recovery should reject malformed JSON"; exit 1; }
[ "$(cat "$ACMESH_TASK_STATE_DIR/$newline_id.json")" = "$newline_before" ] || { echo "recovery should reject newline task filenames"; exit 1; }

recovery_jsonfilter_bin="$ROOT/tests/.tmp/recovery-jsonfilter-bin"
rm -rf "$recovery_jsonfilter_bin"
mkdir -p "$recovery_jsonfilter_bin"
ACMESH_TEST_REAL_JSONFILTER="$(command -v jsonfilter)"
export ACMESH_TEST_REAL_JSONFILTER
cat > "$recovery_jsonfilter_bin/jsonfilter" <<'EOF'
#!/bin/sh
input=""
expression=""
selector=""
while [ "$#" -gt 0 ]; do
	case "$1" in
		-i) input="${2:-}"; shift 2 ;;
		-e|-t) selector="$1"; expression="${2:-}"; shift 2 ;;
		*) shift ;;
	esac
done
if [ "$input" = "${ACMESH_TEST_RECOVERY_STATE:-}" ] && \
	[ "$expression" = '@.operation' ] && \
	[ -n "${ACMESH_TEST_RECOVERY_READY:-}" ] && \
	[ -n "${ACMESH_TEST_RECOVERY_RELEASE:-}" ]; then
	: > "$ACMESH_TEST_RECOVERY_READY"
	attempt=0
	while [ ! -e "$ACMESH_TEST_RECOVERY_RELEASE" ]; do
		attempt=$((attempt + 1))
		[ "$attempt" -lt 100 ] || exit 1
		sleep 1
	done
fi
exec "$ACMESH_TEST_REAL_JSONFILTER" -i "$input" "$selector" "$expression"
EOF
chmod +x "$recovery_jsonfilter_bin/jsonfilter"
PATH="$recovery_jsonfilter_bin:$PATH"
export PATH

acmesh_task_recovery_race() {
	id="$1"
	initial_status="$2"
	worker_status="$3"
	created_at="$4"
	race_dir="$ROOT/tests/.tmp/recovery-race-$id"
	ready="$race_dir/recovery-ready"
	release="$race_dir/recovery-release"
	worker_started="$race_dir/worker-started"
	worker_done="$race_dir/worker-done"
	rm -rf "$race_dir" "$ACMESH_TASK_STATE_DIR" "$ACMESH_TASK_LOG_DIR"
	mkdir -p "$race_dir"
	acmesh_task_fixture "$id" "$initial_status" "$created_at"
	ACMESH_TEST_RECOVERY_READY="$ready"
	ACMESH_TEST_RECOVERY_RELEASE="$release"
	ACMESH_TEST_RECOVERY_STATE="$ACMESH_TASK_STATE_DIR/$id.json"
	export ACMESH_TEST_RECOVERY_READY ACMESH_TEST_RECOVERY_RELEASE ACMESH_TEST_RECOVERY_STATE
	acmesh_task_recover_interrupted &
	recovery_pid=$!
	attempt=0
	while [ ! -e "$ready" ]; do
		attempt=$((attempt + 1))
		if [ "$attempt" -ge 100 ]; then
			kill "$recovery_pid" 2>/dev/null || true
			wait "$recovery_pid" 2>/dev/null || true
			echo "recovery race did not reach the interrupted publication"
			return 1
		fi
		sleep 1
	done
	(
		: > "$worker_started"
		case "$worker_status" in
			running)
				acmesh_task_write_state_atomic "$id" renew running worker 0 \
					"2026-01-01T00:00:10Z" '' ''
				;;
			success)
				acmesh_task_write_state_atomic "$id" renew success worker 0 \
					"2026-01-01T00:00:10Z" "2026-01-01T00:00:20Z" ''
				;;
		esac
		: > "$worker_done"
	) &
	worker_pid=$!
	attempt=0
	while [ ! -e "$worker_started" ] && [ "$attempt" -lt 20 ]; do
		attempt=$((attempt + 1))
		sleep 1
	done
	[ -e "$worker_started" ] || {
		kill "$worker_pid" "$recovery_pid" 2>/dev/null || true
		wait "$worker_pid" 2>/dev/null || true
		wait "$recovery_pid" 2>/dev/null || true
		echo "worker did not attempt the protected transition"
		return 1
	}
	: > "$release"
	wait "$worker_pid"
	wait "$recovery_pid"
	[ -e "$worker_done" ] || { echo "worker did not finish the protected transition"; return 1; }
	unset ACMESH_TEST_RECOVERY_READY ACMESH_TEST_RECOVERY_RELEASE ACMESH_TEST_RECOVERY_STATE
	grep "\"status\":\"$worker_status\"" "$ACMESH_TASK_STATE_DIR/$id.json" >/dev/null || {
		echo "recovery should not overwrite worker transition $initial_status -> $worker_status"
		cat "$ACMESH_TASK_STATE_DIR/$id.json"
		return 1
	}
}

acmesh_task_recovery_race 20260101000010-910 created running 2025-12-31T23:59:00Z
acmesh_task_recovery_race 20260101000011-911 running success 2026-01-01T00:00:00Z

rm -rf "$ACMESH_TASK_STATE_DIR" "$ACMESH_TASK_LOG_DIR"
index=1
while [ "$index" -le 10 ]; do
	id="$(printf '20260101000%03d-1' "$index")"
	acmesh_task_fixture "$id" success
	index=$((index + 1))
done
running_id=20260102000000-999
created_id=20260102000001-998
acmesh_task_fixture "$running_id" running
acmesh_task_fixture "$created_id" created 2026-01-02T00:00:01Z
prune_mismatch_id=20250101000000-1
prune_malformed_id=20250101000000-2
printf '%s\n' '{"ok":true,"taskId":"20250101000000-999","operation":"renew","createdAt":"2025-01-01T00:00:00Z","status":"success"}' > "$ACMESH_TASK_STATE_DIR/$prune_mismatch_id.json"
printf '%s\n' '{"taskId":"20250101000000-2","status":"success"' > "$ACMESH_TASK_STATE_DIR/$prune_malformed_id.json"
chmod 600 "$ACMESH_TASK_STATE_DIR/$prune_mismatch_id.json" "$ACMESH_TASK_STATE_DIR/$prune_malformed_id.json"
prune_mismatch_before="$(cat "$ACMESH_TASK_STATE_DIR/$prune_mismatch_id.json")"
prune_malformed_before="$(cat "$ACMESH_TASK_STATE_DIR/$prune_malformed_id.json")"

acmesh_task_prune 5
terminal_count=0
index=1
while [ "$index" -le 10 ]; do
	id="$(printf '20260101000%03d-1' "$index")"
	[ ! -f "$ACMESH_TASK_STATE_DIR/$id.json" ] || terminal_count=$((terminal_count + 1))
	index=$((index + 1))
done
[ "$terminal_count" = 5 ] || { echo "prune should retain exactly 5 valid terminal tasks"; exit 1; }
[ -f "$ACMESH_TASK_STATE_DIR/$running_id.json" ] && [ -f "$ACMESH_TASK_LOG_DIR/$running_id.log" ] || { echo "prune should retain running task state and log"; exit 1; }
[ -f "$ACMESH_TASK_STATE_DIR/$created_id.json" ] && [ -f "$ACMESH_TASK_LOG_DIR/$created_id.log" ] || { echo "prune should retain created task state and log"; exit 1; }
[ "$(cat "$ACMESH_TASK_STATE_DIR/$prune_mismatch_id.json")" = "$prune_mismatch_before" ] || { echo "prune should ignore taskId and filename mismatch"; exit 1; }
[ "$(cat "$ACMESH_TASK_STATE_DIR/$prune_malformed_id.json")" = "$prune_malformed_before" ] || { echo "prune should ignore malformed JSON"; exit 1; }
index=1
while [ "$index" -le 10 ]; do
	id="$(printf '20260101000%03d-1' "$index")"
	if [ "$index" -le 5 ]; then
		[ ! -e "$ACMESH_TASK_STATE_DIR/$id.json" ] || { echo "prune should remove oldest terminal state $id"; exit 1; }
		[ ! -e "$ACMESH_TASK_LOG_DIR/$id.log" ] || { echo "prune should remove matching oldest log $id"; exit 1; }
	else
		[ -f "$ACMESH_TASK_STATE_DIR/$id.json" ] || { echo "prune should retain latest terminal state $id"; exit 1; }
		[ -f "$ACMESH_TASK_LOG_DIR/$id.log" ] || { echo "prune should retain matching latest log $id"; exit 1; }
	fi
	index=$((index + 1))
done

operations="$ROOT/htdocs/luci-static/resources/view/acmesh/operations_v2.js"
grep -F "const TERMINAL_TASK_STATES = [ 'success', 'failed', 'interrupted', 'cancelled' ];" "$operations" >/dev/null || { echo "frontend should declare all terminal task states"; exit 1; }
if grep -F "status.status !== 'running'" "$operations" >/dev/null; then
	echo "frontend should not stop polling for created or unknown task states"
	exit 1
fi
grep -F "TERMINAL_TASK_STATES.indexOf(status.status)" "$operations" >/dev/null || { echo "frontend should stop polling only for terminal task states"; exit 1; }

echo "test_task_recovery: ok"
