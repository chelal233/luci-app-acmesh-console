#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
ACL="$ROOT/root/usr/share/rpcd/acl.d/luci-app-acmesh-console.json"
VIEWS="$ROOT/htdocs/luci-static/resources/view/acmesh"
bin="$ROOT/tests/.tmp/rpc-boundaries-bin"
calls="$ROOT/tests/.tmp/rpc-boundaries-calls"

rm -rf "$bin" "$calls"
mkdir -p "$bin"

cat > "$bin/acmeshctl" <<SH
#!/bin/sh
printf '%s\n' "\$*" >> "$calls"
printf '{"ok":true}\n'
SH
chmod +x "$bin/acmeshctl"
export ACMESHCTL="$bin/acmeshctl"

grep -F '"/usr/libexec/acmesh-console/rpc-read": [ "exec" ]' "$ACL" >/dev/null
grep -F '"/usr/libexec/acmesh-console/rpc-write": [ "exec" ]' "$ACL" >/dev/null
! grep -F '"/usr/libexec/acmesh-console/acmeshctl": [ "exec" ]' "$ACL" >/dev/null
! grep -F '"/etc/acme": [ "list", "read" ]' "$ACL" >/dev/null
! grep -R -- '--credential\|--key-pem\|--fullchain-pem\|--json' "$VIEWS" >/dev/null

set +e
read_error="$(sh "$ROOT/root/usr/libexec/acmesh-console/rpc-read" unsupported 2>/dev/null)"
read_rc=$?
write_error="$(sh "$ROOT/root/usr/libexec/acmesh-console/rpc-write" unsupported 2>/dev/null)"
write_rc=$?
set -e

[ "$read_rc" = 2 ] || { echo "rpc-read unsupported should exit 2"; exit 1; }
[ "$write_rc" = 2 ] || { echo "rpc-write unsupported should exit 2"; exit 1; }
printf '%s' "$read_error" | grep -F '"ok":false' >/dev/null
printf '%s' "$read_error" | grep -F 'unsupported method' >/dev/null
printf '%s' "$write_error" | grep -F '"ok":false' >/dev/null
printf '%s' "$write_error" | grep -F 'unsupported method' >/dev/null
[ ! -e "$calls" ] || { echo "unsupported RPC methods invoked acmeshctl"; exit 1; }

set +e
authorization_error="$(ACMESHCTL="$ROOT/root/usr/libexec/acmesh-console/acmeshctl" sh "$ROOT/root/usr/libexec/acmesh-console/rpc-read" authorization_list 2>/dev/null)"
authorization_rc=$?
set -e
[ "$authorization_rc" = 0 ] || { echo "authorization_list should succeed"; echo "$authorization_error"; exit 1; }
printf '%s' "$authorization_error" | grep -F '"ok":true' >/dev/null || { echo "authorization_list did not return structured JSON"; exit 1; }
printf '%s' "$authorization_error" | grep -F '"records":[' >/dev/null || { echo "authorization_list omitted records"; exit 1; }
grep -F 'ACMESH_AUTH_RECOMPUTE_CALLBACK=acmesh_operation_recompute' "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" >/dev/null || { echo "authorization_list omitted recompute callback"; exit 1; }

set +e
consume_error="$(ACMESH_REQUEST_DIR="$ROOT/tests/.tmp/missing-request-inbox" sh "$ROOT/root/usr/libexec/acmesh-console/rpc-write" renew --request-id not-an-id 2>/dev/null)"
consume_rc=$?
set -e
[ "$consume_rc" != 0 ] || { echo "rpc-write invalid request should fail"; exit 1; }
printf '%s' "$consume_error" | grep -F '"ok":false' >/dev/null || { echo "rpc-write swallowed request consume JSON"; exit 1; }
printf '%s' "$consume_error" | grep -F 'request inbox unavailable' >/dev/null || { echo "rpc-write returned wrong consume error"; exit 1; }

echo "test_rpc_boundaries: ok"
