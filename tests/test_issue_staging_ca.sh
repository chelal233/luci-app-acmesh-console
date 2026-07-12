#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"

out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" preview-issue --domain example.com --key-type ec256 --validation-method dns --dns-api dns_cf --ca letsencrypt_staging)"

case "$out" in
	*'"ok":true'*"--server 'letsencrypt_test'"*"--dns 'dns_cf'"*) ;;
	*) echo "preview issue did not include letsencrypt staging"; echo "$out"; exit 1 ;;
esac

export ACMESH_TASK_STATE_DIR="$ROOT/tests/.tmp/staging-ca-state"
export ACMESH_TASK_LOG_DIR="$ROOT/tests/.tmp/staging-ca-log"
rm -rf "$ACMESH_TASK_STATE_DIR" "$ACMESH_TASK_LOG_DIR"
task_out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" issue --domain example.com --key-type ec256 --validation-method dns --dns-api dns_cf --ca letsencrypt_staging --test-mode)"
task_id="$(printf '%s' "$task_out" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
sleep 1
log="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-log --task-id "$task_id")"
case "$log" in
	*"TEST MODE"*"--server 'letsencrypt_test'"*) ;;
	*) echo "issue test-mode log did not include staging server"; echo "$log"; exit 1 ;;
esac

echo "test_issue_staging_ca: ok"
