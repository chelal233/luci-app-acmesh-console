#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
TEST_ROOT="$ROOT/tests/.tmp/deploy-transaction"
export ACMESH_TASK_WORKSPACE_DIR="$TEST_ROOT/workspaces"
export ACMESH_DEPLOY_LOCK_DIR="$TEST_ROOT/locks"
rm -rf "$TEST_ROOT"
mkdir -p "$TEST_ROOT" "$ACMESH_TASK_WORKSPACE_DIR"
mkdir -p "$ACMESH_DEPLOY_LOCK_DIR"
chmod 700 "$TEST_ROOT" "$ACMESH_TASK_WORKSPACE_DIR" "$ACMESH_DEPLOY_LOCK_DIR"
. "$ROOT/tests/lib/host_flock.sh"
acmesh_test_install_flock_shim "$TEST_ROOT/flock"
acmesh_test_install_private_ls_shim "$TEST_ROOT/private-ls" "$TEST_ROOT"
. "$ACMESH_LIB_DIR/io.sh"
. "$ACMESH_LIB_DIR/deploy.sh"

write_pair() {
	dir="$1" prefix="$2"
	mkdir -p "$dir"
	printf '%s-key\n' "$prefix" > "$dir/key.pem"
	printf '%s-chain\n' "$prefix" > "$dir/fullchain.pem"
}

assert_pair() {
	dir="$1" prefix="$2"
	[ "$(cat "$dir/key.pem")" = "$prefix-key" ] || { echo "key is not from $prefix pair"; exit 1; }
	[ "$(cat "$dir/fullchain.pem")" = "$prefix-chain" ] || { echo "fullchain is not from $prefix pair"; exit 1; }
}

source_dir="$TEST_ROOT/source"
target_dir="$TEST_ROOT/target"
write_pair "$source_dir" new
write_pair "$target_dir" old

root_target_status=0
acmesh_deploy_canonical_target /../../ >/dev/null 2>&1 || root_target_status=$?
[ "$root_target_status" = 73 ] || { echo "canonical root target should return 73, got $root_target_status"; exit 1; }
control_target="$(printf '/tmp/control\tpath')"
control_status=0
acmesh_deploy_lexical_absolute_target "$control_target" >/dev/null || control_status=$?
[ "$control_status" = 73 ] || { echo "control character target should return 73, got $control_status"; exit 1; }

local_same_target="$TEST_ROOT/local-same-target.pem"
local_same_stage_log="$TEST_ROOT/local-same-target-stages"
local_same_error="$TEST_ROOT/local-same-target-error"
printf '%s\n' local-original > "$local_same_target"
ACMESH_CURRENT_TASK_ID=20260101010109-800
ACMESH_DEPLOY_STAGE_LOG="$local_same_stage_log"
export ACMESH_CURRENT_TASK_ID ACMESH_DEPLOY_STAGE_LOG
local_same_status=0
acmesh_deploy_transaction "$source_dir/key.pem" "$source_dir/fullchain.pem" \
	"$local_same_target" "$local_same_target" ':' '' '' '' 2> "$local_same_error" || local_same_status=$?
[ "$local_same_status" = 74 ] || { echo "local same target should return 74, got $local_same_status"; exit 1; }
grep -q 'key and fullchain targets must be different' "$local_same_error" || { echo "local same target failure was not explicit"; cat "$local_same_error"; exit 1; }
[ "$(cat "$local_same_target")" = local-original ] || { echo "local same target changed the original file"; exit 1; }
[ ! -e "$local_same_stage_log" ] || { echo "local same target reached a deployment stage"; cat "$local_same_stage_log"; exit 1; }
if find "$TEST_ROOT" -name 'local-same-target.pem.acmesh-*' | grep . >/dev/null; then echo "local same target created transaction artifacts"; exit 1; fi
unset ACMESH_DEPLOY_STAGE_LOG

run_profile_collision_preflight() (
	deploy_type="$1" case_name="$2"
	case_root="$TEST_ROOT/profile-collision-$deploy_type-$case_name"
	mkdir -p "$case_root/a" "$case_root/b" "$case_root/real"
	case "$case_name" in
		exact) key_target="$case_root/shared.pem"; cert_target="$case_root/shared.pem" ;;
		alias) key_target="$case_root/a/../b/shared.pem"; cert_target="$case_root/b/shared.pem" ;;
		symlink-missing-exact) ln -s real "$case_root/link"; key_target="$case_root/link/missing/shared.pem"; cert_target="$case_root/real/missing/shared.pem" ;;
		symlink-missing-alias) ln -s real "$case_root/link"; key_target="$case_root/link/missing/../shared.pem"; cert_target="$case_root/real/shared.pem" ;;
		root-key) key_target=/../../; cert_target="$case_root/cert.pem" ;;
		root-cert) key_target="$case_root/key.pem"; cert_target=/./../ ;;
	esac
	case "$case_name" in
		symlink-*) [ -L "$case_root/link" ] || { printf '%s\n' "test_deploy_transaction: SKIP $case_name (host lacks POSIX directory symlinks)" >&2; return 0; } ;;
	esac
	lock_marker="$case_root/lock-called"
	guard_marker="$case_root/guard-called"
	upload_marker="$case_root/upload-called"
	acmesh_deploy_ssh_copy() { : > "$upload_marker"; return 92; }
	acmesh_execute_profile_deploy_guarded() { : > "$guard_marker"; acmesh_deploy_ssh_copy || true; return 92; }
	acmesh_lock_run() { : > "$lock_marker"; shift; "$@"; }
	ACMESH_CURRENT_TASK_ID=20260101010108-799
	export ACMESH_CURRENT_TASK_ID
	profile_status=0
	acmesh_execute_profile_deploy "$deploy_type" local-files same-target.example \
		"$key_target" "$cert_target" '' '' ':' \
		"$source_dir/key.pem" "$source_dir/fullchain.pem" '' '' 192.0.2.90 22 root root-key ecc 2> "$case_root/error" || profile_status=$?
	case "$case_name" in root-*) expected_status=73;; *) expected_status=74;; esac
	[ "$profile_status" = "$expected_status" ] || { echo "$deploy_type $case_name preflight should return $expected_status before locking, got $profile_status"; exit 1; }
	if [ "$expected_status" = 74 ]; then
		grep -q 'key and fullchain targets must be different' "$case_root/error" || { echo "$deploy_type $case_name collision was not explicit"; cat "$case_root/error"; exit 1; }
	fi
	for marker in "$lock_marker" "$guard_marker" "$upload_marker"; do
		[ ! -e "$marker" ] || { echo "$deploy_type $case_name collision crossed preflight: $marker"; exit 1; }
	done
)

for case_name in exact alias symlink-missing-exact symlink-missing-alias root-key root-cert; do
	run_profile_collision_preflight local "$case_name"
done
for case_name in exact alias root-key root-cert; do
	run_profile_collision_preflight ssh "$case_name"
done

run_ssh_local_symlink_independence() (
	case_root="$TEST_ROOT/profile-ssh-local-symlink-independence"
	mkdir -p "$case_root/real"
	ln -s real "$case_root/link"
	[ -L "$case_root/link" ] || { printf '%s\n' "test_deploy_transaction: SKIP SSH local-symlink independence (host lacks POSIX directory symlinks)" >&2; return 0; }
	key_target="$case_root/link/shared.pem"
	cert_target="$case_root/real/shared.pem"
	guard_marker="$case_root/guard-called"
	acmesh_lock_run() { shift; "$@"; }
	acmesh_execute_profile_deploy_guarded() { : > "$guard_marker"; return 92; }
	ACMESH_CURRENT_TASK_ID=20260101010108-799
	export ACMESH_CURRENT_TASK_ID
	status=0
	acmesh_execute_profile_deploy ssh local-files remote-layout.example \
		"$key_target" "$cert_target" '' '' ':' \
		"$source_dir/key.pem" "$source_dir/fullchain.pem" '' '' 192.0.2.90 22 root root-key ecc \
		>/dev/null 2>&1 || status=$?
	[ "$status" = 92 ] || { echo "SSH preflight used the router's local symlink layout, got $status"; exit 1; }
	[ -e "$guard_marker" ] || { echo "SSH deployment did not pass lexical preflight"; exit 1; }
)
run_ssh_local_symlink_independence

new_parent_root="$TEST_ROOT/new-parent-deploy"
rm -rf "$new_parent_root"
ACMESH_CURRENT_TASK_ID=20260101010107-798
export ACMESH_CURRENT_TASK_ID
acmesh_execute_profile_deploy local local-files new-parent.example \
	"$new_parent_root/key/key.pem" "$new_parent_root/cert/fullchain.pem" '' '' ':' \
	"$source_dir/key.pem" "$source_dir/fullchain.pem" '' '' '' 22 root '' ecc >/dev/null
[ "$(cat "$new_parent_root/key/key.pem")" = new-key ] || { echo "new key parent deployment failed"; exit 1; }
[ "$(cat "$new_parent_root/cert/fullchain.pem")" = new-chain ] || { echo "new certificate parent deployment failed"; exit 1; }

ACMESH_CURRENT_TASK_ID=20260101010110-801
export ACMESH_CURRENT_TASK_ID
if acmesh_deploy_transaction "$source_dir/key.pem" "$source_dir/fullchain.pem" \
	"$target_dir/key.pem" "$target_dir/fullchain.pem" 'exit 19' '' '' ''; then
	echo "reload failure must fail the deployment"
	exit 1
fi
assert_pair "$target_dir" old
if find "$target_dir" -name '*.acmesh-new-*' -o -name '*.acmesh-backup-*' | grep . >/dev/null; then
	echo "reload rollback left transaction artifacts"
	exit 1
fi

fault_bin="$TEST_ROOT/fault-bin"
mkdir -p "$fault_bin"
real_mv="$(command -v mv)"
real_chmod="$(command -v chmod)"
real_chown="$(command -v chown)"
real_chgrp="$(command -v chgrp)"
cat > "$fault_bin/mv" <<'EOF'
#!/bin/sh
source_path=""
for arg in "$@"; do
	case "$arg" in
		-*) ;;
		*) source_path="$arg"; break ;;
	esac
done
if [ -n "${ACMESH_TEST_FAIL_ROLLBACK_MV_SOURCE:-}" ] && [ "$source_path" = "$ACMESH_TEST_FAIL_ROLLBACK_MV_SOURCE" ]; then
	[ -z "${ACMESH_TEST_FAIL_ROLLBACK_MARKER:-}" ] || : > "$ACMESH_TEST_FAIL_ROLLBACK_MARKER"
	exit 58
fi
if [ -n "${ACMESH_TEST_SIGNAL_MV_SOURCE:-}" ] && [ "$source_path" = "$ACMESH_TEST_SIGNAL_MV_SOURCE" ] && [ ! -e "$ACMESH_TEST_FAIL_MARKER" ]; then
	"${ACMESH_TEST_REAL_MV:-/bin/mv}" "$@" || exit $?
	: > "$ACMESH_TEST_FAIL_MARKER"
	kill -TERM "$PPID"
	sleep 1
	exit 0
fi
if [ "$source_path" = "$ACMESH_TEST_FAIL_MV_SOURCE" ] && [ ! -e "$ACMESH_TEST_FAIL_MARKER" ]; then
	: > "$ACMESH_TEST_FAIL_MARKER"
	exit 55
fi
exec "${ACMESH_TEST_REAL_MV:-/bin/mv}" "$@"
EOF
cat > "$fault_bin/chmod" <<'EOF'
#!/bin/sh
last=""
for arg in "$@"; do last="$arg"; done
if [ "$last" = "$ACMESH_TEST_FAIL_CHMOD_TARGET" ] && [ ! -e "$ACMESH_TEST_FAIL_MARKER" ]; then
	: > "$ACMESH_TEST_FAIL_MARKER"
	exit 56
fi
exec "${ACMESH_TEST_REAL_CHMOD:-/bin/chmod}" "$@"
EOF
for metadata_command in chown chgrp; do
	cat > "$fault_bin/$metadata_command" <<'EOF'
#!/bin/sh
command_name="${0##*/}"
if [ "$command_name" = "${ACMESH_TEST_FAIL_METADATA_COMMAND:-}" ]; then
	: > "$ACMESH_TEST_FAIL_MARKER"
	exit 57
fi
case "$command_name" in
	chown) exec "${ACMESH_TEST_REAL_CHOWN:-/bin/chown}" "$@" ;;
	chgrp) exec "${ACMESH_TEST_REAL_CHGRP:-/bin/chgrp}" "$@" ;;
esac
EOF
done
chmod +x "$fault_bin/mv" "$fault_bin/chmod" "$fault_bin/chown" "$fault_bin/chgrp"

write_pair "$target_dir" old
rm -f "$TEST_ROOT/fault.marker" "$TEST_ROOT/reload-ran"
if (
	PATH="$fault_bin:$PATH"
	ACMESH_TEST_REAL_MV="$real_mv"
	ACMESH_TEST_FAIL_MV_SOURCE="$target_dir/fullchain.pem.acmesh-new-20260101010120-820"
	ACMESH_TEST_FAIL_MARKER="$TEST_ROOT/fault.marker"
	ACMESH_CURRENT_TASK_ID=20260101010120-820
	export PATH ACMESH_TEST_REAL_MV ACMESH_TEST_FAIL_MV_SOURCE ACMESH_TEST_FAIL_MARKER ACMESH_CURRENT_TASK_ID
	hash -r
	acmesh_deploy_transaction "$source_dir/key.pem" "$source_dir/fullchain.pem" \
		"$target_dir/key.pem" "$target_dir/fullchain.pem" \
		": > '$TEST_ROOT/reload-ran'" '' '' ''
); then
	echo "second replace failure must fail deployment"
	exit 1
fi
assert_pair "$target_dir" old
[ ! -e "$TEST_ROOT/reload-ran" ] || { echo "replace failure ran reload"; exit 1; }
if find "$target_dir" -name '*.acmesh-new-*' -o -name '*.acmesh-backup-*' | grep . >/dev/null; then echo "replace failure left artifacts"; exit 1; fi

write_pair "$target_dir" old
rm -f "$TEST_ROOT/fault.marker" "$TEST_ROOT/rollback-fault.marker" "$TEST_ROOT/reload-ran"
local_backup="$target_dir/key.pem.acmesh-backup-20260101010123-823"
if (
	PATH="$fault_bin:$PATH"
	ACMESH_TEST_REAL_MV="$real_mv"
	ACMESH_TEST_FAIL_MV_SOURCE="$target_dir/fullchain.pem.acmesh-new-20260101010123-823"
	ACMESH_TEST_FAIL_ROLLBACK_MV_SOURCE="$local_backup"
	ACMESH_TEST_FAIL_MARKER="$TEST_ROOT/fault.marker"
	ACMESH_TEST_FAIL_ROLLBACK_MARKER="$TEST_ROOT/rollback-fault.marker"
	ACMESH_CURRENT_TASK_ID=20260101010123-823
	export PATH ACMESH_TEST_REAL_MV ACMESH_TEST_FAIL_MV_SOURCE ACMESH_TEST_FAIL_ROLLBACK_MV_SOURCE
	export ACMESH_TEST_FAIL_MARKER ACMESH_TEST_FAIL_ROLLBACK_MARKER ACMESH_CURRENT_TASK_ID
	hash -r
	acmesh_deploy_transaction "$source_dir/key.pem" "$source_dir/fullchain.pem" \
		"$target_dir/key.pem" "$target_dir/fullchain.pem" ':' '' '' ''
); then
	echo "failed rollback restore must fail deployment"
	exit 1
fi
[ -e "$TEST_ROOT/rollback-fault.marker" ] || { echo "rollback restore fault injection did not run"; exit 1; }
[ "$(cat "$local_backup")" = old-key ] || { echo "cleanup deleted or changed the only local key backup"; exit 1; }
[ ! -e "$target_dir/fullchain.pem.acmesh-backup-20260101010123-823" ] || { echo "successful cert rollback left its backup"; exit 1; }
rm -f "$local_backup"

write_pair "$target_dir" old
rm -f "$TEST_ROOT/fault.marker" "$TEST_ROOT/reload-ran"
if (
	PATH="$fault_bin:$PATH"
	ACMESH_TEST_REAL_CHMOD="$real_chmod"
	ACMESH_TEST_FAIL_CHMOD_TARGET="$target_dir/key.pem"
	ACMESH_TEST_FAIL_MARKER="$TEST_ROOT/fault.marker"
	ACMESH_CURRENT_TASK_ID=20260101010121-821
	export PATH ACMESH_TEST_REAL_CHMOD ACMESH_TEST_FAIL_CHMOD_TARGET ACMESH_TEST_FAIL_MARKER ACMESH_CURRENT_TASK_ID
	hash -r
	acmesh_deploy_transaction "$source_dir/key.pem" "$source_dir/fullchain.pem" \
		"$target_dir/key.pem" "$target_dir/fullchain.pem" \
		": > '$TEST_ROOT/reload-ran'" '' '' ''
); then
	echo "post-replace chmod failure must fail deployment"
	exit 1
fi
assert_pair "$target_dir" old
[ ! -e "$TEST_ROOT/reload-ran" ] || { echo "chmod failure ran reload"; exit 1; }
if find "$target_dir" -name '*.acmesh-new-*' -o -name '*.acmesh-backup-*' | grep . >/dev/null; then echo "chmod failure left artifacts"; exit 1; fi

write_pair "$target_dir" old
rm -f "$TEST_ROOT/fault.marker" "$TEST_ROOT/reload-ran"
if (
	PATH="$fault_bin:$PATH"
	ACMESH_TEST_REAL_MV="$real_mv"
	ACMESH_TEST_SIGNAL_MV_SOURCE="$target_dir/key.pem"
	ACMESH_TEST_FAIL_MARKER="$TEST_ROOT/fault.marker"
	ACMESH_CURRENT_TASK_ID=20260101010122-822
	export PATH ACMESH_TEST_REAL_MV ACMESH_TEST_SIGNAL_MV_SOURCE ACMESH_TEST_FAIL_MARKER ACMESH_CURRENT_TASK_ID
	hash -r
	acmesh_deploy_transaction "$source_dir/key.pem" "$source_dir/fullchain.pem" \
		"$target_dir/key.pem" "$target_dir/fullchain.pem" \
		": > '$TEST_ROOT/reload-ran'" '' '' ''
); then
	echo "signal immediately after backup move must fail deployment"
	exit 1
else
	backup_signal_status=$?
fi
[ "$backup_signal_status" = 143 ] || { echo "backup signal should return 143, got $backup_signal_status"; exit 1; }
assert_pair "$target_dir" old
[ ! -e "$TEST_ROOT/reload-ran" ] || { echo "backup signal ran reload"; exit 1; }
if find "$target_dir" -name '*.acmesh-new-*' -o -name '*.acmesh-backup-*' | grep . >/dev/null; then echo "backup signal left artifacts"; exit 1; fi

ACMESH_CURRENT_TASK_ID=20260101010111-802
export ACMESH_CURRENT_TASK_ID
transaction_log="$TEST_ROOT/transaction.log"
ACMESH_DEPLOY_STAGE_LOG="$transaction_log"
export ACMESH_DEPLOY_STAGE_LOG
acmesh_deploy_transaction "$source_dir/key.pem" "$source_dir/fullchain.pem" \
	"$target_dir/key.pem" "$target_dir/fullchain.pem" ':' '' '' ''
assert_pair "$target_dir" new
for stage in upload backup replace reload; do
	grep -q "^$stage$" "$transaction_log" || { echo "transaction did not log $stage"; cat "$transaction_log"; exit 1; }
done
if find "$target_dir" -name '*.acmesh-new-*' -o -name '*.acmesh-backup-*' | grep . >/dev/null; then
	echo "successful transaction left artifacts"
	exit 1
fi

write_pair "$source_dir" later
serial_log="$TEST_ROOT/serial.log"
reload_script="$TEST_ROOT/reload.sh"
cat > "$reload_script" <<'EOF'
#!/bin/sh
if [ -e "$ACMESH_SERIAL_ACTIVE" ]; then
	printf 'overlap\n' >> "$ACMESH_SERIAL_LOG"
fi
: > "$ACMESH_SERIAL_ACTIVE"
sleep 1
rm -f "$ACMESH_SERIAL_ACTIVE"
printf 'reload\n' >> "$ACMESH_SERIAL_LOG"
EOF
chmod +x "$reload_script"
ACMESH_SERIAL_ACTIVE="$TEST_ROOT/serial.active"
ACMESH_SERIAL_LOG="$serial_log"
export ACMESH_SERIAL_ACTIVE ACMESH_SERIAL_LOG
(
	ACMESH_CURRENT_TASK_ID=20260101010112-803
	export ACMESH_CURRENT_TASK_ID
	acmesh_execute_profile_deploy local local-files serial.example \
		"$target_dir/key.pem" "$target_dir/fullchain.pem" '' '' "$reload_script" \
		"$source_dir/key.pem" "$source_dir/fullchain.pem" '' '' '' 22 root '' ecc >/dev/null
) &
first=$!
(
	ACMESH_CURRENT_TASK_ID=20260101010113-804
	export ACMESH_CURRENT_TASK_ID
	acmesh_execute_profile_deploy local local-files serial.example \
		"$target_dir/key.pem" "$target_dir/fullchain.pem" '' '' "$reload_script" \
		"$source_dir/key.pem" "$source_dir/fullchain.pem" '' '' '' 22 root '' ecc >/dev/null
) &
second=$!
wait "$first"
wait "$second"
[ "$(grep -c '^reload$' "$serial_log" | tr -d ' ')" = 2 ] || { echo "both serialized reloads should run"; cat "$serial_log"; exit 1; }
if grep -q '^overlap$' "$serial_log"; then
	echo "same-target deployments overlapped"
	cat "$serial_log"
	exit 1
fi

remote_source="$TEST_ROOT/remote-source"
remote_target="$TEST_ROOT/remote-target"
write_pair "$remote_source" remote-new
write_pair "$remote_target" remote-old

run_remote_same_target_case() (
	case_name="$1"
	case_root="$TEST_ROOT/remote-same-target-$case_name"
	target_root="$case_root/target"
	mkdir -p "$target_root/a" "$target_root/b"
	case "$case_name" in
		exact) key_target="$target_root/shared.pem"; cert_target="$target_root/shared.pem" ;;
		alias) key_target="$target_root/a/../b/shared.pem"; cert_target="$target_root/b/shared.pem" ;;
		symlink) ln -s b "$target_root/link"; key_target="$target_root/link/shared.pem"; cert_target="$target_root/b/shared.pem" ;;
	esac
	printf '%s\n' remote-original > "$target_root/b/shared.pem"
	[ "$case_name" != exact ] || printf '%s\n' remote-original > "$target_root/shared.pem"
	upload_calls=0
	acmesh_deploy_generation() { printf '%s\n' 8068068068068068068068068068068068068068068068068068068068068068; }
	acmesh_deploy_ssh_copy() { upload_calls=$((upload_calls + 1)); return 91; }
	acmesh_deploy_ssh_exec() { sh -c "$4"; }
	ACMESH_CURRENT_TASK_ID=20260101010200-806
	export ACMESH_CURRENT_TASK_ID
	case_error="$case_root/error"
	case_status=0
	acmesh_deploy_remote_transaction "$remote_source/key.pem" "$remote_source/fullchain.pem" \
		"$key_target" "$cert_target" mock root-key 22 0 ':' '' '' 644 2> "$case_error" || case_status=$?
	[ "$case_status" = 74 ] || { echo "remote $case_name same target should return 74, got $case_status"; exit 1; }
	grep -q 'key and fullchain targets must be different' "$case_error" || { echo "remote $case_name same target failure was not explicit"; cat "$case_error"; exit 1; }
	[ "$upload_calls" = 0 ] || { echo "remote $case_name same target uploaded data"; exit 1; }
	if find "$target_root" -name '*.acmesh-transaction.lock' | grep . >/dev/null; then echo "remote $case_name same target created a lock"; exit 1; fi
	[ "$(cat "$cert_target")" = remote-original ] || { echo "remote $case_name same target changed the original file"; exit 1; }
)

run_remote_same_target_case exact
run_remote_same_target_case alias
run_remote_same_target_case symlink

run_ssh_transport_case() (
	transport_dir="$TEST_ROOT/transport"
	trace="$transport_dir/trace"
	mkdir -p "$transport_dir"
	rm -f "$ROOT/injected" "$ROOT/injected-sub" "$trace"
	acmesh_ssh_client_is_dropbear() { return 1; }
	scp() { echo "legacy scp was called" >&2; return 91; }
	ssh() {
		while [ "$#" -gt 0 ]; do
			case "$1" in
				-o|-i|-p) shift 2 ;;
				*) target="$1"; remote_command="$2"; break ;;
			esac
		done
		printf '%s\n' "$target" >> "$trace"
		sh -c "$remote_command"
	}
	dangerous_path="$transport_dir/remote 'single' \"double\" cert;touch injected-\$(touch injected-sub)"
	umask 022
	acmesh_deploy_ssh_copy "$remote_source/key.pem" 'root@2001:db8::42' \
		/unused/key.pem test-key 2222 0 "$dangerous_path" 600
	[ "$(cat "$dangerous_path")" = remote-new-key ] || { echo "quoted SSH stdin transport lost file content"; exit 1; }
	remote_mode="$(ls -l "$dangerous_path" | awk '{print $1}')"
	[ "$remote_mode" = -rw------- ] || { echo "remote key temp was not mode 600 before transaction: $remote_mode"; exit 1; }
	[ ! -e "$ROOT/injected" ] && [ ! -e "$ROOT/injected-sub" ] || { echo "remote path executed shell syntax"; exit 1; }
	[ "$(cat "$trace")" = 'root@2001:db8::42' ] || { echo "IPv6 SSH target was constructed incorrectly"; cat "$trace"; exit 1; }
	preview="$(acmesh_deploy_ssh_copy_command "$remote_source/key.pem" 'root@2001:db8::42' "$dangerous_path" test-key 2222 0)"
	case "$preview" in *"ssh "*"'root@2001:db8::42'"*"cat >"*) ;; *) echo "IPv6 SSH upload preview is incomplete"; echo "$preview"; exit 1;; esac
	case "$preview" in *"scp "*) echo "upload preview must not use legacy scp"; echo "$preview"; exit 1;; esac
)

run_ssh_transport_case

run_mock_remote_transaction() (
	fail_copy="${1:-0}" reload_command="${2:-:}" transport_mode="${3:-none}"
	owner="${4:-}" group="${5:-}"
	test_generation=8058058058058058058058058058058058058058058058058058058058058058
	copy_count=0
	remote_transaction_pid=""
	acmesh_deploy_generation() { printf '%s\n' "$test_generation"; }
	acmesh_deploy_ssh_copy() {
		copy_count=$((copy_count + 1))
		if [ "$fail_copy" = "$copy_count" ]; then
			printf 'partial-upload\n' > "$7"
			return 41
		fi
		cp "$1" "$7"
	}
	acmesh_deploy_ssh_exec() {
		case "$4" in
		*'acmesh_action=transaction'*)
			case "$transport_mode" in
				lost-after-completion)
					remote_status=0
					sh -c "$4" || remote_status=$?
					return 66
					;;
				async-lost-after-replace)
					sh -c "$4" &
					remote_transaction_pid=$!
					attempt=0
					while [ ! -e "$ACMESH_TEST_REMOTE_RELOAD_MARKER" ]; do
						attempt=$((attempt + 1))
						[ "$attempt" -lt 20 ] || return 68
						sleep 1
					done
					return 66
					;;
			esac
			;;
		*'acmesh_action=recover'*)
		if [ "$transport_mode" = async-lost-after-replace ]; then
			: > "$ACMESH_TEST_REMOTE_RELEASE"
		fi
			;;
		esac
		sh -c "$4"
	}
	ACMESH_CURRENT_TASK_ID=20260101010114-805
	export ACMESH_CURRENT_TASK_ID
	transaction_status=0
	acmesh_deploy_remote_transaction "$remote_source/key.pem" "$remote_source/fullchain.pem" \
		"$remote_target/key.pem" "$remote_target/fullchain.pem" mock root-key 22 0 \
		"$reload_command" "$owner" "$group" 644 || transaction_status=$?
	[ -z "$remote_transaction_pid" ] || wait "$remote_transaction_pid" 2>/dev/null || true
	return "$transaction_status"
)

if run_mock_remote_transaction 1 ':' >/dev/null 2>&1; then
	echo "first remote upload failure should fail deployment"
	exit 1
fi
assert_pair "$remote_target" remote-old
if find "$remote_target" -name '*.acmesh-new-*' -o -name '*.acmesh-backup-*' | grep . >/dev/null; then
	echo "first remote upload failure left transaction artifacts"
	exit 1
fi

if run_mock_remote_transaction 2 ':' >/dev/null 2>&1; then
	echo "second remote upload failure should fail deployment"
	exit 1
fi
assert_pair "$remote_target" remote-old
if find "$remote_target" -name '*.acmesh-new-*' -o -name '*.acmesh-backup-*' | grep . >/dev/null; then
	echo "remote upload failure left transaction artifacts"
	exit 1
fi

write_pair "$remote_target" remote-old
transport_stage_log="$TEST_ROOT/transport-stage.log"
remote_reload_marker="$TEST_ROOT/remote-reload.marker"
remote_release="$TEST_ROOT/remote-release"
rm -f "$transport_stage_log" "$remote_reload_marker" "$remote_release"
ACMESH_DEPLOY_STAGE_LOG="$transport_stage_log"
ACMESH_TEST_REMOTE_RELOAD_MARKER="$remote_reload_marker"
ACMESH_TEST_REMOTE_RELEASE="$remote_release"
export ACMESH_DEPLOY_STAGE_LOG ACMESH_TEST_REMOTE_RELOAD_MARKER ACMESH_TEST_REMOTE_RELEASE
remote_lost_reload=": > '$remote_reload_marker'; while [ ! -e '$remote_release' ]; do sleep 1; done; exit 23"
if run_mock_remote_transaction 0 "$remote_lost_reload" async-lost-after-replace >/dev/null 2>&1; then
	echo "lost transaction result after replace should fail after confirmed rollback"
	exit 1
else
	transport_status=$?
fi
[ "$transport_status" = 66 ] || { echo "transaction transport failure should preserve status 66, got $transport_status"; exit 1; }
[ -e "$remote_reload_marker" ] || { echo "transport failure test never reached remote replace/reload"; exit 1; }
assert_pair "$remote_target" remote-old
if find "$remote_target" -name '*.acmesh-*' | grep . >/dev/null; then echo "transaction transport failure left artifacts"; find "$remote_target" -name '*.acmesh-*'; exit 1; fi
for reached_stage in upload backup replace reload rollback; do
	grep -q "^$reached_stage$" "$transport_stage_log" || { echo "confirmed remote rollback omitted $reached_stage"; cat "$transport_stage_log"; exit 1; }
done
unset ACMESH_DEPLOY_STAGE_LOG

write_pair "$remote_target" remote-old
if ! run_mock_remote_transaction 0 ':' lost-after-completion >/dev/null 2>&1; then
	echo "confirmed committed transaction should survive a lost SSH result"
	exit 1
fi
assert_pair "$remote_target" remote-new
if find "$remote_target" -name '*.acmesh-*' | grep . >/dev/null; then echo "confirmed committed transaction left artifacts"; find "$remote_target" -name '*.acmesh-*'; exit 1; fi

write_pair "$remote_target" remote-old
rm -f "$TEST_ROOT/fault.marker"
if (
	PATH="$fault_bin:$PATH"
	ACMESH_TEST_REAL_MV="$real_mv"
	ACMESH_TEST_SIGNAL_MV_SOURCE="$remote_target/key.pem"
	ACMESH_TEST_FAIL_MARKER="$TEST_ROOT/fault.marker"
	export PATH ACMESH_TEST_REAL_MV ACMESH_TEST_SIGNAL_MV_SOURCE ACMESH_TEST_FAIL_MARKER
	hash -r
	run_mock_remote_transaction 0 ':' none
); then
	echo "remote signal immediately after backup move must fail"
	exit 1
else
	remote_signal_status=$?
fi
[ "$remote_signal_status" = 143 ] || { echo "remote backup signal should return 143, got $remote_signal_status"; exit 1; }
assert_pair "$remote_target" remote-old
if find "$remote_target" -name '*.acmesh-*' | grep . >/dev/null; then echo "remote backup signal left artifacts"; find "$remote_target" -name '*.acmesh-*'; exit 1; fi

for metadata_command in chown chgrp; do
	write_pair "$remote_target" remote-old
	rm -f "$TEST_ROOT/fault.marker"
	if (
		PATH="$fault_bin:$PATH"
		ACMESH_TEST_REAL_CHOWN="$real_chown"
		ACMESH_TEST_REAL_CHGRP="$real_chgrp"
		ACMESH_TEST_FAIL_METADATA_COMMAND="$metadata_command"
		ACMESH_TEST_FAIL_MARKER="$TEST_ROOT/fault.marker"
		export PATH ACMESH_TEST_REAL_CHOWN ACMESH_TEST_REAL_CHGRP ACMESH_TEST_FAIL_METADATA_COMMAND ACMESH_TEST_FAIL_MARKER
		hash -r
		case "$metadata_command" in
			chown) run_mock_remote_transaction 0 ':' none fixture_owner '' ;;
			chgrp) run_mock_remote_transaction 0 ':' none '' fixture_group ;;
		esac
	); then
		echo "$metadata_command failure should fail remote transaction"
		exit 1
	fi
	[ -e "$TEST_ROOT/fault.marker" ] || { echo "$metadata_command fault injection did not run"; exit 1; }
	assert_pair "$remote_target" remote-old
	if find "$remote_target" -name '*.acmesh-*' | grep . >/dev/null; then echo "$metadata_command failure left artifacts"; find "$remote_target" -name '*.acmesh-*'; exit 1; fi
done

write_pair "$remote_target" remote-old
rm -f "$TEST_ROOT/fault.marker" "$TEST_ROOT/rollback-fault.marker"
remote_test_generation=8058058058058058058058058058058058058058058058058058058058058058
remote_key_backup="$remote_target/key.pem.acmesh-backup-$remote_test_generation"
remote_key_lock_dir="$remote_target/key.pem.acmesh-transaction.lock"
remote_cert_lock_dir="$remote_target/fullchain.pem.acmesh-transaction.lock"
remote_state_file="$remote_key_lock_dir/state"
if (
	PATH="$fault_bin:$PATH"
	ACMESH_TEST_REAL_MV="$real_mv"
	ACMESH_TEST_REAL_CHOWN="$real_chown"
	ACMESH_TEST_FAIL_METADATA_COMMAND=chown
	ACMESH_TEST_FAIL_ROLLBACK_MV_SOURCE="$remote_key_backup"
	ACMESH_TEST_FAIL_MARKER="$TEST_ROOT/fault.marker"
	ACMESH_TEST_FAIL_ROLLBACK_MARKER="$TEST_ROOT/rollback-fault.marker"
	export PATH ACMESH_TEST_REAL_MV ACMESH_TEST_REAL_CHOWN ACMESH_TEST_FAIL_METADATA_COMMAND
	export ACMESH_TEST_FAIL_ROLLBACK_MV_SOURCE ACMESH_TEST_FAIL_MARKER ACMESH_TEST_FAIL_ROLLBACK_MARKER
	hash -r
	run_mock_remote_transaction 0 ':' none fixture_owner ''
); then
	echo "unrecoverable remote rollback must fail deployment"
	exit 1
fi
[ -e "$TEST_ROOT/rollback-fault.marker" ] || { echo "remote rollback restore fault injection did not run"; exit 1; }
[ "$(cat "$remote_key_backup")" = remote-old-key ] || { echo "client cleanup deleted or changed the only remote key backup"; exit 1; }
case "$(cat "$remote_state_file")" in recovery-required:metadata:"$remote_test_generation") ;; *) echo "remote failed rollback did not retain recovery-required state"; cat "$remote_state_file"; exit 1;; esac
for remote_lock_dir in "$remote_key_lock_dir" "$remote_cert_lock_dir"; do
	[ "$(cat "$remote_lock_dir/generation")" = "$remote_test_generation" ] || { echo "remote failed rollback lost target-lock ownership"; exit 1; }
	[ "$(cat "$remote_lock_dir/state")" = "recovery-required:metadata:$remote_test_generation" ] || { echo "remote failed rollback split target-lock state"; exit 1; }
	rm -f "$remote_lock_dir/state" "$remote_lock_dir/state.tmp-$remote_test_generation" \
		"$remote_lock_dir/generation" "$remote_lock_dir/generation.tmp-$remote_test_generation" "$remote_lock_dir/active.tmp-$remote_test_generation" \
		"$remote_lock_dir/key-absent-$remote_test_generation" "$remote_lock_dir/cert-absent-$remote_test_generation"
	rmdir "$remote_lock_dir"
done
rm -f "$remote_key_backup"
write_pair "$remote_target" remote-old

if run_mock_remote_transaction 0 'exit 23' >/dev/null 2>&1; then
	echo "remote reload failure should fail deployment"
	exit 1
else
	remote_reload_status=$?
fi
[ "$remote_reload_status" = 70 ] || { echo "remote reload failure should return 70, got $remote_reload_status"; exit 1; }
assert_pair "$remote_target" remote-old
if find "$remote_target" -name '*.acmesh-new-*' -o -name '*.acmesh-backup-*' | grep . >/dev/null; then
	echo "remote reload rollback left transaction artifacts"
	exit 1
fi

run_mock_remote_transaction 0 ':' >/dev/null
assert_pair "$remote_target" remote-new
if find "$remote_target" -name '*.acmesh-new-*' -o -name '*.acmesh-backup-*' | grep . >/dev/null; then
	echo "successful remote transaction left artifacts"
	exit 1
fi

run_target_lock_protocol_cases() (
	protocol_root="$TEST_ROOT/target-lock-protocol"
	protocol_source="$protocol_root/source"
	protocol_target="$protocol_root/target"
	protocol_marker="$protocol_root/reload.marker"
	protocol_release="$protocol_root/release"
	mkdir -p "$protocol_root"
	write_pair "$protocol_source" first
	write_pair "$protocol_target" old
	mode=lose-before-lock
	prepare_calls=0
	upload_calls=0
	remote_transaction_pid=""
	saved_recovery=""
	generation_trace="$protocol_root/generations"
	rm -f "$generation_trace"

	acmesh_deploy_ssh_copy() {
		upload_calls=$((upload_calls + 1))
		cp "$1" "$7"
	}
	acmesh_deploy_ssh_exec() {
		case "$4" in
			*'acmesh_action=prepare'*)
				printf '%s\n' "$4" | sed -n "s/^generation='\([0-9a-f][0-9a-f]*\)'$/\1/p" >> "$generation_trace"
				prepare_calls=$((prepare_calls + 1))
				if [ "$mode" = lose-before-lock ] && [ "$prepare_calls" = 1 ]; then return 66; fi
				sh -c "$4"
				;;
			*'acmesh_action=inspect'*) sh -c "$4" ;;
			*'acmesh_action=transaction'*)
				if [ "$mode" = active-timeout ]; then
					sh -c "$4" &
					remote_transaction_pid=$!
					attempt=0
					while [ ! -e "$protocol_marker" ]; do
						attempt=$((attempt + 1))
						[ "$attempt" -lt 20 ] || return 68
						sleep 1
					done
					return 66
				fi
				sh -c "$4"
				;;
			*'acmesh_action=recover'*) saved_recovery="$4"; sh -c "$4" ;;
			*'acmesh_action=cancel'*|*'acmesh_action=ack'*) sh -c "$4" ;;
			*) echo "remote command skipped target-lock protocol" >&2; return 69 ;;
		esac
	}

	ACMESH_CURRENT_TASK_ID=20260101010300-901
	export ACMESH_CURRENT_TASK_ID
	if acmesh_deploy_remote_transaction "$protocol_source/key.pem" "$protocol_source/fullchain.pem" \
		"$protocol_target/key.pem" "$protocol_target/fullchain.pem" mock root-key 22 0 ':' '' '' 644; then
		echo "connection loss before target lock should fail"
		exit 1
	else
		lost_before_status=$?
	fi
	[ "$lost_before_status" = 66 ] || { echo "pre-lock connection loss should preserve 66, got $lost_before_status"; exit 1; }
	[ "$upload_calls" = 0 ] || { echo "pre-lock connection loss uploaded files"; exit 1; }
	assert_pair "$protocol_target" old
	[ ! -e "$protocol_target/key.pem.acmesh-transaction.lock" ] || { echo "pre-lock connection loss fabricated a target lock"; exit 1; }

	mode=normal
	ACMESH_CURRENT_TASK_ID=20260101010301-902
	export ACMESH_CURRENT_TASK_ID
	acmesh_deploy_remote_transaction "$protocol_source/key.pem" "$protocol_source/fullchain.pem" \
		"$protocol_target/key.pem" "$protocol_target/fullchain.pem" mock root-key 22 0 ':' '' '' 644
	assert_pair "$protocol_target" first
	[ ! -e "$protocol_target/key.pem.acmesh-transaction.lock" ] || { echo "confirmed transaction did not ACK target lock"; exit 1; }

	write_pair "$protocol_target" old
	write_pair "$protocol_source" first
	rm -f "$protocol_marker" "$protocol_release"
	mode=active-timeout
	ACMESH_DEPLOY_REMOTE_RECOVERY_WAIT=1
	ACMESH_CURRENT_TASK_ID=20260101010302-903
	export ACMESH_DEPLOY_REMOTE_RECOVERY_WAIT ACMESH_CURRENT_TASK_ID
	blocking_reload=": > '$protocol_marker'; while [ ! -e '$protocol_release' ]; do sleep 1; done; exit 23"
	if acmesh_deploy_remote_transaction "$protocol_source/key.pem" "$protocol_source/fullchain.pem" \
		"$protocol_target/key.pem" "$protocol_target/fullchain.pem" mock root-key 22 0 "$blocking_reload" '' '' 644; then
		echo "lost active transaction result should not succeed"
		exit 1
	else
		active_status=$?
	fi
	[ "$active_status" = 66 ] || { echo "active result loss should preserve 66, got $active_status"; exit 1; }
	[ -n "$remote_transaction_pid" ] && kill -0 "$remote_transaction_pid" 2>/dev/null || { echo "old remote transaction is not still active after recovery timeout"; exit 1; }
	old_token="$(cat "$protocol_target/key.pem.acmesh-transaction.lock/generation")"
	printf '%s\n' "$old_token" | grep -Eq '^[0-9a-f]{64}$' || { echo "transaction generation is not 256-bit hex"; echo "$old_token"; exit 1; }
	[ "$old_token" != "$ACMESH_CURRENT_TASK_ID" ] || { echo "transaction reused task ID as CAS generation"; exit 1; }
	assert_pair "$protocol_target" first
	uploads_before_retry="$upload_calls"

	write_pair "$protocol_source" second
	mode=normal
	ACMESH_CURRENT_TASK_ID=20260101010302-903
	export ACMESH_CURRENT_TASK_ID
	if acmesh_deploy_remote_transaction "$protocol_source/key.pem" "$protocol_source/fullchain.pem" \
		"$protocol_target/key.pem" "$protocol_target/fullchain.pem" mock root-key 22 0 ':' '' '' 644; then
		echo "same-target retry entered while old token was active"
		exit 1
	else
		retry_busy_status=$?
	fi
	[ "$retry_busy_status" = 76 ] || { echo "same-target active retry should return 76, got $retry_busy_status"; exit 1; }
	new_token="$(sed -n '$p' "$generation_trace")"
	[ -n "$new_token" ] && [ "$new_token" != "$old_token" ] || { echo "same task ID did not receive an independent transaction generation"; cat "$generation_trace"; exit 1; }
	[ "$(cat "$protocol_target/key.pem.acmesh-transaction.lock/generation")" = "$old_token" ] || { echo "new generation took over old target lock"; exit 1; }
	[ "$upload_calls" = "$uploads_before_retry" ] || { echo "blocked same-target retry uploaded or replaced files"; exit 1; }
	assert_pair "$protocol_target" first

	: > "$protocol_release"
	wait "$remote_transaction_pid" 2>/dev/null || true
	assert_pair "$protocol_target" old
	[ -n "$saved_recovery" ] || { echo "active timeout did not retain a token-scoped recovery command"; exit 1; }
	recovered_state="$(sh -c "$saved_recovery")"
	case "$recovered_state" in "rolled-back:reload:$old_token") ;; *) echo "old token state is not recoverable"; echo "$recovered_state"; exit 1;; esac
	acmesh_deploy_remote_ack_transaction "$protocol_target/key.pem" "$protocol_target/fullchain.pem" mock root-key 22 0 "$old_token"
	[ ! -e "$protocol_target/key.pem.acmesh-transaction.lock" ] || { echo "token ACK did not release target lock"; exit 1; }

	mode=normal
	ACMESH_CURRENT_TASK_ID=20260101010304-905
	export ACMESH_CURRENT_TASK_ID
	acmesh_deploy_remote_transaction "$protocol_source/key.pem" "$protocol_source/fullchain.pem" \
		"$protocol_target/key.pem" "$protocol_target/fullchain.pem" mock root-key 22 0 ':' '' '' 644
	assert_pair "$protocol_target" second
	if find "$protocol_target" -name '*.acmesh-*' | grep . >/dev/null; then echo "recovered target-lock protocol left artifacts"; find "$protocol_target" -name '*.acmesh-*'; exit 1; fi
)

run_target_lock_protocol_cases

run_shared_resource_lock_case() (
	case_name="$1"
	shared_root="$TEST_ROOT/shared-lock-$case_name"
	source_one="$shared_root/source-one"
	source_two="$shared_root/source-two"
	target_root="$shared_root/target"
	marker="$shared_root/reload.marker"
	release="$shared_root/release"
	mkdir -p "$target_root"
	write_pair "$source_one" first
	write_pair "$source_two" second
	printf '%s\n' old-key-a > "$target_root/key-a.pem"
	printf '%s\n' old-key-b > "$target_root/key-b.pem"
	printf '%s\n' old-cert-a > "$target_root/cert-a.pem"
	printf '%s\n' old-cert-b > "$target_root/cert-b.pem"
	mode=active
	upload_calls=0
	remote_pid=""

	case "$case_name" in
		shared-cert)
			first_key="$target_root/key-a.pem"; first_cert="$target_root/z-cert-a.pem"
			second_key="$target_root/key-b.pem"; second_cert="$target_root/./z-cert-a.pem"
			second_unique="$second_key"
			printf '%s\n' old-cert-a > "$first_cert"
			;;
		shared-key)
			first_key="$target_root/key-a.pem"; first_cert="$target_root/cert-a.pem"
			second_key="$target_root/./key-a.pem"; second_cert="$target_root/cert-b.pem"
			second_unique="$second_cert"
			;;
	esac

	acmesh_deploy_ssh_copy() { upload_calls=$((upload_calls + 1)); cp "$1" "$7"; chmod "${8:-600}" "$7"; }
	acmesh_deploy_ssh_exec() {
		case "$4" in
			*'acmesh_action=transaction'*)
				if [ "$mode" = active ]; then
					sh -c "$4" & remote_pid=$!
					attempt=0
					while [ ! -e "$marker" ]; do attempt=$((attempt + 1)); [ "$attempt" -lt 20 ] || return 68; sleep 1; done
					return 66
				fi
				;;
		esac
		sh -c "$4"
	}

	ACMESH_DEPLOY_REMOTE_RECOVERY_WAIT=1
	ACMESH_CURRENT_TASK_ID=20260101010400-910
	export ACMESH_DEPLOY_REMOTE_RECOVERY_WAIT ACMESH_CURRENT_TASK_ID
	blocking_reload=": > '$marker'; while [ ! -e '$release' ]; do sleep 1; done; exit 23"
	first_status=0
	acmesh_deploy_remote_transaction "$source_one/key.pem" "$source_one/fullchain.pem" \
		"$first_key" "$first_cert" mock root-key 22 0 "$blocking_reload" '' '' 644 || first_status=$?
	[ "$first_status" = 66 ] || { echo "$case_name first transaction should preserve transport loss"; exit 1; }
	[ -n "$remote_pid" ] && kill -0 "$remote_pid" 2>/dev/null || { echo "$case_name first transaction is not active"; exit 1; }
	uploads_before="$upload_calls"

	mode=normal
	ACMESH_CURRENT_TASK_ID=20260101010401-911
	export ACMESH_CURRENT_TASK_ID
	second_status=0
	acmesh_deploy_remote_transaction "$source_two/key.pem" "$source_two/fullchain.pem" \
		"$second_key" "$second_cert" mock root-key 22 0 ':' '' '' 644 || second_status=$?
	[ "$second_status" = 76 ] || { echo "$case_name concurrent transaction was not blocked: $second_status"; exit 1; }
	[ "$upload_calls" = "$uploads_before" ] || { echo "$case_name blocked transaction uploaded or replaced data"; exit 1; }
	[ ! -e "$second_unique.acmesh-transaction.lock" ] || { echo "$case_name blocked transaction retained its partial lock"; exit 1; }
	first_generation="$(cat "$first_key.acmesh-transaction.lock/generation")"
	printf '%s\n' "$first_generation" | grep -Eq '^[0-9a-f]{64}$' || { echo "$case_name first key lock lost its generation"; exit 1; }
	[ "$(cat "$first_cert.acmesh-transaction.lock/generation")" = "$first_generation" ] || { echo "$case_name blocked transaction changed or removed a first-transaction lock"; exit 1; }

	: > "$release"
	wait "$remote_pid" 2>/dev/null || true
	[ "$(cat "$first_key")" = old-key-a ] || { echo "$case_name old key was not restored"; exit 1; }
	[ "$(cat "$first_cert")" = old-cert-a ] || { echo "$case_name old cert was not restored"; exit 1; }
)

run_shared_resource_lock_case shared-cert
run_shared_resource_lock_case shared-key

worker_script="$TEST_ROOT/blocking-worker.sh"
cat > "$worker_script" <<'EOF'
#!/bin/sh
marker="$1" child_file="$2"
trap 'printf HUP > "$marker"; exit 129' HUP
trap 'printf INT > "$marker"; exit 130' INT
trap 'printf TERM > "$marker"; exit 143' TERM
sleep 60 &
child=$!
printf '%s\n' "$child" > "$child_file"
wait "$child"
EOF
chmod +x "$worker_script"

missing_setsid_workspace="$ACMESH_TASK_WORKSPACE_DIR/missing-setsid"
missing_setsid_marker="$TEST_ROOT/missing-setsid.marker"
missing_setsid_child="$TEST_ROOT/missing-setsid.child"
mkdir -p "$missing_setsid_workspace"
if (ACMESH_DEPLOY_TIMEOUT=1 ACMESH_SETSID_BIN="$TEST_ROOT/no-such-setsid" acmesh_deploy_run_worker \
	"$missing_setsid_workspace" "$worker_script" "$missing_setsid_marker" "$missing_setsid_child"); then
	echo "deploy runner should reject missing setsid"
	exit 1
else
	missing_setsid_status=$?
fi
[ "$missing_setsid_status" = 127 ] || { echo "missing setsid should return 127, got $missing_setsid_status"; exit 1; }
[ ! -e "$missing_setsid_child" ] || { echo "worker started without the required setsid runner"; exit 1; }
[ ! -e "$missing_setsid_workspace" ] || { echo "missing setsid did not clean workspace"; exit 1; }

assert_process_gone() {
	pid="$1"
	if kill -0 "$pid" 2>/dev/null; then
		echo "deploy process remained alive: $pid"
		exit 1
	fi
}

case "$(uname -s 2>/dev/null || true)" in
MINGW*|MSYS*|CYGWIN*)
	printf '%s\n' 'test_deploy_transaction: SKIP process-tree signal assertions (Git Bash lacks authoritative /proc process ancestry)' >&2
	;;
*)
signal_driver="$TEST_ROOT/signal-driver.sh"
cat > "$signal_driver" <<'EOF'
#!/bin/sh
set -eu
. "$ACMESH_LIB_DIR/io.sh"
. "$ACMESH_LIB_DIR/deploy.sh"
signal_name="$1" workspace="$2" worker_script="$3" marker="$4" child_file="$5"
runner_pid=$$
(
	attempt=0
	while [ ! -s "$child_file" ]; do
		attempt=$((attempt + 1))
		[ "$attempt" -lt 50 ] || exit 1
		sleep 1
	done
	kill -"$signal_name" "$runner_pid"
) &
acmesh_deploy_run_worker "$workspace" "$worker_script" "$marker" "$child_file"
EOF
chmod +x "$signal_driver"
for signal in HUP INT TERM; do
	workspace="$ACMESH_TASK_WORKSPACE_DIR/signal-$signal"
	marker="$TEST_ROOT/signal-$signal.marker"
	child_file="$TEST_ROOT/signal-$signal.child"
	mkdir -p "$workspace"
	printf 'private material\n' > "$workspace/private.pem"
	if sh "$signal_driver" "$signal" "$workspace" "$worker_script" "$marker" "$child_file"; then
		echo "$signal deploy runner should exit on signal"
		exit 1
	else
		runner_status=$?
	fi
	case "$signal" in HUP) expected_status=129; expected_worker_signal=HUP;; INT) expected_status=130; expected_worker_signal=TERM;; TERM) expected_status=143; expected_worker_signal=TERM;; esac
	[ "$runner_status" = "$expected_status" ] || { echo "$signal runner status was $runner_status, expected $expected_status"; exit 1; }
	child="$(cat "$child_file")"
	attempt=0
	while kill -0 "$child" 2>/dev/null; do
		attempt=$((attempt + 1))
		[ "$attempt" -lt 50 ] || break
		sleep 1
	done
	assert_process_gone "$child"
	[ "$(cat "$marker")" = "$expected_worker_signal" ] || { echo "$signal did not stop the deploy worker with $expected_worker_signal"; exit 1; }
	[ ! -e "$workspace" ] || { echo "$signal did not remove task workspace"; exit 1; }
done

timeout_workspace="$ACMESH_TASK_WORKSPACE_DIR/timeout"
timeout_marker="$TEST_ROOT/timeout.marker"
timeout_child_file="$TEST_ROOT/timeout.child"
mkdir -p "$timeout_workspace"
printf 'private material\n' > "$timeout_workspace/private.pem"
if (ACMESH_DEPLOY_TIMEOUT=1 acmesh_deploy_run_worker "$timeout_workspace" \
	"$worker_script" "$timeout_marker" "$timeout_child_file"); then
	echo "timed out deploy worker should fail"
	exit 1
else
	timeout_status=$?
fi
[ "$timeout_status" = 124 ] || { echo "deploy timeout should return 124, got $timeout_status"; exit 1; }
timeout_child="$(cat "$timeout_child_file")"
assert_process_gone "$timeout_child"
[ "$(cat "$timeout_marker")" = TERM ] || { echo "timeout should propagate TERM"; exit 1; }
[ ! -e "$timeout_workspace" ] || { echo "timeout did not remove task workspace"; exit 1; }
;;
esac

echo "test_deploy_transaction: ok"
