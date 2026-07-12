#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
export ACMESH_TASK_STATE_DIR="$ROOT/tests/.tmp/core-upgrade-state"
export ACMESH_TASK_LOG_DIR="$ROOT/tests/.tmp/core-upgrade-log"
home="$ROOT/tests/.tmp/core-upgrade-home"
rm -rf "$ACMESH_TASK_STATE_DIR" "$ACMESH_TASK_LOG_DIR" "$home"
mkdir -p "$home"

cat > "$home/acme.sh" <<'SH'
#!/bin/sh
case "$1" in
	--version) echo "https://github.com/acmesh-official/acme.sh v9.9.9-test" ;;
	--home)
		shift 2
		case "$1" in
			--upgrade) echo "fake upgrade ok" ;;
			*) echo "fake acme $*" ;;
		esac
		;;
	*) echo "fake acme $*" ;;
esac
SH
chmod +x "$home/acme.sh"

set +e
out="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" core-upgrade --home "$home" --test-mode)"
rc=$?
set -e
[ "$rc" = 0 ] || { echo "core-upgrade command failed"; echo "$out"; exit 1; }
case "$out" in
	*'"ok":true'*'"testMode":true'*'"taskId"'*) ;;
	*) echo "core upgrade test mode did not create test task"; echo "$out"; exit 1 ;;
esac

task_id="$(printf '%s' "$out" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
sleep 1
status="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-status --task-id "$task_id")"
log="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" task-log --task-id "$task_id")"

case "$status" in
	*'"status":"success"'*) ;;
	*) echo "core upgrade test task should succeed"; echo "$status"; echo "$log"; exit 1 ;;
esac
case "$status" in
	*'"operation":"core-upgrade-test"'*) ;;
	*) echo "core upgrade test task has wrong operation"; echo "$status"; exit 1 ;;
esac
case "$log" in
	*"TEST MODE"*"v9.9.9-test"*"https://github.com/acmesh-official/acme.sh/archive/refs/tags/v3.1.4.tar.gz"*) ;;
	*) echo "core upgrade test log is wrong"; echo "$log"; exit 1 ;;
esac
case "$log" in
	*" --upgrade"*|*"master.tar.gz"*)
		echo "core upgrade should use explicit tag archive"
		echo "$log"
		exit 1
		;;
esac

echo "test_core_upgrade_mode: ok"
