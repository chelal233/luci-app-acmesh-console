#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
command -v jsonfilter >/dev/null 2>&1 || { echo "test_destructive_authorization: SKIP (jsonfilter unavailable)"; exit 0; }
TMP="${TMPDIR:-/tmp}/acmesh-destructive.$$"; trap 'rm -rf "$TMP"' 0 HUP INT TERM
mkdir -p "$TMP/config" "$TMP/state" "$TMP/challenges" "$TMP/tasks" "$TMP/acme/example.org_ecc"; chmod 700 "$TMP" "$TMP/config" "$TMP/state" "$TMP/challenges" "$TMP/tasks" "$TMP/acme" "$TMP/acme/example.org_ecc"
. "$ROOT/tests/lib/host_flock.sh"; acmesh_test_install_flock_shim "$TMP/flock"; acmesh_test_install_private_ls_shim "$TMP/private-ls" "$TMP"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib" ACMESH_CONSOLE_CONFIG="$TMP/config/config.json" ACMESH_CONSOLE_UCI_CONFIG="$TMP/missing-uci" ACMESH_ACME_HOME="$TMP/acme"
export ACMESH_CONFIG_LOCK_FILE="$TMP/config/config.lock"
export ACMESH_AUTH_STATE_DIR="$TMP/state" ACMESH_AUTH_INSTANCE_FILE="$TMP/state/instance-id" ACMESH_AUTH_LEDGER_FILE="$TMP/state/authorizations.json" ACMESH_AUTH_LOCK_FILE="$TMP/state/authorization.lock" ACMESH_AUTH_CHALLENGE_DIR="$TMP/challenges"
export ACMESH_TASK_STATE_DIR="$TMP/tasks/state" ACMESH_TASK_LOG_DIR="$TMP/tasks/log" ACMESH_TASK_WORKSPACE_DIR="$TMP/tasks/workspaces" ACMESH_RUNTIME_DIR="$TMP/runtime" ACMESH_DESTRUCTIVE_TRACE="$TMP/acme-trace"
CTL="$ROOT/root/usr/libexec/acmesh-console/acmeshctl"
cat > "$ACMESH_CONSOLE_CONFIG" <<JSON
{"schemaVersion":2,"global":{"defaultAccountEmail":"ops@example.org","coreTag":"v3.1.4","acmeHome":"$TMP/acme"},"accountProfiles":[{"id":"used-account","name":"Used","ca":"letsencrypt","accountEmail":""},{"id":"delete-account","name":"Delete","ca":"letsencrypt","accountEmail":""}],"issueProfiles":[{"id":"used-issue","name":"Used","domain":"used.example.org","accountProfileId":"used-account","deployProfileId":"","keyType":"ec256","validationMethod":"standalone","testModeOverride":"force-real-mode"}],"deployProfiles":[]}
JSON
chmod 600 "$ACMESH_CONSOLE_CONFIG"
cat > "$TMP/acme/example.org_ecc/example.org.conf" <<'CONF'
Le_Domain='example.org'
Le_Keylength='ec-256'
CONF
chmod 600 "$TMP/acme/example.org_ecc/example.org.conf"
cat > "$TMP/acme/acme.sh" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$ACMESH_DESTRUCTIVE_TRACE"
SH
chmod 700 "$TMP/acme/acme.sh"

printf '%s\n' '{"profileType":"account","profileId":"used-account"}' > "$TMP/delete-used.json"
set +e; referenced="$(sh "$CTL" profile-delete --request-file "$TMP/delete-used.json")"; referenced_rc=$?; set -e
[ "$referenced_rc" = 4 ]; printf '%s' "$referenced" | grep -F 'profileReferenced' >/dev/null; printf '%s' "$referenced" | grep -F 'dependencies' >/dev/null
# Ordinary config-save cannot bypass the destructive authorization route by
# silently omitting an existing profile.
cat > "$TMP/bypass-delete.json" <<JSON
{"schemaVersion":2,"global":{"defaultAccountEmail":"ops@example.org","coreTag":"v3.1.4","acmeHome":"$TMP/acme"},"accountProfiles":[{"id":"used-account","name":"Used","ca":"letsencrypt","accountEmail":""}],"issueProfiles":[{"id":"used-issue","name":"Used","domain":"used.example.org","accountProfileId":"used-account","deployProfileId":"","keyType":"ec256","validationMethod":"standalone","testModeOverride":"force-real-mode"}],"deployProfiles":[]}
JSON
set +e; bypass="$(sh "$CTL" config-save --request-file "$TMP/bypass-delete.json")"; bypass_rc=$?; set -e
[ "$bypass_rc" = 4 ]; printf '%s' "$bypass" | grep -F 'profile deletion requires profile-delete authorization' >/dev/null
printf '%s\n' '{"profileType":"account","profileId":"delete-account"}' > "$TMP/delete.json"
set +e; delete_challenge="$(sh "$CTL" profile-delete --request-file "$TMP/delete.json")"; rc=$?; set -e; [ "$rc" = 3 ]
delete_id="$(printf '%s' "$delete_challenge" | jsonfilter -e '@.challengeId')"; printf '{"challengeId":"%s","decision":"remember"}\n' "$delete_id" > "$TMP/execute.json"
set +e; denied="$(sh "$CTL" authorization-execute --request-file "$TMP/execute.json")"; denied_rc=$?; set -e; [ "$denied_rc" = 2 ]; printf '%s' "$denied" | grep -F rememberNotAllowed >/dev/null
set +e; delete_challenge="$(sh "$CTL" profile-delete --request-file "$TMP/delete.json")"; rc=$?; set -e; [ "$rc" = 3 ]
delete_id="$(printf '%s' "$delete_challenge" | jsonfilter -e '@.challengeId')"; printf '{"challengeId":"%s","decision":"once"}\n' "$delete_id" > "$TMP/execute.json"
deleted="$(sh "$CTL" authorization-execute --request-file "$TMP/execute.json")"; printf '%s' "$deleted" | grep -F '"deleted":true' >/dev/null
! jsonfilter -i "$ACMESH_CONSOLE_CONFIG" -e '@.accountProfiles[*].id' | grep -Fx delete-account >/dev/null
set +e; reused="$(sh "$CTL" authorization-execute --request-file "$TMP/execute.json")"; reused_rc=$?; set -e; [ "$reused_rc" = 4 ]

run_certificate_action() {
	command="$1" expected="$2" request="$TMP/$command.json"; printf '%s\n' '{"domain":"example.org","keyType":"ec256"}' > "$request"
	set +e; challenge="$(sh "$CTL" "$command" --request-file "$request")"; rc=$?; set -e; [ "$rc" = 3 ]
	id="$(printf '%s' "$challenge" | jsonfilter -e '@.challengeId')"; printf '{"challengeId":"%s","decision":"once"}\n' "$id" > "$TMP/execute.json"
	if [ "$command" = certificate-revoke ]; then
		printf '{"challengeId":"%s","decision":"remember"}\n' "$id" > "$TMP/execute.json"
		set +e; denied="$(sh "$CTL" authorization-execute --request-file "$TMP/execute.json")"; denied_rc=$?; set -e; [ "$denied_rc" = 2 ]; printf '%s' "$denied" | grep -F rememberNotAllowed >/dev/null
		set +e; challenge="$(sh "$CTL" "$command" --request-file "$request")"; rc=$?; set -e; [ "$rc" = 3 ]; id="$(printf '%s' "$challenge" | jsonfilter -e '@.challengeId')"
	fi
	printf '{"challengeId":"%s","decision":"once"}\n' "$id" > "$TMP/execute.json"
	result="$(sh "$CTL" authorization-execute --request-file "$TMP/execute.json")"; task_id="$(printf '%s' "$result" | jsonfilter -e '@.taskId')"; [ -n "$task_id" ]
	i=0; while [ "$i" -lt 30 ]; do status="$(sh "$CTL" task-status --task-id "$task_id")"; state="$(printf '%s' "$status" | jsonfilter -e '@.status')"; [ "$state" = running ] || break; sleep 1; i=$((i + 1)); done
	[ "$state" = success ]; grep -F -- "--$expected -d example.org --ecc" "$ACMESH_DESTRUCTIVE_TRACE" >/dev/null
	set +e; sh "$CTL" authorization-execute --request-file "$TMP/execute.json" >/dev/null 2>&1; reused_rc=$?; set -e; [ "$reused_rc" = 4 ]
}
run_certificate_action certificate-revoke revoke
run_certificate_action certificate-remove remove
echo "test_destructive_authorization: ok"
