#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
. "$ACMESH_LIB_DIR/json.sh"
. "$ROOT/tests/lib/cli_request.sh"
export ACMESH_TASK_STATE_DIR="$ROOT/tests/.tmp/test-mode-state" ACMESH_TASK_LOG_DIR="$ROOT/tests/.tmp/test-mode-log"
export ACMESH_AUTH_STATE_DIR="$ROOT/tests/.tmp/test-mode-auth" ACMESH_AUTH_CHALLENGE_DIR="$ROOT/tests/.tmp/test-mode-challenges"
rm -rf "$ACMESH_TASK_STATE_DIR" "$ACMESH_TASK_LOG_DIR" "$ACMESH_AUTH_STATE_DIR" "$ACMESH_AUTH_CHALLENGE_DIR"
out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" issue --domain example.com --key-type ecc --dns-api dns_cf --test-mode)"
case "$out" in *'"ok":true'*'"testMode":true'*'"command"'*) ;; *) echo "issue test preview failed"; echo "$out"; exit 1;; esac
case "$out" in *'"taskId"'*) echo "test mode created task"; exit 1;; esac
[ ! -e "$ACMESH_TASK_STATE_DIR" ] && [ ! -e "$ACMESH_AUTH_STATE_DIR" ] && [ ! -e "$ACMESH_AUTH_CHALLENGE_DIR" ]
custom="$(acmesh_test_cli_request issue --domain custom.example.com --key-type ec256 --dns-api dns_custom --credential ODD_VARIABLE=custom-secret --test-mode)"
case "$custom" in *custom-secret*) echo "credential leaked"; exit 1;; *"ODD_VARIABLE='***'"*) ;; *) echo "credential was not masked"; echo "$custom"; exit 1;; esac
echo "test_issue_test_mode: ok"
