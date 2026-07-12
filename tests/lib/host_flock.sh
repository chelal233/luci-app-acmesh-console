#!/bin/sh

acmesh_test_install_flock_shim() {
	shim_root="$1"
	command -v flock >/dev/null 2>&1 && return 0
	mkdir -p "$shim_root/bin" "$shim_root/lock"
	cat > "$shim_root/bin/flock" <<'EOF'
#!/bin/sh
[ "${1:-}" = -n ] && [ "${2:-}" = 9 ] || exit 2
held="$ACMESH_TEST_FLOCK_ROOT/held"
parent="$PPID"
if ! mkdir "$held" 2>/dev/null; then
	owner="$(cat "$held/owner" 2>/dev/null || true)"
	case "$owner" in
		''|*[!0-9]*) exit 1 ;;
	esac
	kill -0 "$owner" 2>/dev/null && exit 1
	rm -f "$held/owner"
	rmdir "$held" 2>/dev/null || exit 1
	mkdir "$held" 2>/dev/null || exit 1
fi
printf '%s\n' "$parent" > "$held/owner"
(
	while kill -0 "$parent" 2>/dev/null; do
		sleep 0.05
	done
	if [ "$(cat "$held/owner" 2>/dev/null || true)" = "$parent" ]; then
		rm -f "$held/owner"
		rmdir "$held" 2>/dev/null || true
	fi
) </dev/null >/dev/null 2>&1 &
exit 0
EOF
	chmod +x "$shim_root/bin/flock"
	ACMESH_TEST_FLOCK_ROOT="$shim_root/lock"
	PATH="$shim_root/bin:$PATH"
	export ACMESH_TEST_FLOCK_ROOT PATH
}

acmesh_test_install_private_ls_shim() {
	shim_root="$1"
	private_root="$2"
	[ "$(LC_ALL=C ls -ld "$private_root" 2>/dev/null | awk '{print $1}')" != drwx------ ] || return 0
	mkdir -p "$shim_root/bin"
	ACMESH_TEST_REAL_LS="$(command -v ls)"
	ACMESH_TEST_PRIVATE_ROOT="$private_root"
	export ACMESH_TEST_REAL_LS ACMESH_TEST_PRIVATE_ROOT
	cat > "$shim_root/bin/ls" <<'EOF'
#!/bin/sh
case "${1:-}" in
	-ld|-nd)
		candidate="${2:-}"
		case "$candidate" in
			"$ACMESH_TEST_PRIVATE_ROOT"|"$ACMESH_TEST_PRIVATE_ROOT"/*)
				if [ -d "$candidate" ] && [ ! -L "$candidate" ]; then
					printf 'drwx------ 1 0 0 0 Jan 1 00:00 %s\n' "$candidate"
					exit 0
				fi
				if [ -f "$candidate" ] && [ ! -L "$candidate" ]; then
					printf '%s\n' "-rw------- 1 0 0 0 Jan 1 00:00 $candidate"
					exit 0
				fi
				;;
		esac
		;;
esac
exec "$ACMESH_TEST_REAL_LS" "$@"
EOF
	chmod +x "$shim_root/bin/ls"
	PATH="$shim_root/bin:$PATH"
	export PATH
}
