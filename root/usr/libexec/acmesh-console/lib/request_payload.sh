. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/json.sh"

acmesh_request_payload_validate() {
	path="${1:-}"
	if [ -z "$path" ] || [ ! -f "$path" ] || [ -L "$path" ]; then
		printf '{"ok":false,"error":"invalid request file"}\n'
		return 2
	fi
	if ! command -v jsonfilter >/dev/null 2>&1; then
		printf '{"ok":false,"error":"jsonfilter is required"}\n'
		return 1
	fi
	root_type="$(jsonfilter -i "$path" -t '@' 2>/dev/null)" || {
		printf '{"ok":false,"error":"invalid request json"}\n'
		return 2
	}
	if [ "$root_type" != object ]; then
		printf '{"ok":false,"error":"request payload must be a JSON object"}\n'
		return 2
	fi
	test_mode_type="$(jsonfilter -i "$path" -t '@.testMode' 2>/dev/null || true)"
	case "$test_mode_type" in
		''|boolean) ;;
		*)
			printf '{"ok":false,"error":"request testMode must be a JSON boolean"}\n'
			return 2
			;;
	esac
}

acmesh_request_value() {
	path="$1"
	key="$2"
	default="${3-}"
	value="$(jsonfilter -i "$path" -e "@.$key" 2>/dev/null || true)"
	[ -n "$value" ] && printf '%s\n' "$value" || printf '%s\n' "$default"
}

acmesh_request_lines() {
	path="$1"
	key="$2"
	jsonfilter -i "$path" -e "@.$key[*]" 2>/dev/null || true
}
