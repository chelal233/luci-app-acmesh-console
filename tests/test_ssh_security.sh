#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
TEST_ROOT="$ROOT/tests/.tmp/ssh-security"
export ACMESH_SSH_DIR="$TEST_ROOT/ssh"
export ACMESH_TASK_WORKSPACE_DIR="$TEST_ROOT/workspaces"
rm -rf "$TEST_ROOT"
mkdir -p "$TEST_ROOT/bin" "$ACMESH_TASK_WORKSPACE_DIR"
chmod 700 "$TEST_ROOT" "$ACMESH_TASK_WORKSPACE_DIR"
. "$ROOT/tests/lib/host_flock.sh"
acmesh_test_install_flock_shim "$TEST_ROOT/flock"

grep -Eq '^LUCI_DEPENDS:=.*\+openssh-client-utils([[:space:]]|$)' "$ROOT/Makefile" || {
	echo "Makefile must depend on openssh-client-utils for ssh-keyscan"
	exit 1
}

cat > "$TEST_ROOT/bin/ssh-keyscan" <<'EOF'
#!/bin/sh
host=""
while [ "$#" -gt 0 ]; do
	case "$1" in -p|-T|-t) shift 2 ;; *) host="$1"; shift ;; esac
done
if [ -n "${ACMESH_TEST_HOSTKEY_LINES:-}" ]; then
	printf '%b\n' "$ACMESH_TEST_HOSTKEY_LINES"
else
	printf '%s %s %s\n' "$host" "${ACMESH_TEST_HOSTKEY_ALGORITHM:-ssh-ed25519}" "${ACMESH_TEST_HOSTKEY_DATA:-AAAAfirst}"
fi
EOF
cat > "$TEST_ROOT/bin/ssh-keygen" <<'EOF'
#!/bin/sh
file=""
while [ "$#" -gt 0 ]; do
	case "$1" in -l|-f|-E) [ "$1" = -f ] && file="$2"; shift 2 ;; *) shift ;; esac
done
case "$(cat "$file")" in
	*AAAAfirst*) printf '256 SHA256:first fixture (ED25519)\n' ;;
	*AAAAsecond*) printf '256 SHA256:second fixture (ED25519)\n' ;;
	*AAAArsa*) printf '3072 SHA256:rsa fixture (RSA)\n' ;;
	*) exit 1 ;;
esac
EOF
cat > "$TEST_ROOT/bin/ssh" <<'EOF'
#!/bin/sh
if [ "${1:-}" = -V ]; then
	printf '%s\n' "${ACMESH_TEST_SSH_VERSION:-OpenSSH_9.9}" >&2
	exit 0
fi
printf 'HOME=%s\n' "${HOME:-}" >> "$ACMESH_TEST_SSH_TRACE"
printf 'ARGS=' >> "$ACMESH_TEST_SSH_TRACE"
printf ' <%s>' "$@" >> "$ACMESH_TEST_SSH_TRACE"
printf '\n' >> "$ACMESH_TEST_SSH_TRACE"
EOF
chmod +x "$TEST_ROOT/bin/ssh-keyscan" "$TEST_ROOT/bin/ssh-keygen" "$TEST_ROOT/bin/ssh"
PATH="$TEST_ROOT/bin:$PATH"
export PATH

. "$ACMESH_LIB_DIR/io.sh"
. "$ACMESH_LIB_DIR/ssh.sh"

acmesh_ssh_validate_target example.com 22 root
acmesh_ssh_validate_target 2001:db8::1 65535 deploy_user
for bad_host in '' '-proxy' 'host name' 'host;id' 'host
name'; do
	if acmesh_ssh_validate_target "$bad_host" 22 root; then
		echo "unsafe SSH host accepted: $bad_host"
		exit 1
	fi
done
for bad_user in '' '-root' 'root user' 'root;id' 'root
user'; do
	if acmesh_ssh_validate_target example.com 22 "$bad_user"; then
		echo "unsafe SSH user accepted: $bad_user"
		exit 1
	fi
done
for bad_port in 0 65536 22x '-22' '22 23'; do
	if acmesh_ssh_validate_target example.com "$bad_port" root; then
		echo "unsafe SSH port accepted: $bad_port"
		exit 1
	fi
done
for bad_path in relative '-/etc/key' '/etc/key
next'; do
	if acmesh_ssh_validate_remote_path "$bad_path"; then
		echo "unsafe remote path accepted: $bad_path"
		exit 1
	fi
done
acmesh_ssh_validate_remote_path /etc/ssl/example.key

stale_challenge="$TEST_ROOT/challenge-stale"
probe="$(acmesh_ssh_probe_host_key example.com 22 "$stale_challenge" || true)"
case "$probe" in
	*'"error":"hostKeyRequired"'*'"algorithm":"ssh-ed25519"'*'"fingerprint":"SHA256:first"'*) ;;
	*) echo "unknown host should require confirmation"; echo "$probe"; exit 1 ;;
esac
[ -s "$stale_challenge" ] || { echo "unknown host should create a private challenge"; exit 1; }

ACMESH_TEST_HOSTKEY_DATA=AAAAsecond
export ACMESH_TEST_HOSTKEY_DATA
new_challenge="$TEST_ROOT/challenge-new"
new_probe="$(acmesh_ssh_probe_host_key example.com 22 "$new_challenge" || true)"
case "$new_probe" in *'"error":"hostKeyRequired"'*'"fingerprint":"SHA256:second"'*) ;; *) echo "second challenge should capture changed probe"; echo "$new_probe"; exit 1;; esac
confirm="$(acmesh_ssh_confirm_host_key "$new_challenge")"
case "$confirm" in *'"ok":true'*'"fingerprint":"SHA256:second"'*) ;; *) echo "matching second challenge should pin host"; echo "$confirm"; exit 1;; esac
acmesh_ssh_verify_pinned_host example.com 22 >/dev/null
grep -q 'ssh-ed25519 AAAAsecond' "$ACMESH_SSH_DIR/known_hosts" || { echo "confirmed host key was not pinned"; exit 1; }

# A server may advertise more host-key algorithms over time. A still-present
# pinned key must win over ssh-keyscan's unstable output order.
printf 'multi.example ssh-rsa AAAArsa\n' >> "$ACMESH_SSH_DIR/known_hosts"
ACMESH_TEST_HOSTKEY_LINES='multi.example ssh-ed25519 AAAAsecond\nmulti.example ssh-rsa AAAArsa'
export ACMESH_TEST_HOSTKEY_LINES
multi_probe="$(acmesh_ssh_probe_host_key multi.example 22)"
case "$multi_probe" in
	*'"ok":true'*'"algorithm":"ssh-rsa"'*'"fingerprint":"SHA256:rsa"'*) ;;
	*) echo "an additional host-key algorithm was mistaken for key replacement"; echo "$multi_probe"; exit 1 ;;
esac
unset ACMESH_TEST_HOSTKEY_LINES

ACMESH_TEST_HOSTKEY_DATA=AAAAfirst
export ACMESH_TEST_HOSTKEY_DATA
stale_result="$(acmesh_ssh_confirm_host_key "$stale_challenge" 2>&1 || true)"
case "$stale_result" in *'"error":"hostKeyChanged"'*) ;; *) echo "stale challenge should not overwrite canonical pin"; echo "$stale_result"; exit 1;; esac
grep -q 'ssh-ed25519 AAAAsecond' "$ACMESH_SSH_DIR/known_hosts" || { echo "stale challenge replaced the canonical pin"; exit 1; }

rm -f "$ACMESH_SSH_DIR/known_hosts"
acmesh_ssh_store_prepare
ACMESH_TEST_HOSTKEY_DATA=AAAAfirst
export ACMESH_TEST_HOSTKEY_DATA
concurrent_pids=""
for n in 1 2 3 4 5 6 7 8; do
	challenge="$TEST_ROOT/challenge-$n"
	acmesh_ssh_probe_host_key "host$n.example" 22 "$challenge" >/dev/null 2>&1 || [ "$?" = 4 ]
	(acmesh_ssh_confirm_host_key "$challenge" >/dev/null) &
	concurrent_pids="$concurrent_pids $!"
done
for pid in $concurrent_pids; do
	if ! wait "$pid"; then
		echo "concurrent host-key confirmation failed"
		exit 1
	fi
done
for n in 1 2 3 4 5 6 7 8; do
	if ! grep -q "^host$n.example ssh-ed25519 AAAAfirst$" "$ACMESH_SSH_DIR/known_hosts"; then
		echo "concurrent confirmation lost host$n.example"
		cat "$ACMESH_SSH_DIR/known_hosts"
		exit 1
	fi
done

ACMESH_TEST_HOSTKEY_DATA=AAAAsecond
export ACMESH_TEST_HOSTKEY_DATA
changed="$(acmesh_ssh_verify_pinned_host host1.example 22 2>&1 || true)"
case "$changed" in *'"error":"hostKeyChanged"'*'"fingerprint":"SHA256:second"'*) ;; *) echo "changed host key should hard stop"; echo "$changed"; exit 1;; esac
if grep -q '^host1.example ssh-ed25519 AAAAsecond$' "$ACMESH_SSH_DIR/known_hosts"; then
	echo "changed probe replaced a pin"
	exit 1
fi

open_command="$(acmesh_ssh_command_options openssh "$TEST_ROOT/private-home")"
case "$open_command" in *"StrictHostKeyChecking=yes"*"UserKnownHostsFile="*) ;; *) echo "OpenSSH must use the canonical pin store"; echo "$open_command"; exit 1;; esac
case "$open_command" in *accept-new*|*StrictHostKeyChecking=no*) echo "OpenSSH command allows host-key bypass"; exit 1;; esac

dropbear_home="$TEST_ROOT/private-home"
acmesh_ssh_prepare_dropbear_home "$dropbear_home"
[ -f "$dropbear_home/.ssh/known_hosts" ] || { echo "Dropbear private HOME is missing known_hosts"; exit 1; }
cmp "$ACMESH_SSH_DIR/known_hosts" "$dropbear_home/.ssh/known_hosts" >/dev/null
drop_command="$(acmesh_ssh_command_options dropbear "$dropbear_home")"
case "$drop_command" in *' -y '*|'-y '*) echo "Dropbear must not bypass pinned host keys"; echo "$drop_command"; exit 1;; esac

run_ssh_test_client_case() (
	client="$1"
	trace="$TEST_ROOT/ssh-test-$client.trace"
	rm -f "$trace"
	ACMESH_TEST_SSH_TRACE="$trace"
	ACMESH_CURRENT_TASK_ID=20260101010200-900
	case "$client" in
		openssh) ACMESH_TEST_SSH_VERSION=OpenSSH_9.9 ;;
		dropbear) ACMESH_TEST_SSH_VERSION='Dropbear v2025.88' ;;
	esac
	export ACMESH_TEST_SSH_TRACE ACMESH_TEST_SSH_VERSION ACMESH_CURRENT_TASK_ID
	[ "$(acmesh_ssh_client_type)" = "$client" ] || { echo "production SSH client detection missed $client"; exit 1; }
	acmesh_ssh_verify_pinned_host() { return 0; }
	acmesh_ssh_test_log example.com 22 root test-key true 0
	case "$client" in
		openssh)
			grep -q 'StrictHostKeyChecking=yes' "$trace" || { echo "ssh-test omitted OpenSSH pinning options"; cat "$trace"; exit 1; }
			grep -q 'UserKnownHostsFile=' "$trace" || { echo "ssh-test omitted OpenSSH known-hosts path"; cat "$trace"; exit 1; }
			;;
		dropbear)
			case "$(sed -n '1p' "$trace")" in HOME="$ACMESH_TASK_WORKSPACE_DIR"/*/dropbear-home) ;; *) echo "ssh-test omitted task-private Dropbear HOME"; cat "$trace"; exit 1;; esac
			grep -q 'StrictHostKeyChecking\|UserKnownHostsFile' "$trace" && { echo "ssh-test passed OpenSSH options to Dropbear"; cat "$trace"; exit 1; }
			private_home="$(sed -n 's/^HOME=//p' "$trace" | head -n 1)"
			cmp "$ACMESH_SSH_DIR/known_hosts" "$private_home/.ssh/known_hosts" >/dev/null || { echo "ssh-test Dropbear HOME does not contain canonical pins"; exit 1; }
			;;
	esac
)

run_ssh_test_client_case openssh
run_ssh_test_client_case dropbear

echo "test_ssh_security: ok"
