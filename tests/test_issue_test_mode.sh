#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
export ACMESH_TASK_STATE_DIR="$ROOT/tests/.tmp/test-mode-state"
export ACMESH_TASK_LOG_DIR="$ROOT/tests/.tmp/test-mode-log"
rm -rf "$ROOT/tests/.tmp/test-mode-state" "$ROOT/tests/.tmp/test-mode-log"

out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" issue --domain example.com --key-type ecc --dns-api dns_cf --test-mode)"

case "$out" in
	*'"ok":true'*'"testMode":true'*'"taskId"'*) ;;
	*) echo "issue test mode did not return a test task"; echo "$out"; exit 1 ;;
esac

task_id="$(printf '%s' "$out" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
sleep 1
status="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-status --task-id "$task_id")"
log="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-log --task-id "$task_id")"

case "$status" in
	*'"status":"success"'*) ;;
	*) echo "test mode task did not succeed"; echo "$status"; exit 1 ;;
esac

case "$log" in
	*"TEST MODE"*"no real ACME request was sent"*"acme.sh --home"*) ;;
	*) echo "test mode log did not explain simulated acme.sh flow"; echo "$log"; exit 1 ;;
esac

custom_out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" issue --domain custom.example.com --key-type ec256 --dns-api dns_custom --credential ODD_VARIABLE=custom-log-secret --test-mode)"
custom_id="$(printf '%s' "$custom_out" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
sleep 1
custom_log="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-log --task-id "$custom_id")"
case "$custom_log" in *custom-log-secret*) echo "custom DNS credential leaked to test-mode log"; echo "$custom_log"; exit 1;; esac
case "$custom_log" in *"ODD_VARIABLE='***'"*) ;; *) echo "custom DNS credential was not value-redacted"; echo "$custom_log"; exit 1;; esac

echo "test_issue_test_mode: ok"
