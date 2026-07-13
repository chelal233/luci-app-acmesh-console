. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/json.sh"
. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/io.sh"
. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/profile.sh"

: "${ACMESH_CONSOLE_CONFIG:=/etc/acmesh-console/config.json}"
: "${ACMESH_CONSOLE_UCI_CONFIG:=/etc/config/acmesh-console}"

acmesh_config_uci_option() {
	key="$1"
	[ -r "$ACMESH_CONSOLE_UCI_CONFIG" ] || return 1
	sed -n "s/^[	 ]*option[	 ][	 ]*$key[	 ][	 ]*['\"]\\([^'\"]*\\)['\"].*/\\1/p" "$ACMESH_CONSOLE_UCI_CONFIG" | head -n 1
}

acmesh_config_default_json() {
	home="$(acmesh_config_uci_option home || true)"
	email="$(acmesh_config_uci_option default_account_email || true)"
	core_tag="$(acmesh_config_uci_option core_tag || true)"
	[ -n "$home" ] || home="/etc/acme"
	[ -n "$core_tag" ] || core_tag="v3.1.4"
	printf '{"schemaVersion":2,"global":{"defaultAccountEmail":"%s","coreTag":"%s","acmeHome":"%s"},"accountProfiles":[],"issueProfiles":[],"deployProfiles":[]}\n' \
		"$(acmesh_json_escape "$email")" \
		"$(acmesh_json_escape "$core_tag")" \
		"$(acmesh_json_escape "$home")"
}

acmesh_config_path() {
	printf '%s\n' "$ACMESH_CONSOLE_CONFIG"
}

acmesh_config_get() {
	path="$(acmesh_config_path)"
	if [ -s "$path" ]; then
		cat "$path"
	else
		acmesh_config_default_json
	fi
}

acmesh_config_save_file() (
	set +u
	request_file="$1"
	if ! acmesh_config_validate_file "$request_file"; then
		printf '{"ok":false,"error":"configuration schema validation failed"}\n'
		return 2
	fi
	path="$(acmesh_config_path)"
	acmesh_profile_jshn || return 1
	json_load_file "$request_file" || return 1
	json_get_type version_type schemaVersion 2>/dev/null || version_type=
	[ -n "$version_type" ] || json_add_int schemaVersion 2
	json_dump | acmesh_atomic_write "$path" 600 || {
		printf '{"ok":false,"error":"configuration save failed"}\n'
		return 1
	}
	printf '{"ok":true,"path":"%s"}\n' "$(acmesh_json_escape "$path")"
)

acmesh_config_bool() {
	key="$1"
	default="$2"
	value="$(acmesh_config_get | jsonfilter -e "@.global.$key" 2>/dev/null || true)"
	[ -n "$value" ] && printf '%s\n' "$value" || printf '%s\n' "$default"
}

acmesh_config_string() {
	key="$1"
	default="$2"
	value="$(acmesh_config_get | jsonfilter -e "@.global.$key" 2>/dev/null || true)"
	[ -n "$value" ] && printf '%s\n' "$value" || printf '%s\n' "$default"
}
