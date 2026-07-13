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
	2:*real\ issue\ requires\ profileId*) ;;
	*) echo "legacy real issue was not rejected"; exit 1 ;;
esac

set +e; out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" issue --home "$home" --domain example.com --key-type ecc --dns-api dns_cf --account-email user@example.org --real-mode)"; rc=$?; set -e
[ "$rc" = 2 ]; printf '%s' "$out" | grep -F 'real issue requires profileId' >/dev/null
[ ! -e "$ACMESH_TASK_STATE_DIR" ] && [ ! -e "$ACMESH_TASK_LOG_DIR" ]

echo "test_issue_real_mode: ok"
