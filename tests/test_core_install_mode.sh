#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
export ACMESH_TASK_STATE_DIR="$ROOT/tests/.tmp/core-install-state"
export ACMESH_TASK_LOG_DIR="$ROOT/tests/.tmp/core-install-log"
home="$ROOT/tests/.tmp/core-install-home"
rm -rf "$ACMESH_TASK_STATE_DIR" "$ACMESH_TASK_LOG_DIR" "$home"

out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" core-install --home "$home" --email admin@example.com --test-mode)"
case "$out" in
	*'"ok":true'*'"testMode":true'*'"taskId"'*) ;;
	*) echo "core install test mode did not create test task"; echo "$out"; exit 1 ;;
esac

task_id="$(printf '%s' "$out" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
sleep 1
status="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-status --task-id "$task_id")"
log="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-log --task-id "$task_id")"

case "$status" in
	*'"status":"success"'*) ;;
	*) echo "core install test task should succeed"; echo "$status"; exit 1 ;;
esac
case "$status" in
	*'"operation":"core-install-test"'*) ;;
	*) echo "core install test task has wrong operation"; echo "$status"; exit 1 ;;
esac

case "$log" in
	*"TEST MODE"*"https://github.com/acmesh-official/acme.sh/archive/refs/tags/v3.1.4.tar.gz"*"--install"*"admin@example.com"*) ;;
	*) echo "core install test log is wrong"; echo "$log"; exit 1 ;;
esac
case "$log" in
	*"LE_WORKING_DIR="*"LE_CONFIG_HOME="*) ;;
	*) echo "core install command should pin acme.sh home"; echo "$log"; exit 1 ;;
esac
case "$log" in
	*"get.acme.sh"*|*"master.tar.gz"*)
		echo "core install should use an explicit tag, not get.acme.sh/master"
		echo "$log"
		exit 1
		;;
esac

echo "test_core_install_mode: ok"
