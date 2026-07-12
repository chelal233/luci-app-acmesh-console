. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/conf.sh"
. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/json.sh"

acmesh_key_type_from_dir() {
	case "$1" in
		*_ecc) printf 'ecc' ;;
		*) printf 'rsa' ;;
	esac
}

acmesh_main_domain_from_dir() {
	base=${1##*/}
	case "$base" in
		*_ecc) printf '%s' "${base%_ecc}" ;;
		*) printf '%s' "$base" ;;
	esac
}

acmesh_scan_home() {
	home="$1"
	first=1
	printf '{"ok":true,"home":"%s","certificates":[' "$(acmesh_json_escape "$home")"
	for dir in "$home"/*; do
		[ -d "$dir" ] || continue
		main="$(acmesh_main_domain_from_dir "$dir")"
		conf="$dir/$main.conf"
		[ -f "$conf" ] || continue
		key_type="$(acmesh_key_type_from_dir "$dir")"
		raw="$(acmesh_parse_kv_file "$conf")"
		[ "$first" = 1 ] || printf ','
		first=0
		printf '{"mainDomain":"%s","keyType":"%s","domainConf":"%s","rawVars":%s}' \
			"$(acmesh_json_escape "$main")" \
			"$(acmesh_json_escape "$key_type")" \
			"$(acmesh_json_escape "$conf")" \
			"$raw"
	done
	printf ']}\n'
}
