#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
export ACMESH_TASK_STATE_DIR="$ROOT/tests/.tmp/account-email-state"
export ACMESH_TASK_LOG_DIR="$ROOT/tests/.tmp/account-email-log"
export ACMESH_CONSOLE_CONFIG="$ROOT/tests/.tmp/account-email-config.json"
home="$ROOT/tests/.tmp/account-email-home"
rm -rf "$ACMESH_TASK_STATE_DIR" "$ACMESH_TASK_LOG_DIR" "$home" "$ACMESH_CONSOLE_CONFIG"
mkdir -p "$home"

cat > "$home/acme.sh" <<'SH'
#!/bin/sh
printf 'FAKE_ACCOUNT_EMAIL=%s\n' "$ACCOUNT_EMAIL"
printf 'FAKE_ACME_CALLED %s\n' "$*"
exit 0
SH
chmod +x "$home/acme.sh"
cat > "$home/account.conf" <<'SH'
    ACCOUNT_EMAIL='admin@example.com'
SH

saved='{"schemaVersion":2,"global":{"defaultAccountEmail":"ops@example.org","coreTag":"v3.1.4","acmeHome":"/etc/acme"},"accountProfiles":[],"issueProfiles":[],"deployProfiles":[]}'
config_request="$ROOT/tests/.tmp/account-email-config-request.json"
printf '%s\n' "$saved" > "$config_request"
chmod 600 "$config_request"
sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" config-save --request-file "$config_request" >/dev/null

preview="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" preview-issue --home "$home" --domain example.org --key-type ec256 --validation-method dns --dns-api dns_cf --test-mode)"
case "$preview" in
	*"ACCOUNT_EMAIL='ops@example.org'"*"--accountemail 'ops@example.org'"*) ;;
	*) echo "preview did not include default account email"; echo "$preview"; exit 1 ;;
esac

set +e; out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" issue --home "$home" --domain example.org --key-type ec256 --validation-method dns --dns-api dns_cf --account-email user@example.org --real-mode)"; rc=$?; set -e
[ "$rc" = 2 ] && printf '%s' "$out" | grep -F 'real issue requires profileId' >/dev/null
. "$ACMESH_LIB_DIR/command.sh"
log="$(acmesh_execute_issue "$home" example.org ec256 dns dns_cf '' '' '' letsencrypt user@example.org example.org)"
case "$log" in
	*"ACCOUNT_EMAIL='user@example.org'"*"--accountemail 'user@example.org'"*"FAKE_ACCOUNT_EMAIL=user@example.org"*) ;;
	*) echo "real issue did not export account email"; echo "$log"; exit 1 ;;
esac
case "$(cat "$home/account.conf")" in
	*"ACCOUNT_EMAIL='user@example.org'"*) ;;
	*) echo "account.conf was not reconciled"; cat "$home/account.conf"; exit 1 ;;
esac
case "$(cat "$home/account.conf")" in
	*"admin@example.com"*) echo "old account email was not replaced"; cat "$home/account.conf"; exit 1 ;;
esac

echo "test_issue_account_email: ok"
