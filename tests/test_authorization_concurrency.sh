#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
command -v jsonfilter >/dev/null 2>&1 || { echo "test_authorization_concurrency: SKIP (jsonfilter unavailable)"; exit 0; }
TMP="${TMPDIR:-/tmp}/acmesh-auth-concurrency.$$"; trap 'rm -rf "$TMP"' 0 HUP INT TERM
mkdir -p "$TMP/state" "$TMP/challenges" "$TMP/material"; chmod 700 "$TMP" "$TMP/state" "$TMP/challenges" "$TMP/material"
. "$ROOT/tests/lib/host_flock.sh"; acmesh_test_install_flock_shim "$TMP/flock"; acmesh_test_install_private_ls_shim "$TMP/private-ls" "$TMP"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib" ACMESH_AUTH_STATE_DIR="$TMP/state" ACMESH_AUTH_INSTANCE_FILE="$TMP/state/instance-id" ACMESH_AUTH_LEDGER_FILE="$TMP/state/authorizations.json" ACMESH_AUTH_LOCK_FILE="$TMP/state/authorization.lock" ACMESH_AUTH_CHALLENGE_DIR="$TMP/challenges"
. "$ROOT/root/usr/libexec/acmesh-console/lib/authorization.sh"
ACMESH_AUTH_ACME_HOME=/etc/acme ACMESH_AUTH_CORE_TAG=3.2.0 acmesh_auth_snapshot core-upgrade core acme.sh "$TMP/material/current"
printf '{}\n' > "$TMP/material/summary"; chmod 600 "$TMP/material/summary"
recompute() { cp "$TMP/material/current" "$4"; cp "$TMP/material/summary" "$5"; chmod 600 "$4" "$5"; }
admit() { (umask 077; printf '%s\n' "$4" >> "$TMP/admissions"); }
export ACMESH_AUTH_RECOMPUTE_CALLBACK=recompute ACMESH_AUTH_ADMIT_CALLBACK=admit
set +e; out="$(acmesh_auth_prepare core-upgrade core acme.sh "$TMP/material/current" "$TMP/material/summary")"; rc=$?; set -e
[ "$rc" = 3 ]; id="$(printf '%s' "$out" | jsonfilter -e '@.challengeId')"
for n in 1 2 3 4 5 6 7 8 9 10; do (acmesh_auth_execute "$id" once > "$TMP/out.$n" 2>/dev/null && printf ok > "$TMP/ok.$n") & done
wait
[ "$(find "$TMP" -name 'ok.*' | wc -l | tr -d ' ')" = 1 ]
[ "$(wc -l < "$TMP/admissions" | tr -d ' ')" = 1 ]

# Cancellation after consumption must clean up and never continue to admission.
set +e; out="$(acmesh_auth_prepare core-upgrade core acme.sh "$TMP/material/current" "$TMP/material/summary")"; rc=$?; set -e
[ "$rc" = 3 ]; cancel_id="$(printf '%s' "$out" | jsonfilter -e '@.challengeId')"
slow_recompute() {
	: > "$TMP/recompute-started"
	while [ ! -e "$TMP/recompute-release" ]; do sleep 1; done
	recompute "$@"
}
export ACMESH_AUTH_RECOMPUTE_CALLBACK=slow_recompute
before="$(wc -l < "$TMP/admissions" | tr -d ' ')"
(acmesh_auth_execute "$cancel_id" once > "$TMP/cancel.out" 2>&1) & cancel_pid=$!
attempt=0; while [ ! -e "$TMP/recompute-started" ]; do attempt=$((attempt + 1)); [ "$attempt" -lt 10 ] || { echo "cancel test did not reach recompute"; exit 1; }; sleep 1; done
kill -TERM "$cancel_pid"
set +e; wait "$cancel_pid"; cancel_rc=$?; set -e
[ "$cancel_rc" -ne 0 ] || { echo "cancelled authorization returned success"; exit 1; }
[ "$(wc -l < "$TMP/admissions" | tr -d ' ')" = "$before" ] || { echo "cancelled authorization was admitted"; exit 1; }
[ ! -e "$TMP/challenges/$cancel_id.json.consuming" ] || { echo "cancelled challenge left consuming state"; exit 1; }
export ACMESH_AUTH_RECOMPUTE_CALLBACK=recompute
start="$(date +%s)"
set +e; retry="$(acmesh_auth_prepare core-upgrade core acme.sh "$TMP/material/current" "$TMP/material/summary")"; retry_rc=$?; set -e
[ "$retry_rc" = 3 ] || { echo "authorization lock remained held after TERM"; exit 1; }
[ $(( $(date +%s) - start )) -lt 3 ] || { echo "authorization lock acquisition was delayed after TERM"; exit 1; }

# A long-lived task forked by admission must not inherit an effective lock.
background_admit() {
	(sleep 5 >/dev/null 2>&1) &
	printf '%s\n' "$!" > "$TMP/background-pid"
	printf '%s\n' "$4" >> "$TMP/admissions"
}
export ACMESH_AUTH_ADMIT_CALLBACK=background_admit
retry_id="$(printf '%s' "$retry" | jsonfilter -e '@.challengeId')"
acmesh_auth_execute "$retry_id" once >/dev/null
start="$(date +%s)"
set +e; after_background="$(acmesh_auth_prepare core-upgrade core acme.sh "$TMP/material/current" "$TMP/material/summary")"; after_rc=$?; set -e
[ "$after_rc" = 3 ] || { echo "background admission retained authorization lock"; exit 1; }
[ $(( $(date +%s) - start )) -lt 3 ] || { echo "background admission delayed lock acquisition"; exit 1; }
[ -s "$TMP/background-pid" ] && kill "$(cat "$TMP/background-pid")" 2>/dev/null || true
echo "test_authorization_concurrency: ok"
