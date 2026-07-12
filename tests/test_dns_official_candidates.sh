#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OPS="$ROOT/htdocs/luci-static/resources/view/acmesh/operations_v2.js"

count="$(sed -n '/OFFICIAL_DNS_API_CANDIDATES = \[/,/\];/p' "$OPS" | grep -o "'dns_[A-Za-z0-9_]*'" | sort -u | wc -l | tr -d ' ')"
if [ "$count" -lt 180 ]; then
	echo "official DNS API candidates look incomplete: $count"
	exit 1
fi

for item in dns_1984hosting dns_acmedns dns_azure dns_cf dns_dp dns_huaweicloud dns_namecheap dns_porkbun dns_tencent dns_volcengine dns_zonomi; do
	if ! sed -n '/OFFICIAL_DNS_API_CANDIDATES = \[/,/\];/p' "$OPS" | grep -Fq "'$item'"; then
		echo "missing official DNS API candidate: $item"
		exit 1
	fi
done

echo "test_dns_official_candidates: ok"
