. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/json.sh"

acmesh_conf_is_secret_key() {
	case "$1" in
		Le_Keylength)
			return 1
			;;
	esac
	case "$1" in
		*Token*|*TOKEN*|*token*|*Key*|*KEY*|*key*|*Secret*|*SECRET*|*secret*|*Password*|*PASSWORD*|*password*|*Authorization*|*AUTHORIZATION*|*authorization*|*Credential*|*CREDENTIAL*|*credential*|*_SK|*_Sk|*_sk)
			return 0
			;;
	esac
	return 1
}

acmesh_parse_kv_file() {
	file="$1"
	first=1
	printf '{'
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
			''|'#'*) continue ;;
			*=*)
				key=${line%%=*}
				value=${line#*=}
				case "$value" in
					\'*\') value=${value#\'}; value=${value%\'} ;;
					\"*\") value=${value#\"}; value=${value%\"} ;;
				esac
				if acmesh_conf_is_secret_key "$key"; then
					value="***"
				fi
				[ "$first" = 1 ] || printf ','
				first=0
				printf '"%s":"%s"' "$(acmesh_json_escape "$key")" "$(acmesh_json_escape "$value")"
				;;
		esac
	done < "$file"
	printf '}\n'
}
