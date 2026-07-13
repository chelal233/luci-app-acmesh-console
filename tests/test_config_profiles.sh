#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
export ACMESH_CONSOLE_CONFIG="$ROOT/tests/.tmp/acmesh-console-config.json"
export ACMESH_CONSOLE_UCI_CONFIG="$ROOT/tests/.tmp/acmesh-console-uci"
export ACMESH_TASK_STATE_DIR="$ROOT/tests/.tmp/config-profile-state"
export ACMESH_TASK_LOG_DIR="$ROOT/tests/.tmp/config-profile-log"
rm -rf "$ROOT/tests/.tmp/config-test"
mkdir -p "$ROOT/tests/.tmp"
chmod 700 "$ROOT/tests/.tmp"
rm -rf "$ACMESH_CONSOLE_CONFIG" "$ACMESH_TASK_STATE_DIR" "$ACMESH_TASK_LOG_DIR"
cat > "$ACMESH_CONSOLE_UCI_CONFIG" <<'EOF'
config acmesh-console 'main'
	option home '/tmp/acme-bootstrap'
	option default_account_email 'bootstrap@example.com'
	option test_mode '0'
	option core_tag 'v3.1.3'
EOF

default_json="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" config-get)"
case "$default_json" in
	*'"defaultAccountEmail":"bootstrap@example.com"'*'"coreTag":"v3.1.3"'*'"acmeHome":"/tmp/acme-bootstrap"'*) ;;
	*) echo "default config missing global defaults"; echo "$default_json"; exit 1 ;;
esac
case "$default_json" in *'"testMode"'*) echo "legacy global test mode was not removed"; exit 1;; esac
case "$default_json" in
	*'"schemaVersion":2'*'"accountProfiles":[]'*'"issueProfiles":[]'*'"deployProfiles":[]'*) ;;
	*) echo "default config missing profile arrays"; echo "$default_json"; exit 1 ;;
esac

saved='{"schemaVersion":2,"global":{"defaultAccountEmail":"ops@example.com","coreTag":"v3.1.4","acmeHome":"'"$ROOT"'/tests/.tmp/config-acme-home"},"accountProfiles":[{"id":"acc1","name":"LE Staging","ca":"letsencrypt_staging","accountEmail":""}],"issueProfiles":[{"id":"issue1","name":"Gate","domain":"gate.example.org","accountProfileId":"acc1","deployProfileId":"","keyType":"ec256","validationMethod":"dns","testModeOverride":"force-real-mode","dnsApi":"dns_cf","credentialMode":"token","credentials":{"CF_Token":"secret-token","CF_Zone_ID":"zone-id"}}],"deployProfiles":[]}'
request="$ROOT/tests/.tmp/config-save-request.json"
printf '%s\n' "$saved" > "$request"
chmod 600 "$request"
save_out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" config-save --request-file "$request")"
case "$save_out" in
	*'"ok":true'*) ;;
	*) echo "config-save failed"; echo "$save_out"; exit 1 ;;
esac
config_mode="$(ls -ld "$ACMESH_CONSOLE_CONFIG" | awk '{print $1}')"
case "$config_mode" in
	-rw-------) ;;
	*) echo "config file should be mode 600, got $config_mode"; exit 1 ;;
esac
config_dir_mode="$(ls -ld "${ACMESH_CONSOLE_CONFIG%/*}" | awk '{print $1}')"
case "$config_dir_mode" in
	drwx------) ;;
	*) echo "config directory should be mode 700, got $config_dir_mode"; exit 1 ;;
esac

loaded="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" config-get)"
printf '%s' "$loaded" | jsonfilter -e '@.global.defaultAccountEmail' | grep -Fx ops@example.com >/dev/null || { echo "saved config was not loaded"; exit 1; }
printf '%s' "$loaded" | jsonfilter -e '@.accountProfiles[0].id' | grep -Fx acc1 >/dev/null || { echo "account profile was not loaded"; exit 1; }
printf '%s' "$loaded" | jsonfilter -e '@.issueProfiles[0].credentials.CF_Token' | grep -Fx secret-token >/dev/null || { echo "issue credentials were not preserved"; exit 1; }

if sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" config-save --json "$saved" >/dev/null 2>&1; then
	echo "config-save should reject raw --json"
	exit 1
fi

legacy="$ROOT/tests/.tmp/config-legacy-request.json"
printf '%s\n' "${saved#*\"schemaVersion\":2,}" | sed 's/^/{/' > "$legacy"
legacy_out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" config-save --request-file "$legacy")"
case "$legacy_out" in *'"ok":true'*) ;; *) echo "legacy config was not normalized"; exit 1;; esac
legacy_loaded="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" config-get)"
[ "$(printf '%s' "$legacy_loaded" | jsonfilter -e '@.schemaVersion')" = 2 ] || { echo "legacy config was not saved as schema v2"; exit 1; }

configured_home="$ROOT/tests/.tmp/config-acme-home"
mkdir -p "$configured_home/custom.example_ecc"
cat > "$configured_home/custom.example_ecc/custom.example.conf" <<'EOF'
Le_Domain='custom.example'
Le_API='dns_cf'
EOF
default_status="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" status)"
case "$default_status" in
	*'"home":"'"$configured_home"'"'*'"mainDomain":"custom.example"'*) ;;
	*) echo "status should use saved acmeHome by default"; echo "$default_status"; exit 1 ;;
esac

renew_out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" renew --domain custom.example --key-type ecc --test-mode)"
case "$renew_out" in
	*'"ok":true'*'"testMode":true'*'"command"'*) ;;
	*) echo "renew should inherit saved test mode"; echo "$renew_out"; exit 1 ;;
esac
case "$renew_out" in
	*"--home '$configured_home'"*"--renew"*) ;;
	*) echo "renew should use saved acmeHome by default"; echo "$renew_out"; exit 1 ;;
esac

managed_preview="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" deploy-preview --type ssh --cert-source managed-acme --domain custom.example --key-type ecc --host 192.0.2.10 --key-file /etc/ssl/custom.key --fullchain-file /etc/ssl/custom.fullchain.pem)"
case "$managed_preview" in
	*"$configured_home/custom.example_ecc/fullchain.cer"*"$configured_home/custom.example_ecc/custom.example.key"*) ;;
	*) echo "managed deploy should use saved acmeHome by default"; echo "$managed_preview"; exit 1 ;;
esac

export ACMESH_TASK_STATE_DIR="$ROOT/tests/.tmp/config-default-state"
export ACMESH_TASK_LOG_DIR="$ROOT/tests/.tmp/config-default-log"
rm -rf "$ACMESH_TASK_STATE_DIR" "$ACMESH_TASK_LOG_DIR"
core_out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" core-install --home "$ROOT/tests/.tmp/config-core-home" --test-mode)"
case "$core_out" in
	*'"testMode":true'*'"command"'*) ;;
	*) echo "core-install should inherit global testMode"; echo "$core_out"; exit 1 ;;
esac
case "$core_out" in
	*"refs/tags/v3.1.4.tar.gz"*"ops@example.com"*) ;;
	*) echo "core-install did not use global default email/tag"; echo "$core_out"; exit 1 ;;
esac

issue_out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" issue --domain example.com --key-type ec256 --validation-method dns --dns-api dns_cf --test-mode)"
case "$issue_out" in
	*'"testMode":true'*'"command"'*) ;;
	*) echo "issue should inherit global testMode"; echo "$issue_out"; exit 1 ;;
esac

echo "test_config_profiles: ok"
