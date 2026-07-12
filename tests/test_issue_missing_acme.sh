#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
export ACMESH_TASK_STATE_DIR="$ROOT/tests/.tmp/missing-acme-state"
export ACMESH_TASK_LOG_DIR="$ROOT/tests/.tmp/missing-acme-log"
home="$ROOT/tests/.tmp/missing-acme-home"
rm -rf "$ROOT/tests/.tmp/missing-acme-state" "$ROOT/tests/.tmp/missing-acme-log" "$home"
mkdir -p "$home"

out="$(PATH=/usr/bin:/bin sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" issue --home "$home" --domain example.com --key-type ecc --dns-api dns_cf --real-mode)"
case "$out" in
	*'"ok":true'*'"taskId"'*) ;;
	*) echo "missing acme case did not create task"; echo "$out"; exit 1 ;;
esac

task_id="$(printf '%s' "$out" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
sleep 1
status="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-status --task-id "$task_id")"
log="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-log --task-id "$task_id")"

case "$status" in
	*'"status":"failed"'*) ;;
	*) echo "missing acme task should fail"; echo "$status"; echo "$log"; exit 1 ;;
esac

case "$log" in
	*"acme.sh not found"*) ;;
	*) echo "missing acme log did not explain root cause"; echo "$log"; exit 1 ;;
esac

echo "test_issue_missing_acme: ok"
