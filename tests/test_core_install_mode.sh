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
	*'"ok":true'*'"testMode":true'*'"command"'*) ;;
	*) echo "core install test mode did not return preview"; echo "$out"; exit 1 ;;
esac
case "$out" in *'"taskId"'*) echo "core install test mode created task"; exit 1;; esac
[ ! -e "$ACMESH_TASK_STATE_DIR" ] && [ ! -e "$ACMESH_TASK_LOG_DIR" ]
case "$out" in
	*"https://github.com/acmesh-official/acme.sh/archive/refs/tags/v3.1.4.tar.gz"*"--install"*"admin@example.com"*) ;;
	*) echo "core install preview is wrong"; echo "$out"; exit 1 ;;
esac
case "$out" in
	*"LE_WORKING_DIR="*"LE_CONFIG_HOME="*) ;;
	*) echo "core install command should pin acme.sh home"; echo "$out"; exit 1 ;;
esac
case "$out" in
	*"get.acme.sh"*|*"master.tar.gz"*)
		echo "core install should use an explicit tag, not get.acme.sh/master"
		echo "$out"
		exit 1
		;;
esac

echo "test_core_install_mode: ok"
