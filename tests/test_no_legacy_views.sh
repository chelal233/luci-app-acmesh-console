#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MENU="$ROOT/root/usr/share/luci/menu.d/luci-app-acmesh-console.json"
CLEANUP="$ROOT/root/etc/uci-defaults/99-acmesh-console-cleanup"

[ ! -e "$ROOT/htdocs/luci-static/resources/view/acmesh/operations.js" ] || {
	echo "deprecated operations.js must not be packaged"
	exit 1
}
grep -F '"path": "acmesh/operations_v2"' "$MENU" >/dev/null
grep -F '/www/luci-static/resources/view/acmesh/operations.js' "$CLEANUP" >/dev/null
echo "test_no_legacy_views: ok"
