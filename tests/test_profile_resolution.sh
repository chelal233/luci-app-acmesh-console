#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
export ACMESH_CONSOLE_CONFIG="$ROOT/tests/.tmp/profile-resolution/config.json"
export ACMESH_TASK_WORKSPACE_DIR="$ROOT/tests/.tmp/profile-resolution/work"
export ACMESH_DEPLOY_LOCK_DIR="$ROOT/tests/.tmp/profile-resolution/deploy-locks"
. "$ACMESH_LIB_DIR/io.sh"
. "$ACMESH_LIB_DIR/config.sh"
. "$ACMESH_LIB_DIR/profile.sh"

rm -rf "${ACMESH_CONSOLE_CONFIG%/*}"
mkdir -p "${ACMESH_CONSOLE_CONFIG%/*}"
chmod 700 "${ACMESH_CONSOLE_CONFIG%/*}"
cat > "$ACMESH_CONSOLE_CONFIG" <<JSON
{"schemaVersion":2,"global":{"defaultAccountEmail":"default@example.org","testMode":false,"coreTag":"v3.1.4","acmeHome":"/etc/acme"},"accountProfiles":[{"id":"acc","name":"LE","ca":"letsencrypt_staging","accountEmail":"overlay@example.org"}],"issueProfiles":[{"id":"issue","name":"Example","domain":"example.org","domains":["example.org","www.example.org"],"accountProfileId":"acc","deployProfileId":"deploy","keyType":"ec256","validationMethod":"dns","testModeOverride":"force-test-mode","dnsApi":"dns_cf","credentialMode":"token","credentials":{"CF_Token":"top-secret"},"challengeAlias":"alias.example.net","dnsSleep":42}],"deployProfiles":[{"id":"deploy","name":"nginx","type":"ssh","certSource":"managed-acme","domain":"example.org","keyType":"ec256","host":"192.0.2.10","user":"root","port":"22","sshKey":"/root/.ssh/id_ed25519","keyFile":"/etc/ssl/example.key","fullchainFile":"/etc/ssl/example.pem","reloadcmd":"service nginx reload","sudoMode":"always","owner":"root","group":"ssl-cert","mode":"0640"},{"id":"local-deploy","name":"local","type":"local","certSource":"paste-pem","keyPem":"profile-private-key","fullchainPem":"profile-fullchain","keyFile":"$ROOT/tests/.tmp/profile-resolution/deployed.key","fullchainFile":"$ROOT/tests/.tmp/profile-resolution/deployed.fullchain","owner":"root","group":"root","mode":"0640"}]}
JSON
chmod 600 "$ACMESH_CONSOLE_CONFIG"

issue="$ROOT/tests/.tmp/profile-resolution/issue.json"
stdout="$ROOT/tests/.tmp/profile-resolution/stdout"
acmesh_profile_resolve_issue issue "$issue" > "$stdout"
[ ! -s "$stdout" ] || { echo "resolver leaked output"; exit 1; }
[ "$(jsonfilter -i "$issue" -e '@.accountEmail')" = overlay@example.org ]
[ "$(jsonfilter -i "$issue" -e '@.ca')" = letsencrypt_staging ]
[ "$(jsonfilter -i "$issue" -e '@.testMode')" = true ]
[ "$(jsonfilter -i "$issue" -e '@.credentials.CF_Token')" = top-secret ]
[ "$(jsonfilter -i "$issue" -e '@.domains[1]')" = www.example.org ]
[ "$(jsonfilter -i "$issue" -e '@.challengeAlias')" = alias.example.net ]
[ "$(jsonfilter -i "$issue" -e '@.dnsSleep')" = 42 ]
[ "$(LC_ALL=C ls -ld "$issue" | awk '{print $1}')" = -rw------- ]

deploy="$ROOT/tests/.tmp/profile-resolution/deploy.json"
acmesh_profile_resolve_deploy deploy "$deploy" > "$stdout"
[ ! -s "$stdout" ] || { echo "deploy resolver leaked output"; exit 1; }
[ "$(jsonfilter -i "$deploy" -e '@.id')" = deploy ]
[ "$(jsonfilter -i "$deploy" -e '@.target.host')" = 192.0.2.10 ]
[ "$(jsonfilter -i "$deploy" -e '@.destinations.keyFile')" = /etc/ssl/example.key ]
[ "$(jsonfilter -i "$deploy" -e '@.target.sudoMode')" = always ]
[ "$(jsonfilter -i "$deploy" -e '@.destinations.owner')" = root ]
[ "$(jsonfilter -i "$deploy" -e '@.destinations.group')" = ssl-cert ]
[ "$(jsonfilter -i "$deploy" -e '@.destinations.mode')" = 0640 ]

acmesh_profile_resolve_issue missing "$issue" >/dev/null 2>&1 && { echo "missing profile accepted"; exit 1; } || :
acmesh_profile_resolve_issue '../issue' "$issue" >/dev/null 2>&1 && { echo "unsafe id accepted"; exit 1; } || :

export ACMESH_TASK_STATE_DIR="$ROOT/tests/.tmp/profile-resolution/state"
export ACMESH_TASK_LOG_DIR="$ROOT/tests/.tmp/profile-resolution/log"
request="$ROOT/tests/.tmp/profile-resolution/issue-request.json"
printf '%s\n' '{"profileId":"issue"}' > "$request"
chmod 600 "$request"
run_out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" issue --request-file "$request")"
case "$run_out" in *'"taskId"'*) ;; *) echo "issue did not accept profile id"; exit 1;; esac
case "$run_out" in *'"testMode":true'*) ;; *) echo "issue profile test mode was not preserved"; exit 1;; esac
case "$run_out" in *top-secret*) echo "issue response leaked credentials"; exit 1;; esac
task_id="$(printf '%s' "$run_out" | jsonfilter -e '@.taskId')"
sleep 1
run_log="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-log --task-id "$task_id")"
case "$run_log" in *"--dns 'dns_cf'"*"-d 'example.org'"*"-d 'www.example.org'"*"--challenge-alias 'alias.example.net'"*"--dnssleep '42'"*) ;; *) echo "issue worker did not consume complete current profile"; echo "$run_log"; exit 1;; esac
case "$run_log" in *top-secret*) echo "issue task log leaked credentials"; exit 1;; esac
[ ! -e "$ACMESH_TASK_WORKSPACE_DIR/$task_id/issue-profile.json" ] || { echo "resolved issue profile was retained"; exit 1; }

deploy_request="$ROOT/tests/.tmp/profile-resolution/deploy-request.json"
printf '%s\n' '{"profileId":"local-deploy"}' > "$deploy_request"
deploy_out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" deploy-run --request-file "$deploy_request")"
case "$deploy_out" in *'"taskId"'*) ;; *) echo "deploy did not accept profile id"; echo "$deploy_out"; exit 1;; esac
case "$deploy_out" in *profile-private-key*) echo "deploy response leaked private material"; exit 1;; esac
deploy_task_id="$(printf '%s' "$deploy_out" | jsonfilter -e '@.taskId')"
sleep 1
deploy_status="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-status --task-id "$deploy_task_id")"
case "$deploy_status" in *'"status":"success"'*) ;; *) echo "deploy profile task failed"; echo "$deploy_status"; exit 1;; esac
grep -q '^profile-private-key$' "$ROOT/tests/.tmp/profile-resolution/deployed.key" || { echo "deploy profile did not use resolved private key"; exit 1; }
grep -q '^profile-fullchain$' "$ROOT/tests/.tmp/profile-resolution/deployed.fullchain" || { echo "deploy profile did not use resolved fullchain"; exit 1; }
[ ! -e "$ACMESH_TASK_WORKSPACE_DIR/$deploy_task_id/deploy-profile.json" ] || { echo "resolved deploy profile was retained"; exit 1; }
if [ "$(id -u)" = 0 ]; then
	set -- $(LC_ALL=C ls -ld "$ROOT/tests/.tmp/profile-resolution/deployed.key")
	[ "$3:$4" = root:root ] || { echo "deploy profile did not apply owner/group"; exit 1; }
	[ "$1" = -rw------- ] || { echo "deploy profile did not enforce private key mode"; exit 1; }
	set -- $(LC_ALL=C ls -ld "$ROOT/tests/.tmp/profile-resolution/deployed.fullchain")
	[ "$3:$4" = root:root ] || { echo "deploy profile did not apply fullchain owner/group"; exit 1; }
	[ "$1" = -rw-r----- ] || { echo "deploy profile did not apply fullchain mode"; exit 1; }
fi

echo "test_profile_resolution: ok"
