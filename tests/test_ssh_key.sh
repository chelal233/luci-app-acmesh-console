#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
export ACMESH_SSH_DIR="$ROOT/tests/.tmp/ssh"
rm -rf "$ACMESH_SSH_DIR"

if ! command -v ssh-keygen >/dev/null 2>&1; then
	echo "test_ssh_key: skipped (ssh-keygen missing)"
	exit 0
fi

out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" ssh-key ensure)"
case "$out" in
	*'"ok":true'*'"publicKey":"ssh-'*) ;;
	*) echo "ssh key ensure did not return public key"; echo "$out"; exit 1 ;;
esac

[ -f "$ACMESH_SSH_DIR/id_ed25519" ]
[ -f "$ACMESH_SSH_DIR/id_ed25519.pub" ]

echo "test_ssh_key: ok"
