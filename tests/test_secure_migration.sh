#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
command -v jsonfilter >/dev/null 2>&1 || { echo "test_secure_migration: SKIP (jsonfilter unavailable)"; exit 0; }
TMP="${TMPDIR:-/tmp}/acmesh-migration.$$"; trap 'rm -rf "$TMP"' 0 HUP INT TERM
mkdir -p "$TMP/config" "$TMP/state" "$TMP/challenges" "$TMP/pending" "$TMP/tasks"; chmod 700 "$TMP" "$TMP/config" "$TMP/state" "$TMP/challenges" "$TMP/pending" "$TMP/tasks"
. "$ROOT/tests/lib/host_flock.sh"; acmesh_test_install_flock_shim "$TMP/flock"; acmesh_test_install_private_ls_shim "$TMP/private-ls" "$TMP"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
export ACMESH_CONSOLE_CONFIG="$TMP/config/config.json" ACMESH_CONSOLE_UCI_CONFIG="$TMP/missing-uci" ACMESH_PENDING_IMPORT_DIR="$TMP/pending"
export ACMESH_CONFIG_LOCK_FILE="$TMP/config/config.lock"
export ACMESH_AUTH_STATE_DIR="$TMP/state" ACMESH_AUTH_INSTANCE_FILE="$TMP/state/instance-id" ACMESH_AUTH_LEDGER_FILE="$TMP/state/authorizations.json" ACMESH_AUTH_LOCK_FILE="$TMP/state/authorization.lock" ACMESH_AUTH_CHALLENGE_DIR="$TMP/challenges"
export ACMESH_TASK_STATE_DIR="$TMP/tasks/state" ACMESH_TASK_LOG_DIR="$TMP/tasks/log"
CTL="$ROOT/root/usr/libexec/acmesh-console/acmeshctl"
base='{"schemaVersion":2,"global":{"defaultAccountEmail":"old@example.org","coreTag":"v3.1.4","acmeHome":"/etc/acme"},"accountProfiles":[],"issueProfiles":[],"deployProfiles":[]}'
printf '%s\n' "$base" > "$ACMESH_CONSOLE_CONFIG"; chmod 600 "$ACMESH_CONSOLE_CONFIG"
candidate='{"schemaVersion":2,"global":{"defaultAccountEmail":"new@example.org","coreTag":"v3.1.4","acmeHome":"/etc/acme"},"accountProfiles":[],"issueProfiles":[],"deployProfiles":[]}'
envelope="{\"format\":\"acmesh-console-config\",\"version\":1,\"config\":$candidate}"
escaped="$(printf '%s' "$envelope" | sed 's/\\/\\\\/g; s/"/\\"/g')"
printf '{"payload":"%s"}\n' "$escaped" > "$TMP/preview.json"
preview="$(sh "$CTL" import-preview --request-file "$TMP/preview.json")"
preview_id="$(printf '%s' "$preview" | jsonfilter -e '@.previewId')"; [ "${#preview_id}" = 64 ]
[ -f "$TMP/pending/$preview_id.json" ] && [ ! -L "$TMP/pending/$preview_id.json" ]
printf '{"previewId":"%s"}\n' "$preview_id" > "$TMP/apply.json"
set +e; challenge="$(sh "$CTL" import-apply --request-file "$TMP/apply.json")"; rc=$?; set -e
[ "$rc" = 3 ]; challenge_id="$(printf '%s' "$challenge" | jsonfilter -e '@.challengeId')"
printf '{"challengeId":"%s","decision":"remember"}\n' "$challenge_id" > "$TMP/execute.json"
set +e; denied="$(sh "$CTL" authorization-execute --request-file "$TMP/execute.json")"; denied_rc=$?; set -e
[ "$denied_rc" = 2 ]; printf '%s' "$denied" | grep -F 'rememberNotAllowed' >/dev/null
# A consumed destructive challenge cannot be retried; create a fresh one.
sh "$CTL" import-preview --request-file "$TMP/preview.json" >/dev/null
set +e; challenge="$(sh "$CTL" import-apply --request-file "$TMP/apply.json")"; rc=$?; set -e; [ "$rc" = 3 ]
challenge_id="$(printf '%s' "$challenge" | jsonfilter -e '@.challengeId')"; printf '{"challengeId":"%s","decision":"once"}\n' "$challenge_id" > "$TMP/execute.json"
applied="$(sh "$CTL" authorization-execute --request-file "$TMP/execute.json")"
printf '%s' "$applied" | grep -F '"applied":true' >/dev/null
[ "$(jsonfilter -i "$ACMESH_CONSOLE_CONFIG" -e '@.global.defaultAccountEmail')" = new@example.org ]
[ ! -e "$TMP/pending/$preview_id.json" ]
[ ! -e "$ACMESH_TASK_STATE_DIR" ] && [ ! -e "$ACMESH_TASK_LOG_DIR" ]

# Export is direct, contains only the validated config envelope, and never logs secrets.
printf '%s\n' '{"scope":"config-with-secrets"}' > "$TMP/export.json"
set +e; export_challenge="$(sh "$CTL" secret-export --request-file "$TMP/export.json")"; rc=$?; set -e; [ "$rc" = 3 ]
export_id="$(printf '%s' "$export_challenge" | jsonfilter -e '@.challengeId')"; printf '{"challengeId":"%s","decision":"remember"}\n' "$export_id" > "$TMP/execute.json"
exported="$(sh "$CTL" authorization-execute --request-file "$TMP/execute.json")"
printf '%s' "$exported" | grep -F '"format":"acmesh-console-config"' >/dev/null
printf '%s' "$exported" | grep -F 'new@example.org' >/dev/null
case "$exported" in *authorizations.json*|*instance-id*|*known_hosts*|*taskId*|*challengeId*) exit 1;; esac
[ ! -e "$ACMESH_TASK_LOG_DIR" ]
# Config bytes are the remembered export identity.
sed -i 's/new@example.org/changed@example.org/' "$ACMESH_CONSOLE_CONFIG"
set +e; changed="$(sh "$CTL" secret-export --request-file "$TMP/export.json")"; changed_rc=$?; set -e
[ "$changed_rc" = 3 ]; printf '%s' "$changed" | grep -F '"authorizationRequired":true' >/dev/null

# Pending bytes are immutable authorization material.
preview="$(sh "$CTL" import-preview --request-file "$TMP/preview.json")"; preview_id="$(printf '%s' "$preview" | jsonfilter -e '@.previewId')"
printf '{"previewId":"%s"}\n' "$preview_id" > "$TMP/apply.json"
set +e; challenge="$(sh "$CTL" import-apply --request-file "$TMP/apply.json")"; rc=$?; set -e; [ "$rc" = 3 ]
printf ' ' >> "$TMP/pending/$preview_id.json"
challenge_id="$(printf '%s' "$challenge" | jsonfilter -e '@.challengeId')"; printf '{"challengeId":"%s","decision":"once"}\n' "$challenge_id" > "$TMP/execute.json"
set +e; sh "$CTL" authorization-execute --request-file "$TMP/execute.json" >/dev/null 2>&1; stale_rc=$?; set -e
[ "$stale_rc" != 0 ]; [ "$(jsonfilter -i "$ACMESH_CONSOLE_CONFIG" -e '@.global.defaultAccountEmail')" = changed@example.org ]

for invalid in \
	'{"format":"wrong","version":1,"config":{}}' \
	'{"format":"acmesh-console-config","version":"1","config":{"schemaVersion":2,"global":{},"accountProfiles":[],"issueProfiles":[],"deployProfiles":[]}}' \
	'{"format":"acmesh-console-config","version":1,"unexpected":true,"config":{"schemaVersion":2,"global":{},"accountProfiles":[],"issueProfiles":[],"deployProfiles":[]}}' \
	'{"format":"acmesh-console-config","version":2,"config":{}}' \
	'{"format":"acmesh-console-config","version":1,"config":{"global":{"defaultAccountEmail":"","coreTag":"v3.1.4","acmeHome":"/etc/acme"},"accountProfiles":[],"issueProfiles":[],"deployProfiles":[]}}' \
	'{"format":"acmesh-console-config","version":1,"config":{"global":[],"accountProfiles":[],"issueProfiles":[],"deployProfiles":[]}}' \
	'{"format":"acmesh-console-config","version":1,"config":{"schemaVersion":2,"global":{"defaultAccountEmail":"","coreTag":"v3.1.4","acmeHome":"/etc/acme"},"accountProfiles":[{"id":"dup","name":"One","ca":"letsencrypt","accountEmail":""},{"id":"dup","name":"Two","ca":"letsencrypt","accountEmail":""}],"issueProfiles":[],"deployProfiles":[]}}' \
	'{"format":"acmesh-console-config","version":1,"config":{"schemaVersion":2,"global":{"defaultAccountEmail":"","coreTag":"v3.1.4","acmeHome":"/etc/acme"},"accountProfiles":[],"issueProfiles":[{"id":"dangling","name":"Dangling","domain":"dangling.example","accountProfileId":"missing","deployProfileId":"","keyType":"ec256","validationMethod":"standalone","testModeOverride":"force-real-mode"}],"deployProfiles":[]}}'; do
	escaped="$(printf '%s' "$invalid" | sed 's/\\/\\\\/g; s/"/\\"/g')"; printf '{"payload":"%s"}\n' "$escaped" > "$TMP/invalid.json"
	if sh "$CTL" import-preview --request-file "$TMP/invalid.json" >/dev/null 2>&1; then echo "invalid import accepted"; exit 1; fi
done
echo "test_secure_migration: ok"
