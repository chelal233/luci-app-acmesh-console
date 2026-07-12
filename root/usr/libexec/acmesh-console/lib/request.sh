: "${ACMESH_REQUEST_DIR:=/var/run/acmesh-console/requests}"

acmesh_request_validate_id() {
	printf '%s\n' "${1:-}" | grep -Eq '^[a-f0-9]{32}$'
}

acmesh_request_dir_is_private() (
	request_dir="${1:-}"
	[ -n "$request_dir" ] || exit 1
	[ -d "$request_dir" ] && [ ! -L "$request_dir" ] || exit 1
	listing="$(LC_ALL=C ls -ld "$request_dir" 2>/dev/null)" || exit 1
	set -- $listing
	[ "${1:-}" = drwx------ ] || exit 1
	listing="$(LC_ALL=C ls -nd "$request_dir" 2>/dev/null)" || exit 1
	set -- $listing
	[ "${3:-}" = 0 ]
)

acmesh_request_file_is_private() (
	request_file="${1:-}"
	[ -n "$request_file" ] || exit 1
	[ -f "$request_file" ] && [ ! -L "$request_file" ] || exit 1
	listing="$(LC_ALL=C ls -ld "$request_file" 2>/dev/null)" || exit 1
	set -- $listing
	[ "${1:-}" = -rw------- ] || exit 1
	listing="$(LC_ALL=C ls -nd "$request_file" 2>/dev/null)" || exit 1
	set -- $listing
	[ "${3:-}" = 0 ]
)

acmesh_request_consume() {
	id="${1:-}"
	if ! acmesh_request_dir_is_private "$ACMESH_REQUEST_DIR"; then
		printf '{"ok":false,"error":"request inbox unavailable"}\n'
		return 1
	fi
	if ! acmesh_request_validate_id "$id"; then
		printf '{"ok":false,"error":"invalid request id"}\n'
		return 2
	fi
	source="$ACMESH_REQUEST_DIR/$id.json"
	if ! acmesh_request_file_is_private "$source"; then
		printf '{"ok":false,"error":"request not found"}\n'
		return 1
	fi
	target="$(umask 077; mktemp "$ACMESH_REQUEST_DIR/.$id.processing.XXXXXX")" || return 1
	if ! acmesh_request_file_is_private "$target"; then
		rm -f "$target"
		return 1
	fi
	if ! acmesh_request_file_is_private "$source" || ! mv "$source" "$target"; then
		rm -f "$target"
		printf '{"ok":false,"error":"request not found"}\n'
		return 1
	fi
	if ! acmesh_request_file_is_private "$target"; then
		rm -f "$target"
		printf '{"ok":false,"error":"request not found"}\n'
		return 1
	fi
	printf '%s\n' "$target"
}
