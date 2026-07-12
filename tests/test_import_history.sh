#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
export ACMESH_TASK_STATE_DIR="$ROOT/tests/.tmp/import-history-state"
export ACMESH_TASK_LOG_DIR="$ROOT/tests/.tmp/import-history-log"
rm -rf "$ACMESH_TASK_STATE_DIR" "$ACMESH_TASK_LOG_DIR"

home="$ROOT/tests/fixtures/acme-home"
out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" import-history --home "$home")"

case "$out" in
	*'"ok":true'*'"taskId"'*) ;;
	*) echo "import-history did not create task"; echo "$out"; exit 1 ;;
esac

task_id="$(printf '%s' "$out" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
sleep 1
status="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-status --task-id "$task_id")"
log="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-log --task-id "$task_id")"

case "$status" in
	*'"status":"success"'*) ;;
	*) echo "import-history task should succeed"; echo "$status"; echo "$log"; exit 1 ;;
esac
case "$status" in
	*'"operation":"import-history"'*) ;;
	*) echo "import-history task has wrong operation"; echo "$status"; echo "$log"; exit 1 ;;
esac

case "$log" in
	*"Imported certificate variants: 2"*) ;;
	*) echo "import-history log is wrong"; echo "$log"; exit 1 ;;
esac
case "$log" in
	*"example.com"*) ;;
	*) echo "import-history log missing domain"; echo "$log"; exit 1 ;;
esac
case "$log" in
	*"ecc"*) ;;
	*) echo "import-history log missing ecc"; echo "$log"; exit 1 ;;
esac
case "$log" in
	*"rsa"*) ;;
	*) echo "import-history log missing rsa"; echo "$log"; exit 1 ;;
esac

echo "test_import_history: ok"
