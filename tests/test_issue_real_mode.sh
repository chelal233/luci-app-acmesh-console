#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
export ACMESH_TASK_STATE_DIR="$ROOT/tests/.tmp/real-mode-state"
export ACMESH_TASK_LOG_DIR="$ROOT/tests/.tmp/real-mode-log"
export ACMESH_CONSOLE_CONFIG="$ROOT/tests/.tmp/real-mode-config.json"
home="$ROOT/tests/.tmp/real-acme-home"
rm -rf "$ROOT/tests/.tmp/real-mode-state" "$ROOT/tests/.tmp/real-mode-log" "$home"
rm -f "$ACMESH_CONSOLE_CONFIG"
mkdir -p "$home"

cat > "$home/acme.sh" <<'SH'
#!/bin/sh
printf 'FAKE_ACME_CALLED %s\n' "$*"
exit 0
SH
chmod +x "$home/acme.sh"

set +e
missing_email_out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" issue --home "$home" --domain example.com --key-type ecc --dns-api dns_cf --real-mode 2>&1)"
missing_email_rc=$?
set -e
case "$missing_email_rc:$missing_email_out" in
	0:*) echo "real mode without account email should fail"; echo "$missing_email_out"; exit 1 ;;
	*account\ email\ is\ required*) ;;
	*) echo "real mode without account email failed for wrong reason"; echo "$missing_email_out"; exit 1 ;;
esac

out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" issue --home "$home" --domain example.com --key-type ecc --dns-api dns_cf --account-email user@example.org --real-mode)"
case "$out" in
	*'"ok":true'*'"taskId"'*) ;;
	*) echo "real mode did not create task"; echo "$out"; exit 1 ;;
esac

task_id="$(printf '%s' "$out" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
sleep 1
status="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-status --task-id "$task_id")"
log="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-log --task-id "$task_id")"

case "$status" in
	*'"status":"success"'*) ;;
	*) echo "real mode task did not succeed"; echo "$status"; echo "$log"; exit 1 ;;
esac

case "$log" in
	*"REAL MODE"*"Using account email: user@example.org"*"FAKE_ACME_CALLED"*"--issue"*"--accountemail user@example.org"*"--dns dns_cf"*) ;;
	*) echo "real mode did not execute fake acme.sh"; echo "$log"; exit 1 ;;
esac

echo "test_issue_real_mode: ok"
