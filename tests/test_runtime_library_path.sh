#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
CTL="$ROOT/root/usr/libexec/acmesh-console/acmeshctl"
DEPLOY="$ROOT/root/usr/libexec/acmesh-console/lib/deploy.sh"

grep -F 'ACMESH_LIB_DIR="${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}"' "$CTL" >/dev/null
grep -F 'export ACMESH_LIB_DIR' "$CTL" >/dev/null
grep -F '${ACMESH_DEPLOY_WORKER_SCRIPT:-${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/deploy-worker.sh}' "$DEPLOY" >/dev/null

echo "test_runtime_library_path: ok"
