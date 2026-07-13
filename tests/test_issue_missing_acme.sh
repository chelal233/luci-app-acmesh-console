#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
export ACMESH_TASK_STATE_DIR="$ROOT/tests/.tmp/missing-acme-state"
export ACMESH_TASK_LOG_DIR="$ROOT/tests/.tmp/missing-acme-log"
home="$ROOT/tests/.tmp/missing-acme-home"
rm -rf "$ROOT/tests/.tmp/missing-acme-state" "$ROOT/tests/.tmp/missing-acme-log" "$home"
mkdir -p "$home"

. "$ACMESH_LIB_DIR/command.sh"
set +e; log="$(PATH=/usr/bin:/bin acmesh_execute_issue "$home" example.com ecc dns dns_cf '' '' '' letsencrypt user@example.org example.com 2>&1)"; rc=$?; set -e
[ "$rc" = 127 ]
case "$log" in
	*"acme.sh not found"*) ;;
	*) echo "missing acme log did not explain root cause"; echo "$log"; exit 1 ;;
esac

echo "test_issue_missing_acme: ok"
