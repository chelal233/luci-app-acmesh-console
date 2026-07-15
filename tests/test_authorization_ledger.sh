#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
command -v jsonfilter >/dev/null 2>&1 || { echo "test_authorization_ledger: SKIP (jsonfilter unavailable)"; exit 0; }
TMP="${TMPDIR:-/tmp}/acmesh-auth-ledger.$$"
trap 'rm -rf "$TMP"' 0 HUP INT TERM
mkdir -p "$TMP/state" "$TMP/challenges" "$TMP/material" "$TMP/bin"; chmod 700 "$TMP" "$TMP/state" "$TMP/challenges" "$TMP/material"
. "$ROOT/tests/lib/host_flock.sh"
acmesh_test_install_flock_shim "$TMP/flock"
acmesh_test_install_private_ls_shim "$TMP/private-ls" "$TMP"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
export ACMESH_AUTH_STATE_DIR="$TMP/state" ACMESH_AUTH_INSTANCE_FILE="$TMP/state/instance-id"
export ACMESH_AUTH_LEDGER_FILE="$TMP/state/authorizations.json" ACMESH_AUTH_LOCK_FILE="$TMP/state/authorization.lock"
export ACMESH_AUTH_CHALLENGE_DIR="$TMP/challenges"
. "$ROOT/root/usr/libexec/acmesh-console/lib/authorization.sh"

NOW=1783658400
acmesh_auth_now() { printf '%s\n' "$NOW"; }
make_material() {
	ACMESH_AUTH_ACCOUNT_ID=account-1 ACMESH_AUTH_CA=letsencrypt ACMESH_AUTH_PRIMARY_DOMAIN="${DOMAIN:-example.com}" \
	ACMESH_AUTH_DOMAINS="${DOMAIN:-example.com}" ACMESH_AUTH_KEY_TYPE=ec256 ACMESH_AUTH_VALIDATION=dns ACMESH_AUTH_DNS_API=dns_cf \
	ACMESH_AUTH_DNS_SLEEP=30 ACMESH_AUTH_TEST_MODE=false acmesh_auth_snapshot issue issueProfile issue-1 "$TMP/material/current"
	printf '{"domain":"%s"}\n' "${DOMAIN:-example.com}" > "$TMP/material/summary"; chmod 600 "$TMP/material/summary"
}
recompute() { cp "$TMP/material/current" "$4"; cp "$TMP/material/summary" "$5"; chmod 600 "$4" "$5"; }
admit() { printf '%s:%s\n' "$3" "$4" >> "$TMP/admitted"; }
export ACMESH_AUTH_RECOMPUTE_CALLBACK=recompute ACMESH_AUTH_ADMIT_CALLBACK=admit
make_material

set +e; first="$(acmesh_auth_prepare issue issueProfile issue-1 "$TMP/material/current" "$TMP/material/summary")"; rc=$?; set -e
[ "$rc" = 3 ]; id="$(printf '%s' "$first" | jsonfilter -e '@.challengeId')"; [ -n "$id" ]
set -- $(LC_ALL=C ls -l "$TMP/challenges/$id.json"); [ "$1" = -rw------- ]
acmesh_auth_execute "$id" once | grep -F '"ok":true' >/dev/null
[ "$(jsonfilter -i "$TMP/state/authorizations.json" -e '@.records[*].id' | wc -l | tr -d ' ')" = 0 ]
if acmesh_auth_execute "$id" once >/dev/null 2>&1; then echo "consumed challenge reused"; exit 1; fi

set +e; out="$(acmesh_auth_prepare issue issueProfile issue-1 "$TMP/material/current" "$TMP/material/summary")"; rc=$?; set -e
[ "$rc" = 3 ]; id="$(printf '%s' "$out" | jsonfilter -e '@.challengeId')"
acmesh_auth_execute "$id" remember >/dev/null
[ "$(jsonfilter -i "$TMP/state/authorizations.json" -e '@.records[0].useCount')" = 1 ]
acmesh_auth_prepare issue issueProfile issue-1 "$TMP/material/current" "$TMP/material/summary" | grep -F '"remembered":true' >/dev/null
[ "$(jsonfilter -i "$TMP/state/authorizations.json" -e '@.records[0].useCount')" = 2 ]

# A canonical snapshot cannot be admitted under a different caller-supplied subject.
before_admissions="$(wc -l < "$TMP/admitted" | tr -d ' ')"
if acmesh_auth_prepare issue issueProfile substituted-subject "$TMP/material/current" "$TMP/material/summary" >/dev/null 2>&1; then
	echo "snapshot identity mismatch was admitted"; exit 1
fi
[ "$(wc -l < "$TMP/admitted" | tr -d ' ')" = "$before_admissions" ]

# Cosmetic values are not material; changing a dangerous field is.
ACMESH_AUTH_NAME=renamed ACMESH_AUTH_DESCRIPTION=changed make_material
acmesh_auth_prepare issue issueProfile issue-1 "$TMP/material/current" "$TMP/material/summary" | grep -F '"remembered":true' >/dev/null
DOMAIN=other.example make_material
set +e; changed="$(acmesh_auth_prepare issue issueProfile issue-1 "$TMP/material/current" "$TMP/material/summary")"; rc=$?; set -e
[ "$rc" = 3 ]; changed_id="$(printf '%s' "$changed" | jsonfilter -e '@.challengeId')"
DOMAIN=third.example make_material
if acmesh_auth_execute "$changed_id" once >/dev/null 2>&1; then echo "changed challenge admitted"; exit 1; fi

# Expiry and pruning preserve live challenges but remove expired and old consuming files.
DOMAIN=expire.example make_material
set +e; expired="$(acmesh_auth_prepare issue issueProfile issue-1 "$TMP/material/current" "$TMP/material/summary")"; rc=$?; set -e
[ "$rc" = 3 ]; expired_id="$(printf '%s' "$expired" | jsonfilter -e '@.challengeId')"; NOW=$((NOW + 301))
if acmesh_auth_execute "$expired_id" once >/dev/null 2>&1; then echo "expired challenge admitted"; exit 1; fi
NOW=$((NOW + 1)); DOMAIN=live.example make_material
set +e; live="$(acmesh_auth_prepare issue issueProfile issue-1 "$TMP/material/current" "$TMP/material/summary")"; rc=$?; set -e
[ "$rc" = 3 ]; live_id="$(printf '%s' "$live" | jsonfilter -e '@.challengeId')"
sed 's/"createdAt":[0-9][0-9]*/"createdAt":1/' "$TMP/challenges/$live_id.json" > "$TMP/challenges/orphan.json.consuming"; chmod 600 "$TMP/challenges/orphan.json.consuming"
NOW=$((NOW + 1)); acmesh_auth_prune_challenges "$NOW"
[ -f "$TMP/challenges/$live_id.json" ] || { echo "live challenge pruned"; exit 1; }
[ ! -e "$TMP/challenges/orphan.json.consuming" ]

# Challenge execution is bound to the router instance that created it.
DOMAIN=instance-bound.example make_material
set +e; bound="$(acmesh_auth_prepare issue issueProfile issue-1 "$TMP/material/current" "$TMP/material/summary")"; rc=$?; set -e
[ "$rc" = 3 ]; bound_id="$(printf '%s' "$bound" | jsonfilter -e '@.challengeId')"
saved_instance="$(cat "$TMP/state/instance-id")"
printf '%032d\n' 7 > "$TMP/state/instance-id"; chmod 600 "$TMP/state/instance-id"
if acmesh_auth_execute "$bound_id" once >/dev/null 2>&1; then echo "cross-instance challenge admitted"; exit 1; fi
printf '%s\n' "$saved_instance" > "$TMP/state/instance-id"; chmod 600 "$TMP/state/instance-id"

# Ledger validation rejects non-object records and extra fields that could hide secrets.
instance="$(cat "$TMP/state/instance-id")"
printf '{"schemaVersion":1,"instanceId":"%s","ackVersion":1,"records":["bad"]}\n' "$instance" > "$TMP/bad-record-type"; chmod 600 "$TMP/bad-record-type"
if acmesh_auth_ledger_valid "$TMP/bad-record-type"; then echo "non-object ledger record accepted"; exit 1; fi
printf '{"schemaVersion":1,"instanceId":"%s","ackVersion":1,"records":[{"id":"record-1","operation":"issue","subjectType":"issueProfile","subjectId":"issue-1","fingerprint":"sha256:%064d","grantedAt":"1","lastUsedAt":"1","useCount":1,"ackVersion":1,"secret":"must-not-exist"}]}\n' "$instance" 0 > "$TMP/extra-record-field"; chmod 600 "$TMP/extra-record-field"
if acmesh_auth_ledger_valid "$TMP/extra-record-field"; then echo "extra ledger record field accepted"; exit 1; fi
printf '{"schemaVersion":1,"instanceId":"%s","ackVersion":1,"records":[],"secret":"must-not-exist"}\n' "$instance" > "$TMP/extra-envelope-field"; chmod 600 "$TMP/extra-envelope-field"
if acmesh_auth_ledger_valid "$TMP/extra-envelope-field"; then echo "extra ledger envelope field accepted"; exit 1; fi

# Syntactically valid records for unknown operations remain visible as Unsupported.
printf '{"schemaVersion":1,"instanceId":"%s","ackVersion":1,"records":[{"id":"unsupported-1","operation":"future-operation","subjectType":"futureType","subjectId":"future-1","fingerprint":"sha256:%064d","grantedAt":"1","lastUsedAt":"1","useCount":1,"ackVersion":1}]}\n' "$instance" 0 > "$TMP/state/authorizations.json"; chmod 600 "$TMP/state/authorizations.json"
acmesh_auth_list | grep -F '"status":"Unsupported"' >/dev/null

# Corrupt state is retained and cannot silently authorize; migration never contains it.
printf '{broken\n' > "$TMP/state/authorizations.json"; chmod 600 "$TMP/state/authorizations.json"
NOW=$((NOW + 1)); set +e; acmesh_auth_prepare issue issueProfile issue-1 "$TMP/material/current" "$TMP/material/summary" >/dev/null; rc=$?; set -e
[ "$rc" = 3 ]; ls "$TMP/state"/authorizations.json.corrupt.* >/dev/null
! grep -R 'authorizations.json' "$ROOT/root/usr/libexec/acmesh-console/lib/config.sh" >/dev/null

# Router identity, acknowledgement and schema mismatches fail closed.
old_instance="$(cat "$TMP/state/instance-id")"; printf '%032d\n' 9 > "$TMP/state/instance-id"; chmod 600 "$TMP/state/instance-id"
acmesh_auth_list | grep -F '"records":[]' >/dev/null
printf '%s\n' "$old_instance" > "$TMP/state/instance-id"; chmod 600 "$TMP/state/instance-id"
sed 's/"ackVersion":1/"ackVersion":99/' "$TMP/state/authorizations.json" > "$TMP/bad"; mv "$TMP/bad" "$TMP/state/authorizations.json"; chmod 600 "$TMP/state/authorizations.json"
acmesh_auth_list | grep -F '"records":[]' >/dev/null
sed 's/"schemaVersion":1/"schemaVersion":99/' "$TMP/state/authorizations.json" > "$TMP/bad"; mv "$TMP/bad" "$TMP/state/authorizations.json"; chmod 600 "$TMP/state/authorizations.json"
acmesh_auth_list | grep -F '"records":[]' >/dev/null

acmesh_auth_revoke_all
echo "test_authorization_ledger: ok"
