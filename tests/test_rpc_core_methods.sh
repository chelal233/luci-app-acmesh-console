#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_TASK_STATE_DIR="$ROOT/tests/.tmp/rpc-core-state"
export ACMESH_TASK_LOG_DIR="$ROOT/tests/.tmp/rpc-core-log"
export ACMESH_REQUEST_DIR="$ROOT/tests/.tmp/rpc-core-requests"
home="$ROOT/tests/.tmp/rpc-core-home"
bin="$ROOT/tests/.tmp/rpc-core-bin"
calls="$ROOT/tests/.tmp/rpc-core-calls"
payloads="$ROOT/tests/.tmp/rpc-core-payloads"
rm -rf "$ACMESH_TASK_STATE_DIR" "$ACMESH_TASK_LOG_DIR" "$ACMESH_REQUEST_DIR" "$home" "$bin" "$calls" "$payloads"
mkdir -p "$home" "$bin/lib" "$ACMESH_REQUEST_DIR" "$payloads"
chmod 700 "$ACMESH_REQUEST_DIR"

cat > "$bin/lib/json.sh" <<SH
. "$ROOT/root/usr/libexec/acmesh-console/lib/json.sh"
SH
cat > "$bin/lib/request.sh" <<'SH'
acmesh_request_consume() {
	id="$1"
	printf '%s\n' "$id" | grep -Eq '^[a-f0-9]{32}$' || return 2
	source="$ACMESH_REQUEST_DIR/$id.json"
	[ -f "$source" ] || return 1
	target="$ACMESH_REQUEST_DIR/.$id.processing.$$"
	mv "$source" "$target" || return 1
	printf '%s\n' "$target"
}
SH
export ACMESH_LIB_DIR="$bin/lib"

cat > "$bin/acmeshctl-wrapper" <<SH
#!/bin/sh
cmd="\$1"
shift
printf '%s %s\n' "\$cmd" "\$*" >> "$calls"
case "\$cmd" in
	core-status)
		printf '{"ok":true,"home":"%s"}\n' "$home"
		;;
	*)
		[ "\${1:-}" = --request-file ] && [ -f "\${2:-}" ] || exit 3
		cat "\$2" > "$payloads/\$cmd.json"
		printf '{"ok":true,"testMode":true,"taskId":"20260712010101-123"}\n'
		;;
esac
SH
chmod +x "$bin/acmeshctl-wrapper"
export ACMESHCTL="$bin/acmeshctl-wrapper"

set +e
status="$(sh "$ROOT/root/usr/libexec/acmesh-console/rpc-read" core_status)"
rc=$?
set -e
[ "$rc" = 0 ] || { echo "rpc core_status command failed"; echo "$status"; exit 1; }
case "$status" in
	*'"ok":true'*'"home":"'"$home"'"'*) ;;
	*) echo "rpc core_status failed"; echo "$status"; exit 1 ;;
esac

set +e
create_request() {
	id="$1"
	payload="$2"
	printf '%s' "$payload" > "$ACMESH_REQUEST_DIR/$id.json"
	chmod 600 "$ACMESH_REQUEST_DIR/$id.json"
}

install_id=11111111111111111111111111111111
create_request "$install_id" '{"tag":"v3.1.4","testMode":true}'
install="$(sh "$ROOT/root/usr/libexec/acmesh-console/rpc-write" core_install --request-id "$install_id")"
rc=$?
set -e
[ "$rc" = 0 ] || { echo "rpc core_install command failed"; echo "$install"; exit 1; }
case "$install" in
	*'"ok":true'*'"testMode":true'*'"taskId"'*) ;;
	*) echo "rpc core_install test mode failed"; echo "$install"; exit 1 ;;
esac
grep -F '"tag":"v3.1.4"' "$payloads/core-install.json" >/dev/null || { echo "rpc core_install did not preserve request payload"; exit 1; }
[ ! -e "$ACMESH_REQUEST_DIR/$install_id.json" ] || { echo "rpc core_install did not consume request"; exit 1; }
! grep -F 'v3.1.4' "$calls" >/dev/null || { echo "rpc core_install leaked payload into argv"; exit 1; }

renew_id=22222222222222222222222222222222
create_request "$renew_id" '{"domain":"rpc-renew.example","keyType":"ecc","testMode":true}'
renew="$(sh "$ROOT/root/usr/libexec/acmesh-console/rpc-write" renew --request-id "$renew_id")"
case "$renew" in
	*'"ok":true'*'"testMode":true'*'"taskId"'*) ;;
	*) echo "rpc renew should preserve request fields"; echo "$renew"; exit 1 ;;
esac
grep -F '"domain":"rpc-renew.example"' "$payloads/renew.json" >/dev/null || { echo "rpc renew did not preserve request payload"; exit 1; }
! grep -F 'rpc-renew.example' "$calls" >/dev/null || { echo "rpc renew leaked payload into argv"; exit 1; }

grep -F 'core-install --request-file ' "$calls" >/dev/null
grep -F 'renew --request-file ' "$calls" >/dev/null

echo "test_rpc_core_methods: ok"
