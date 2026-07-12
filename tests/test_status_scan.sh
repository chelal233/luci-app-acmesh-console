#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"

out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" status --home "$ROOT/tests/fixtures/acme-home")"

case "$out" in
	*'"mainDomain":"example.com"'*) ;;
	*) echo "missing example.com"; echo "$out"; exit 1 ;;
esac

case "$out" in
	*'"keyType":"ecc"'*'"keyType":"rsa"'*|*'"keyType":"rsa"'*'"keyType":"ecc"'*) ;;
	*) echo "missing ecc/rsa variants"; echo "$out"; exit 1 ;;
esac

case "$out" in
	*'"Custom_Unknown":"keep-me"'*) ;;
	*) echo "unknown variable was not preserved"; echo "$out"; exit 1 ;;
esac

case "$out" in
	*'"Le_Keylength":"ec-256"'*) ;;
	*) echo "keylength was not preserved"; echo "$out"; exit 1 ;;
esac

case "$out" in
	*'"CF_Token":"***"'*'"CF_Key":"***"'*) ;;
	*) echo "secret DNS variables were not masked"; echo "$out"; exit 1 ;;
esac

case "$out" in
	*"secret-token-value"*|*"secret-global-key"*) echo "secret DNS variable leaked"; echo "$out"; exit 1 ;;
esac

echo "test_status_scan: ok"
