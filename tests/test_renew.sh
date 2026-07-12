#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
export ACMESH_TASK_STATE_DIR="$ROOT/tests/.tmp/renew-state"
export ACMESH_TASK_LOG_DIR="$ROOT/tests/.tmp/renew-log"
rm -rf "$ACMESH_TASK_STATE_DIR" "$ACMESH_TASK_LOG_DIR"

home="$ROOT/tests/.tmp/renew-home"
rm -rf "$home"
mkdir -p "$home"
cat > "$home/acme.sh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$ACME_SH_ARG_LOG"
EOF
chmod +x "$home/acme.sh"

preview="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" renew --home "$home" --domain ecc.example.com --key-type ecc --test-mode)"
case "$preview" in
	*'"ok":true'*'"testMode":true'*'"taskId"'*) ;;
	*) echo "renew test should create test-mode task"; echo "$preview"; exit 1 ;;
esac
preview_id="$(printf '%s' "$preview" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
sleep 1
preview_status="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-status --task-id "$preview_id")"
preview_log="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-log --task-id "$preview_id")"
case "$preview_status" in
	*'"operation":"renew-test"'*'"status":"success"'*) ;;
	*) echo "renew test task status is wrong"; echo "$preview_status"; echo "$preview_log"; exit 1 ;;
esac
case "$preview_log" in
	*"TEST MODE"*"--renew"*"-d 'ecc.example.com'"*"--ecc"*) ;;
	*) echo "renew test log should show acme.sh renew command"; echo "$preview_log"; exit 1 ;;
esac
case "$preview_log" in
	*"renew skeleton"*) echo "renew test must not use skeleton log"; echo "$preview_log"; exit 1 ;;
esac

arg_log="$ROOT/tests/.tmp/renew-args.log"
rm -f "$arg_log"
ACME_SH_ARG_LOG="$arg_log" sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" renew --home "$home" --domain rsa.example.com --key-type rsa --real-mode >/tmp/acmesh-renew-real.out
real="$(cat /tmp/acmesh-renew-real.out)"
case "$real" in
	*'"ok":true'*'"taskId"'*) ;;
	*) echo "renew real should create task"; echo "$real"; exit 1 ;;
esac
real_id="$(printf '%s' "$real" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
sleep 1
real_status="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-status --task-id "$real_id")"
real_log="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-log --task-id "$real_id")"
case "$real_status" in
	*'"operation":"renew"'*'"status":"success"'*) ;;
	*) echo "renew real task status is wrong"; echo "$real_status"; echo "$real_log"; exit 1 ;;
esac
case "$(cat "$arg_log")" in
	*"--home $home --renew -d rsa.example.com"*) ;;
	*) echo "renew real did not call acme.sh --renew"; cat "$arg_log"; exit 1 ;;
esac
case "$(cat "$arg_log")" in
	*"--ecc"*) echo "rsa renew should not pass --ecc"; cat "$arg_log"; exit 1 ;;
esac

missing="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" renew --home "$home" --real-mode 2>/dev/null || true)"
case "$missing" in
	*'"ok":false'*"domain is required"*) ;;
	*) echo "renew real should require domain"; echo "$missing"; exit 1 ;;
esac

echo "test_renew: ok"
