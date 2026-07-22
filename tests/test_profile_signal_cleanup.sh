#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
. "$ACMESH_LIB_DIR/profile.sh"

TMP="$ROOT/tests/.tmp/profile-signal"
rm -rf "$TMP"
mkdir -p "$TMP"
resolved="$TMP/resolved.json"
ready="$TMP/ready"
after="$TMP/continued"
(
	: > "$resolved"
	acmesh_profile_install_cleanup_traps "$resolved"
	: > "$ready"
	while :; do :; done
	: > "$after"
) &
pid=$!
round=0
while [ ! -e "$ready" ] && [ "$round" -lt 10000 ]; do round=$((round + 1)); :; done
[ -e "$ready" ] || { echo "signal fixture did not become ready"; kill "$pid" 2>/dev/null || :; exit 1; }
kill -TERM "$pid"
set +e
wait "$pid"
status=$?
set -e
[ "$status" -eq 143 ] || { echo "TERM exit was $status, expected 143"; exit 1; }
[ ! -e "$resolved" ] || { echo "resolved file survived TERM"; exit 1; }
[ ! -e "$after" ] || { echo "operation continued after TERM"; exit 1; }
echo "profile signal cleanup tests passed"
