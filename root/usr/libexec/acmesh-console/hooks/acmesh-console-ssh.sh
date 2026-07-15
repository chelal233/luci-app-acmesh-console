#!/bin/sh
set -eu

ACMESH_LIB_DIR="${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}"
export ACMESH_LIB_DIR
. "$ACMESH_LIB_DIR/cert.sh"
. "$ACMESH_LIB_DIR/task.sh"
. "$ACMESH_LIB_DIR/command.sh"
. "$ACMESH_LIB_DIR/dns.sh"
. "$ACMESH_LIB_DIR/provider.sh"
. "$ACMESH_LIB_DIR/deploy.sh"
. "$ACMESH_LIB_DIR/ssh.sh"
. "$ACMESH_LIB_DIR/config.sh"
. "$ACMESH_LIB_DIR/request_payload.sh"
. "$ACMESH_LIB_DIR/authorization.sh"
. "$ACMESH_LIB_DIR/operation.sh"

profile_id="${ACMESH_DEPLOY_PROFILE_ID:-}"
[ -n "$profile_id" ] || profile_id="$(acmesh_profile_find_linked_deploy "${Le_Domain:-}" "${Le_Keylength:-}")" || {
	echo "unable to resolve linked deploy profile" >&2; exit 1;
}
acmesh_profile_validate_id "$profile_id" || { echo "invalid deploy profile id" >&2; exit 2; }
if ! acmesh_operation_is_remembered deploy-run deployProfile "$profile_id"; then
	printf 'authorization required for deploy profile %s\n' "$profile_id" >&2
	exit 1
fi
if ! output="$(ACMESH_OPERATION_REQUIRE_REMEMBERED=1 acmesh_operation_start deploy-run deployProfile "$profile_id" '')"; then
	printf 'authorized deploy failed for profile %s\n' "$profile_id" >&2
	exit 1
fi
printf '%s\n' "$output"
task_id="$(printf '%s\n' "$output" | jsonfilter -e '@.taskId')"
acmesh_task_validate_id "$task_id" || { echo "authorized deploy did not return a task" >&2; exit 1; }
elapsed=0
while [ "$elapsed" -lt 900 ]; do
	state="$ACMESH_TASK_STATE_DIR/$task_id.json"
	status="$(jsonfilter -i "$state" -e '@.status' 2>/dev/null || true)"
	case "$status" in
		success) exit 0 ;;
		failed|interrupted) echo "linked deploy task $task_id ended with $status" >&2; exit 1 ;;
	esac
	sleep 1; elapsed=$((elapsed + 1))
done
echo "linked deploy task $task_id timed out" >&2
exit 124
