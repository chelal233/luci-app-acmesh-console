#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
export ACMESH_TASK_STATE_DIR="$ROOT/tests/.tmp/ssh-test-state"
export ACMESH_TASK_LOG_DIR="$ROOT/tests/.tmp/ssh-test-log"
rm -rf "$ACMESH_TASK_STATE_DIR" "$ACMESH_TASK_LOG_DIR"

out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" ssh-test --host 192.0.2.10 --port 22 --user root --key /etc/acmesh-console/ssh/id_ed25519 --command 'true' --test-mode)"
case "$out" in
	*'"ok":true'*'"taskId"'*) ;;
	*) echo "ssh-test did not create task"; echo "$out"; exit 1 ;;
esac

task_id="$(printf '%s' "$out" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
sleep 1
status="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-status --task-id "$task_id")"
log="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-log --task-id "$task_id")"

case "$status" in
	*'"status":"success"'*) ;;
	*) echo "ssh-test task should succeed in test mode"; echo "$status"; echo "$log"; exit 1 ;;
esac
case "$log" in
	*"TEST MODE: SSH command assembled"*"ssh -i"*"192.0.2.10"*) ;;
	*) echo "ssh-test log is wrong"; echo "$log"; exit 1 ;;
esac

echo "test_ssh_test_mode: ok"
