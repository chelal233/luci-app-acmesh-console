#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OPS="$ROOT/htdocs/luci-static/resources/view/acmesh/operations_v2.js"
CMD="$ROOT/root/usr/libexec/acmesh-console/lib/command.sh"

if grep -Fq "Cloudflare Zone ID / Account ID" "$OPS"; then
	echo "cloudflare token mode should not require zone/account id"
	exit 1
fi

for needle in "ignoredValue" "CF_Zone_ID" "CF_Account_ID"; do
	if ! grep -Fq "$needle" "$OPS"; then
		echo "operations page missing: $needle"
		exit 1
	fi
done

for needle in "acmesh_sanitize_credentials" "CF_Zone_ID=" "CF_Account_ID=none"; do
	if ! grep -Fq "$needle" "$CMD"; then
		echo "command layer missing sanitizer: $needle"
		exit 1
	fi
done

if grep -Fq "value === '0'" "$OPS" || grep -Fq "CF_Zone_ID=0" "$CMD"; then
	echo "zero must remain an explicit user value, not an ignored placeholder"
	exit 1
fi

echo "test_cloudflare_optional_ids: ok"
