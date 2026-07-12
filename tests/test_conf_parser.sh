#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
. "$ACMESH_LIB_DIR/conf.sh"

out="$(acmesh_parse_kv_file "$ROOT/tests/fixtures/acme-home/example.com_ecc/example.com.conf")"

case "$out" in
	*'"Le_Domain":"example.com"'*) ;;
	*) echo "missing Le_Domain"; echo "$out"; exit 1 ;;
esac

case "$out" in
	*'"Custom_Unknown":"keep-me"'*) ;;
	*) echo "missing unknown variable"; echo "$out"; exit 1 ;;
esac

case "$out" in
	*'"Le_Keylength":"ec-256"'*) ;;
	*) echo "non-secret keylength should be preserved"; echo "$out"; exit 1 ;;
esac

case "$out" in
	*'"CF_Token":"***"'*'"CF_Key":"***"'*'"Baidu_SK":"***"'*) ;;
	*) echo "DNS credentials should be masked"; echo "$out"; exit 1 ;;
esac

case "$out" in
	*"secret-token-value"*|*"secret-global-key"*|*"secret-baidu-sk"*) echo "DNS credential value leaked"; echo "$out"; exit 1 ;;
esac

echo "test_conf_parser: ok"
