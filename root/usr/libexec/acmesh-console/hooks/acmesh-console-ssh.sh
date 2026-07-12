#!/bin/sh
set -eu

ACMESH_LIB_DIR="${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}"
export ACMESH_LIB_DIR
. "$ACMESH_LIB_DIR/deploy.sh"

host="${ACMESH_DEPLOY_HOST:?missing host}"
port="${ACMESH_DEPLOY_PORT:-22}"
user="${ACMESH_DEPLOY_USER:-root}"
ssh_key="${ACMESH_DEPLOY_KEY:?missing key}"
remote_fullchain="${ACMESH_DEPLOY_FULLCHAIN:?missing fullchain path}"
remote_key="${ACMESH_DEPLOY_KEYFILE:?missing key path}"
reloadcmd="${ACMESH_DEPLOY_RELOADCMD:-}"
fullchain="${_cfullchain:-${Le_Fullchain:-}}"
keyfile="${_ckey:-${Le_KeyPath:-}}"

[ -f "$fullchain" ] || { echo "fullchain file not found" >&2; exit 1; }
[ -f "$keyfile" ] || { echo "key file not found" >&2; exit 1; }
acmesh_ssh_validate_target "$host" "$port" "$user" || { echo "invalid SSH target" >&2; exit 2; }
acmesh_ssh_validate_remote_path "$remote_key" || { echo "invalid remote key path" >&2; exit 2; }
acmesh_ssh_validate_remote_path "$remote_fullchain" || { echo "invalid remote fullchain path" >&2; exit 2; }

ACMESH_CURRENT_TASK_ID="$(date -u +%Y%m%d%H%M%S)-$$"
export ACMESH_CURRENT_TASK_ID
acmesh_execute_profile_deploy ssh local-files "${Le_Domain:-hook}" \
	"$remote_key" "$remote_fullchain" '' '' "$reloadcmd" \
	"$keyfile" "$fullchain" '' '' "$host" "$port" "$user" "$ssh_key" "${Le_Keylength:-ecc}"
