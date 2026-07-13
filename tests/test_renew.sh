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
	*'"ok":true'*'"testMode":true'*'"command"'*'--renew'*"-d 'ecc.example.com'"*'--ecc'*) ;;
	*) echo "renew test should return command preview"; echo "$preview"; exit 1 ;;
esac
case "$preview" in *'"taskId"'*) echo "renew test mode created task"; exit 1;; esac
[ ! -e "$ACMESH_TASK_STATE_DIR" ] && [ ! -e "$ACMESH_TASK_LOG_DIR" ]

arg_log="$ROOT/tests/.tmp/renew-args.log"
rm -f "$arg_log"
. "$ACMESH_LIB_DIR/command.sh"
ACME_SH_ARG_LOG="$arg_log" acmesh_execute_renew "$home" rsa.example.com rsa
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
