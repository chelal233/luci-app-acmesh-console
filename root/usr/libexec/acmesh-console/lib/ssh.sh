. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/json.sh"
. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/command.sh"

if ! command -v acmesh_task_workspace >/dev/null 2>&1; then
	. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/io.sh"
fi

acmesh_ssh_dir() {
	printf '%s\n' "${ACMESH_SSH_DIR:-/etc/acmesh-console/ssh}"
}

acmesh_ssh_known_hosts_file() {
	printf '%s/known_hosts\n' "$(acmesh_ssh_dir)"
}

acmesh_ssh_client_type() {
	command -v ssh >/dev/null 2>&1 || return 1
	version="$(ssh -V 2>&1 || true)"
	case "$version" in
		*[Dd]ropbear*) printf '%s\n' dropbear ;;
		*[Oo]penSSH*) printf '%s\n' openssh ;;
		*) return 1 ;;
	esac
}

acmesh_ssh_client_is_dropbear() {
	[ "$(acmesh_ssh_client_type 2>/dev/null || true)" = dropbear ]
}

acmesh_ssh_validate_host() {
	case "${1:-}" in ''|-*|*[!A-Za-z0-9._:-]*) return 1 ;; esac
}

acmesh_ssh_validate_user() {
	case "${1:-}" in
		''|-*|[!A-Za-z_]*|*[!A-Za-z0-9_.-]*) return 1 ;;
	esac
}

acmesh_ssh_validate_port() {
	case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac
	[ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

acmesh_ssh_validate_target() {
	acmesh_ssh_validate_host "${1:-}" &&
		acmesh_ssh_validate_port "${2:-}" &&
		acmesh_ssh_validate_user "${3:-}"
}

acmesh_ssh_validate_remote_path() {
	path="${1:-}"
	case "$path" in /*) ;; *) return 1 ;; esac
	sanitized="$(printf '%s' "$path" | LC_ALL=C tr -d '\001-\037\177')" || return 1
	[ "$sanitized" = "$path" ]
}

acmesh_ssh_known_host_token() {
	host="$1" port="${2:-22}"
	if [ "$port" = 22 ]; then
		printf '%s\n' "$host"
	else
		printf '[%s]:%s\n' "$host" "$port"
	fi
}

acmesh_ssh_store_prepare() {
	dir="$(acmesh_ssh_dir)"
	known_hosts="$(acmesh_ssh_known_hosts_file)"
	mkdir -p "$dir" || return 1
	chmod 700 "$dir" || return 1
	if [ ! -e "$known_hosts" ]; then
		(umask 077; : > "$known_hosts") || return 1
	fi
	[ -f "$known_hosts" ] && [ ! -L "$known_hosts" ] || return 1
	chmod 600 "$known_hosts"
}

acmesh_ssh_scan_host_key() {
	host="$1" port="$2"
	acmesh_ssh_validate_host "$host" && acmesh_ssh_validate_port "$port" || return 2
	scanner="${ACMESH_SSH_KEYSCAN_BIN:-ssh-keyscan}"
	keygen="${ACMESH_SSH_KEYGEN_BIN:-ssh-keygen}"
	command -v "$scanner" >/dev/null 2>&1 || return 127
	command -v "$keygen" >/dev/null 2>&1 || return 127
	scan_file="$(mktemp "${TMPDIR:-/tmp}/acmesh-keyscan.XXXXXX")" || return 1
	"$scanner" -T "${ACMESH_SSH_SCAN_TIMEOUT:-5}" -p "$port" "$host" 2>/dev/null |
		sed -n '/^[^#][^ ]* ssh-[A-Za-z0-9-]* [A-Za-z0-9+\/=]*$/p' > "$scan_file"
	[ -s "$scan_file" ] || { rm -f "$scan_file"; return 1; }
	acmesh_ssh_scan_token="$(acmesh_ssh_known_host_token "$host" "$port")"
	known_hosts="$(acmesh_ssh_known_hosts_file)"
	scan_line=""
	if [ -f "$known_hosts" ]; then
		# ssh-keyscan output order is not stable. Prefer a key that is already
		# pinned, then a key using a pinned algorithm, before considering a new
		# algorithm. This prevents an additional server host-key algorithm from
		# being misreported as a replacement of the trusted identity.
		scan_line="$(awk -v token="$acmesh_ssh_scan_token" '
			FILENAME == ARGV[1] { if ($1 == token) pinned[$2 SUBSEP $3] = 1; next }
			pinned[$2 SUBSEP $3] { print; exit }
		' "$known_hosts" "$scan_file" 2>/dev/null || true)"
		[ -n "$scan_line" ] || scan_line="$(awk -v token="$acmesh_ssh_scan_token" '
			FILENAME == ARGV[1] { if ($1 == token) algorithms[$2] = 1; next }
			algorithms[$2] { print; exit }
		' "$known_hosts" "$scan_file" 2>/dev/null || true)"
	fi
	[ -n "$scan_line" ] || scan_line="$(head -n 1 "$scan_file")"
	rm -f "$scan_file"
	[ -n "$scan_line" ] || return 1
	set -- $scan_line
	[ "$#" -ge 3 ] || return 1
	acmesh_ssh_scan_algorithm="$2"
	acmesh_ssh_scan_key_data="$3"
	fingerprint_file="$(mktemp "${TMPDIR:-/tmp}/acmesh-hostkey.XXXXXX")" || return 1
	printf '%s %s\n' "$acmesh_ssh_scan_algorithm" "$acmesh_ssh_scan_key_data" > "$fingerprint_file"
	acmesh_ssh_scan_fingerprint="$("$keygen" -f "$fingerprint_file" -l -E sha256 2>/dev/null | awk '{print $2; exit}')"
	rm -f "$fingerprint_file"
	case "$acmesh_ssh_scan_fingerprint" in SHA256:*) ;; *) return 1 ;; esac
}

acmesh_ssh_pinned_key_data() {
	token="$1" algorithm="$2" known_hosts="$(acmesh_ssh_known_hosts_file)"
	[ -f "$known_hosts" ] || return 1
	awk -v token="$token" -v algorithm="$algorithm" \
		'$1 == token && $2 == algorithm { print $3; found = 1; exit } END { if (!found) exit 1 }' \
		"$known_hosts"
}

acmesh_ssh_token_is_pinned() {
	token="$1" known_hosts="$(acmesh_ssh_known_hosts_file)"
	[ -f "$known_hosts" ] || return 1
	awk -v token="$token" '$1 == token { found = 1; exit } END { exit !found }' "$known_hosts"
}

acmesh_ssh_write_challenge() {
	challenge_file="$1"
	acmesh_path_dir "$challenge_file"
	mkdir -p "$dir" || return 1
	chmod 700 "$dir" || return 1
	challenge_tmp="$(mktemp "$dir/.hostkey-challenge.XXXXXX")" || return 1
	chmod 600 "$challenge_tmp" || { rm -f "$challenge_tmp"; return 1; }
	{
		printf 'host=%s\n' "$2"
		printf 'port=%s\n' "$3"
		printf 'token=%s\n' "$acmesh_ssh_scan_token"
		printf 'algorithm=%s\n' "$acmesh_ssh_scan_algorithm"
		printf 'key=%s\n' "$acmesh_ssh_scan_key_data"
		printf 'fingerprint=%s\n' "$acmesh_ssh_scan_fingerprint"
	} > "$challenge_tmp" || { rm -f "$challenge_tmp"; return 1; }
	mv -f "$challenge_tmp" "$challenge_file"
}

acmesh_ssh_probe_host_key() {
	host="$1" port="${2:-22}" challenge_file="${3:-}"
	acmesh_ssh_validate_host "$host" && acmesh_ssh_validate_port "$port" || {
		printf '{"ok":false,"error":"invalidSshTarget"}\n'
		return 2
	}
	acmesh_ssh_store_prepare || return 1
	acmesh_ssh_scan_host_key "$host" "$port" || {
		printf '{"ok":false,"error":"hostKeyProbeFailed"}\n'
		return 1
	}
	if pinned="$(acmesh_ssh_pinned_key_data "$acmesh_ssh_scan_token" "$acmesh_ssh_scan_algorithm" 2>/dev/null)"; then
		if [ "$pinned" = "$acmesh_ssh_scan_key_data" ]; then
			printf '{"ok":true,"algorithm":"%s","fingerprint":"%s"}\n' \
				"$(acmesh_json_escape "$acmesh_ssh_scan_algorithm")" \
				"$(acmesh_json_escape "$acmesh_ssh_scan_fingerprint")"
			return 0
		fi
		printf '{"ok":false,"error":"hostKeyChanged","algorithm":"%s","fingerprint":"%s"}\n' \
			"$(acmesh_json_escape "$acmesh_ssh_scan_algorithm")" \
			"$(acmesh_json_escape "$acmesh_ssh_scan_fingerprint")"
		return 3
	fi
	if acmesh_ssh_token_is_pinned "$acmesh_ssh_scan_token"; then
		printf '{"ok":false,"error":"hostKeyChanged","algorithm":"%s","fingerprint":"%s"}\n' \
			"$(acmesh_json_escape "$acmesh_ssh_scan_algorithm")" \
			"$(acmesh_json_escape "$acmesh_ssh_scan_fingerprint")"
		return 3
	fi
	[ -n "$challenge_file" ] || {
		printf '{"ok":false,"error":"hostKeyRequired","algorithm":"%s","fingerprint":"%s"}\n' \
			"$(acmesh_json_escape "$acmesh_ssh_scan_algorithm")" \
			"$(acmesh_json_escape "$acmesh_ssh_scan_fingerprint")"
		return 4
	}
	acmesh_ssh_write_challenge "$challenge_file" "$host" "$port" || return 1
	printf '{"ok":false,"error":"hostKeyRequired","challengeId":"%s","algorithm":"%s","fingerprint":"%s"}\n' \
		"$(acmesh_json_escape "${challenge_file##*/}")" \
		"$(acmesh_json_escape "$acmesh_ssh_scan_algorithm")" \
		"$(acmesh_json_escape "$acmesh_ssh_scan_fingerprint")"
	return 4
}

acmesh_ssh_challenge_value() {
	challenge_file="$1" challenge_key="$2"
	sed -n "s/^${challenge_key}=//p" "$challenge_file" | head -n 1
}

acmesh_ssh_confirm_host_key_locked() {
	challenge_file="$1"
	expected_algorithm="$2"
	expected_key="$3"
	expected_fingerprint="$4"
	scan_token="$5"
	scan_algorithm="$6"
	scan_key="$7"
	scan_fingerprint="$8"
	known_hosts="$(acmesh_ssh_known_hosts_file)"

	if acmesh_ssh_token_is_pinned "$scan_token"; then
		pinned="$(acmesh_ssh_pinned_key_data "$scan_token" "$scan_algorithm" 2>/dev/null || true)"
		if [ -z "$pinned" ] || [ "$pinned" != "$scan_key" ] || \
			[ "$scan_algorithm" != "$expected_algorithm" ] || \
			[ "$scan_key" != "$expected_key" ] || \
			[ "$scan_fingerprint" != "$expected_fingerprint" ]; then
			printf '{"ok":false,"error":"hostKeyChanged","algorithm":"%s","fingerprint":"%s"}\n' \
				"$(acmesh_json_escape "$scan_algorithm")" \
				"$(acmesh_json_escape "$scan_fingerprint")"
			return 3
		fi
		rm -f "$challenge_file"
		printf '{"ok":true,"algorithm":"%s","fingerprint":"%s"}\n' \
			"$(acmesh_json_escape "$scan_algorithm")" \
			"$(acmesh_json_escape "$scan_fingerprint")"
		return 0
	fi

	tmp="$(mktemp "$(acmesh_ssh_dir)/.known_hosts.XXXXXX")" || return 1
	awk -v token="$scan_token" '$1 != token' "$known_hosts" > "$tmp" || { rm -f "$tmp"; return 1; }
	printf '%s %s %s\n' "$scan_token" "$scan_algorithm" "$scan_key" >> "$tmp"
	chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }
	mv -f "$tmp" "$known_hosts" || { rm -f "$tmp"; return 1; }
	rm -f "$challenge_file"
	printf '{"ok":true,"algorithm":"%s","fingerprint":"%s"}\n' \
		"$(acmesh_json_escape "$scan_algorithm")" \
		"$(acmesh_json_escape "$scan_fingerprint")"
}

acmesh_ssh_confirm_host_key() {
	challenge_file="${1:-}"
	[ -f "$challenge_file" ] && [ ! -L "$challenge_file" ] || return 2
	host="$(acmesh_ssh_challenge_value "$challenge_file" host)"
	port="$(acmesh_ssh_challenge_value "$challenge_file" port)"
	expected_algorithm="$(acmesh_ssh_challenge_value "$challenge_file" algorithm)"
	expected_key="$(acmesh_ssh_challenge_value "$challenge_file" key)"
	expected_fingerprint="$(acmesh_ssh_challenge_value "$challenge_file" fingerprint)"
	acmesh_ssh_validate_host "$host" && acmesh_ssh_validate_port "$port" || return 2
	acmesh_ssh_scan_host_key "$host" "$port" || return 1
	if [ "$acmesh_ssh_scan_algorithm" != "$expected_algorithm" ] || \
		[ "$acmesh_ssh_scan_key_data" != "$expected_key" ] || \
		[ "$acmesh_ssh_scan_fingerprint" != "$expected_fingerprint" ]; then
		printf '{"ok":false,"error":"hostKeyChanged","algorithm":"%s","fingerprint":"%s"}\n' \
			"$(acmesh_json_escape "$acmesh_ssh_scan_algorithm")" \
			"$(acmesh_json_escape "$acmesh_ssh_scan_fingerprint")"
		return 3
	fi
	acmesh_ssh_store_prepare || return 1
	acmesh_lock_run "$(acmesh_ssh_dir)/known_hosts.lock" acmesh_ssh_confirm_host_key_locked \
		"$challenge_file" "$expected_algorithm" "$expected_key" "$expected_fingerprint" \
		"$acmesh_ssh_scan_token" "$acmesh_ssh_scan_algorithm" "$acmesh_ssh_scan_key_data" "$acmesh_ssh_scan_fingerprint"
}

acmesh_ssh_verify_pinned_host() {
	host="$1" port="${2:-22}"
	acmesh_ssh_validate_host "$host" && acmesh_ssh_validate_port "$port" || {
		printf '{"ok":false,"error":"invalidSshTarget"}\n'
		return 2
	}
	acmesh_ssh_store_prepare || return 1
	acmesh_ssh_scan_host_key "$host" "$port" || {
		printf '{"ok":false,"error":"hostKeyProbeFailed"}\n'
		return 1
	}
	pinned="$(acmesh_ssh_pinned_key_data "$acmesh_ssh_scan_token" "$acmesh_ssh_scan_algorithm" 2>/dev/null || true)"
	if [ -n "$pinned" ] && [ "$pinned" = "$acmesh_ssh_scan_key_data" ]; then
		printf '{"ok":true,"algorithm":"%s","fingerprint":"%s"}\n' \
			"$(acmesh_json_escape "$acmesh_ssh_scan_algorithm")" \
			"$(acmesh_json_escape "$acmesh_ssh_scan_fingerprint")"
		return 0
	fi
	if acmesh_ssh_token_is_pinned "$acmesh_ssh_scan_token"; then
		error=hostKeyChanged
		status=3
	else
		error=hostKeyRequired
		status=4
	fi
	printf '{"ok":false,"error":"%s","algorithm":"%s","fingerprint":"%s"}\n' \
		"$error" \
		"$(acmesh_json_escape "$acmesh_ssh_scan_algorithm")" \
		"$(acmesh_json_escape "$acmesh_ssh_scan_fingerprint")"
	return "$status"
}

acmesh_ssh_prepare_dropbear_home() {
	home="$1"
	[ -n "$home" ] || return 2
	mkdir -p "$home/.ssh" || return 1
	chmod 700 "$home" "$home/.ssh" || return 1
	known_hosts="$(acmesh_ssh_known_hosts_file)"
	[ -f "$known_hosts" ] || return 1
	cp "$known_hosts" "$home/.ssh/known_hosts" || return 1
	chmod 600 "$home/.ssh/known_hosts"
}

acmesh_ssh_command_options() {
	client="$1" private_home="${2:-}"
	case "$client" in
		openssh)
			printf '%s %s' '-o StrictHostKeyChecking=yes -o UserKnownHostsFile=' \
				"$(acmesh_shell_quote "$(acmesh_ssh_known_hosts_file)")"
			;;
		dropbear)
			[ -n "$private_home" ] || return 2
			printf 'HOME=%s' "$(acmesh_shell_quote "$private_home")"
			;;
		*) return 2 ;;
	esac
}

acmesh_ssh_public_from_dropbear() {
	key="$1"
	dropbearkey -y -f "$key" 2>/dev/null | sed -n '/^ssh-/p' | head -n 1
}

acmesh_ssh_key_ensure() {
	dir="$(acmesh_ssh_dir)"
	key="$dir/id_ed25519"
	pub="$key.pub"
	mkdir -p "$dir"
	chmod 700 "$dir"

	if [ ! -f "$key" ]; then
		if command -v ssh-keygen >/dev/null 2>&1; then
			ssh-keygen -q -t ed25519 -N '' -f "$key" >/dev/null
		elif command -v dropbearkey >/dev/null 2>&1; then
			dropbearkey -t ed25519 -f "$key" >/dev/null 2>&1
			acmesh_ssh_public_from_dropbear "$key" > "$pub"
		else
			printf '{"ok":false,"error":"no ssh key generator found"}\n'
			return 1
		fi
	fi

	if [ ! -s "$pub" ]; then
		if command -v ssh-keygen >/dev/null 2>&1; then
			ssh-keygen -y -f "$key" > "$pub"
		elif command -v dropbearkey >/dev/null 2>&1; then
			acmesh_ssh_public_from_dropbear "$key" > "$pub"
		else
			printf '{"ok":false,"error":"no ssh public key reader found"}\n'
			return 1
		fi
	fi

	chmod 600 "$key" 2>/dev/null || true
	chmod 644 "$pub" 2>/dev/null || true
	printf '{"ok":true,"privateKey":"%s","publicKey":"%s"}\n' \
		"$(acmesh_json_escape "$key")" \
		"$(acmesh_json_escape "$(cat "$pub")")"
}

acmesh_ssh_test_log() {
	host="$1"
	port="${2:-22}"
	user="${3:-root}"
	key="$4"
	remote_command="${5:-true}"
	test_mode="${6:-0}"

	acmesh_ssh_validate_target "$host" "$port" "$user" || { echo "invalid SSH target" >&2; return 2; }
	[ -n "$key" ] || { echo "private key path is required" >&2; return 1; }

	if [ "$test_mode" = 1 ]; then
		printf 'TEST MODE: SSH command assembled, but no network connection was opened.\n'
		printf 'ssh -i %s -p %s -o BatchMode=yes %s@%s %s\n' \
			"$(acmesh_shell_quote "$key")" \
			"$(acmesh_shell_quote "$port")" \
			"$user" \
			"$host" \
			"$(acmesh_shell_quote "$remote_command")"
		return 0
	fi

	acmesh_ssh_verify_pinned_host "$host" "$port" >/dev/null || return $?
	client="$(acmesh_ssh_client_type)" || { echo "unsupported ssh client" >&2; return 1; }
	if [ "$client" = openssh ]; then
		ssh -i "$key" -p "$port" -o BatchMode=yes -o StrictHostKeyChecking=yes \
			-o "UserKnownHostsFile=$(acmesh_ssh_known_hosts_file)" "$user@$host" "$remote_command"
	else
		[ -n "${ACMESH_CURRENT_TASK_ID:-}" ] || { echo "Dropbear SSH test requires a task workspace" >&2; return 2; }
		workspace="$(acmesh_task_workspace "$ACMESH_CURRENT_TASK_ID")" || return 1
		private_home="$workspace/dropbear-home"
		acmesh_ssh_prepare_dropbear_home "$private_home" || return 1
		HOME="$private_home" ssh -i "$key" -p "$port" "$user@$host" "$remote_command"
	fi
}
