#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
. "$ACMESH_LIB_DIR/json.sh"
. "$ROOT/tests/lib/cli_request.sh"

providers="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" providers)"
case "$providers" in
	*'"id":"cloudflare"'*'"dnsApi":"dns_cf"'*'"CF_Token"'*'"CF_Zone_ID"'*'"CF_Account_ID"'*) ;;
	*) echo "provider list missing cloudflare token template"; echo "$providers"; exit 1 ;;
esac
case "$providers" in
	*'"id":"aliyun"'*'"dnsApi":"dns_ali"'*'"Ali_Key"'*'"Ali_Secret"'*) ;;
	*) echo "provider list missing aliyun template"; echo "$providers"; exit 1 ;;
esac

preview="$(acmesh_test_cli_request preview-issue --domain example.com --key-type ec256 --validation-method dns --dns-api dns_cf --credential CF_Token=secret-token --test-mode)"
case "$preview" in
	*"CF_Token='***'"*"--dns 'dns_cf'"*) ;;
	*) echo "credential preview did not mask cloudflare token"; echo "$preview"; exit 1 ;;
esac
case "$preview" in
	*"secret-token"*) echo "credential leaked in preview"; echo "$preview"; exit 1 ;;
esac

echo "test_provider_templates: ok"
