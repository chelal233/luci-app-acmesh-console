#!/bin/sh
set -eu

ACMESH_LIB_DIR="${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}"
export ACMESH_LIB_DIR
. "$ACMESH_LIB_DIR/deploy.sh"

acmesh_execute_profile_deploy_locked "$@"
