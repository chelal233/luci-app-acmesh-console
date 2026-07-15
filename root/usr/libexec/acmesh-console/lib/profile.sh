. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/json.sh"
. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/io.sh"
. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/dns.sh"

acmesh_profile_jshn() { command -v jsonfilter >/dev/null 2>&1 && [ -r /usr/share/libubox/jshn.sh ] || return 1; JSON_PREFIX=; JSON_UNSET=; JSON_SEQ=; JSON_CUR=; . /usr/share/libubox/jshn.sh; }
acmesh_profile_validate_id() { printf '%s\n' "${1:-}" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$'; }
acmesh_profile_allowed_keys() { allowed=" $1 "; shift; for candidate in "$@"; do case "$allowed" in *" $candidate "*) ;; *) return 1;; esac; done; }
acmesh_profile_type() { json_get_type _type "$1" 2>/dev/null || _type=; [ "$_type" = "$2" ]; }
acmesh_profile_string() { key="$1" required="${2:-0}"; json_get_type _type "$key" 2>/dev/null || _type=; [ -z "$_type" ] && [ "$required" = 0 ] && return 0; [ "$_type" = string ] || return 1; json_get_var _value "$key"; [ "$required" = 0 ] || [ -n "$_value" ]; }
acmesh_profile_key_type() { case "$1" in ec256|ec384|ec521|rsa2048|rsa3072|rsa4096|rsa8192) return 0;; *) return 1;; esac; }
acmesh_profile_abs_path() { case "$1" in /*) [ "$1" != / ];; *) return 1;; esac; }
acmesh_profile_single_line() { case "$1" in *"$(printf '\r')"*|*'
'*|*'\n'*|*'\r'*|*'\u0000'*) return 1;; esac; }
acmesh_profile_domain() { acmesh_profile_single_line "$1" && printf '%s\n' "$1" | grep -Eq '^\*?\.?[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$' && case "$1" in *..*|.*|*.) return 1;; esac; }
acmesh_profile_env_name() { printf '%s\n' "$1" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$' || return 1; case "$1" in PATH|ENV|BASH_ENV|IFS|CDPATH|LD_*) return 1;; esac; }
acmesh_profile_port() { case "$1" in *[!0-9]*|'') return 1;; esac; [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }
acmesh_profile_identity() { [ -z "$1" ] || { acmesh_profile_single_line "$1" && printf '%s\n' "$1" | grep -Eq '^[A-Za-z_][A-Za-z0-9_.-]*$'; }; }
acmesh_profile_file_mode() { [ -z "$1" ] || { acmesh_profile_single_line "$1" || return 1; case "$1" in [0-7][0-7][0-7]|0[0-7][0-7][0-7]) return 0;; *) return 1;; esac; }; }

acmesh_profile_install_cleanup_traps() {
	ACMESH_RESOLVED_CLEANUP_FILE="$1"
	trap 'rm -f -- "$ACMESH_RESOLVED_CLEANUP_FILE"' EXIT
	trap 'exit 129' HUP
	trap 'exit 130' INT
	trap 'exit 143' TERM
}

acmesh_profile_validate_global() {
	json_select global || return 1; json_get_keys keys
	# testMode is accepted only as a no-op migration field for existing schema-2 files.
	acmesh_profile_allowed_keys 'defaultAccountEmail testMode coreTag acmeHome' $keys || return 1
	acmesh_profile_string defaultAccountEmail || return 1; acmesh_profile_string coreTag 1 || return 1; acmesh_profile_string acmeHome 1 || return 1
	json_get_var home acmeHome; acmesh_profile_abs_path "$home" || return 1; json_get_type legacy_test_type testMode 2>/dev/null || legacy_test_type=; [ -z "$legacy_test_type" ] || [ "$legacy_test_type" = boolean ] || return 1; json_select ..
}

acmesh_profile_validate_accounts() {
	ids=' '; json_select accountProfiles || return 1; json_get_keys indexes
	for index in $indexes; do json_select "$index" || return 1; json_get_keys keys; acmesh_profile_allowed_keys 'id name ca accountEmail' $keys || return 1; acmesh_profile_string id 1 || return 1; json_get_var id id; acmesh_profile_validate_id "$id" || return 1; case "$ids" in *" $id "*) return 1;; esac; ids="$ids$id "; acmesh_profile_string name || return 1; acmesh_profile_string accountEmail || return 1; acmesh_profile_string ca 1 || return 1; json_get_var ca ca; case "$ca" in letsencrypt|letsencrypt_staging|zerossl|google) ;; *) return 1;; esac; json_select ..; done
	ACMESH_ACCOUNT_IDS="$ids"; json_select ..
}

acmesh_profile_dns_credentials_valid() {
	dns="$1"; mode="$2"; json_get_type ctype credentials 2>/dev/null || ctype=; [ "$ctype" = object ] || return 1; json_select credentials || return 1; json_get_keys credential_keys
	credentials=
	for key in $credential_keys; do
		acmesh_profile_env_name "$key" || return 1; acmesh_profile_string "$key" || return 1; json_get_var value "$key"
		case "$value" in *"$(printf '\r')"*|*'
'*|*'\n'*|*'\r'*|*'\u0000'*) return 1;; esac
		credentials="${credentials}${credentials:+
}$key=$value"
	done
	json_select ..
	acmesh_dns_credential_mode_valid "$dns" "$mode" || return 1
	acmesh_dns_validate_mode_credentials "$dns" "$mode" "$credentials"
}

acmesh_profile_validate_deploys() {
	ids=' '; json_select deployProfiles || return 1; json_get_keys indexes
	for index in $indexes; do
		json_select "$index" || return 1; json_get_keys keys; acmesh_profile_allowed_keys 'id name type certSource domain keyType host user port sshKey sourceKeyFile sourceFullchainFile keyPem fullchainPem keyFile fullchainFile certFile caFile reloadcmd sudoMode owner group mode' $keys || return 1
		acmesh_profile_string id 1 || return 1; json_get_var id id; acmesh_profile_validate_id "$id" || return 1; case "$ids" in *" $id "*) return 1;; esac; ids="$ids$id "
		for key in name domain host user port sshKey sourceKeyFile sourceFullchainFile keyPem fullchainPem keyFile fullchainFile certFile caFile reloadcmd sudoMode owner group mode; do acmesh_profile_string "$key" || return 1; done
		acmesh_profile_string type 1 || return 1; json_get_var type type; case "$type" in local|ssh) ;; *) return 1;; esac
		acmesh_profile_string certSource 1 || return 1; json_get_var source certSource; case "$source" in managed-acme|local-files|paste-pem) ;; *) return 1;; esac
		json_get_var key_type keyType; [ -z "$key_type" ] || acmesh_profile_key_type "$key_type" || return 1
		json_get_var port port; [ -z "$port" ] && port=22; case "$port" in *[!0-9]*|'') return 1;; esac; [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || return 1
		json_get_var sudo_mode sudoMode; case "$sudo_mode" in ''|auto|always|never) ;; *) return 1;; esac
		json_get_var owner owner; json_get_var group group; json_get_var mode mode; acmesh_profile_identity "$owner" || return 1; acmesh_profile_identity "$group" || return 1; acmesh_profile_file_mode "$mode" || return 1
		for path_key in keyFile fullchainFile certFile caFile sshKey sourceKeyFile sourceFullchainFile; do json_get_var path "$path_key"; [ -z "$path" ] || acmesh_profile_abs_path "$path" || return 1; done
		json_get_var key_file keyFile; json_get_var chain_file fullchainFile; [ -n "$key_file" ] && [ -n "$chain_file" ] || return 1
		json_get_var domain domain; json_get_var sourceKeyFile sourceKeyFile; json_get_var sourceFullchainFile sourceFullchainFile; json_get_var keyPem keyPem; json_get_var fullchainPem fullchainPem; json_get_var host host; json_get_var user user; json_get_var ssh_key sshKey; json_get_var cert_file certFile; json_get_var ca_file caFile; json_select ..
		case "$source" in
			managed-acme) [ -n "$domain" ] && [ -z "$sourceKeyFile$sourceFullchainFile$keyPem$fullchainPem" ] || return 1 ;;
			local-files) [ -n "$sourceKeyFile" ] && [ -n "$sourceFullchainFile" ] && [ -z "$domain$key_type$keyPem$fullchainPem$cert_file$ca_file" ] || return 1 ;;
			paste-pem) [ -n "$keyPem" ] && [ -n "$fullchainPem" ] && [ -z "$domain$key_type$sourceKeyFile$sourceFullchainFile$cert_file$ca_file" ] || return 1 ;;
		esac
		case "$type" in local) [ -z "$host$user$ssh_key" ] && [ "$port" = 22 ] && [ -z "$sudo_mode" ] || return 1;; ssh) [ -n "$host" ] && [ -n "$ssh_key" ] && [ -z "$cert_file$ca_file" ] || return 1;; esac
	done
	ACMESH_DEPLOY_IDS="$ids"; json_select ..
}

acmesh_profile_validate_issues() {
	ids=' '; json_select issueProfiles || return 1; json_get_keys indexes
	for index in $indexes; do
		json_select "$index" || return 1; json_get_keys keys; acmesh_profile_allowed_keys 'id name domain domains accountProfileId deployProfileId keyType validationMethod testModeOverride dnsApi credentialMode credentials challengeAlias dnsSleep webroot listenPort' $keys || return 1
		acmesh_profile_string id 1 || return 1; json_get_var id id; acmesh_profile_validate_id "$id" || return 1; case "$ids" in *" $id "*) return 1;; esac; ids="$ids$id "
		for key in name deployProfileId dnsApi credentialMode challengeAlias webroot listenPort; do acmesh_profile_string "$key" || return 1; done
		acmesh_profile_string domain 1 || return 1; acmesh_profile_string accountProfileId 1 || return 1; json_get_var account accountProfileId; case "$ACMESH_ACCOUNT_IDS" in *" $account "*) ;; *) return 1;; esac
		json_get_var deploy deployProfileId; if [ -n "$deploy" ]; then case "$ACMESH_DEPLOY_IDS" in *" $deploy "*) ;; *) return 1;; esac; fi
		acmesh_profile_string keyType 1 || return 1; json_get_var key_type keyType; acmesh_profile_key_type "$key_type" || return 1
		acmesh_profile_string validationMethod 1 || return 1; json_get_var validation validationMethod; case "$validation" in dns|webroot|standalone|alpn) ;; *) return 1;; esac
		acmesh_profile_string testModeOverride 1 || return 1; json_get_var policy testModeOverride; case "$policy" in inherit-global-test-mode|force-test-mode|force-real-mode) ;; *) return 1;; esac
		json_get_var domain domain; acmesh_profile_domain "$domain" || return 1
		json_get_type domains_type domains 2>/dev/null || domains_type=; [ -z "$domains_type" ] || [ "$domains_type" = array ] || return 1
		if [ "$domains_type" = array ]; then json_select domains; json_get_keys domain_indexes; [ -n "$domain_indexes" ] || return 1; seen=' '; first=; for domain_index in $domain_indexes; do json_get_type item_type "$domain_index"; [ "$item_type" = string ] || return 1; json_get_var item "$domain_index"; [ -n "$first" ] || first="$item"; acmesh_profile_domain "$item" || return 1; case "$seen" in *" $item "*) return 1;; esac; seen="$seen$item "; done; [ "$first" = "$domain" ] || return 1; json_select ..; fi
		json_get_type sleep_type dnsSleep 2>/dev/null || sleep_type=; [ -z "$sleep_type" ] || [ "$sleep_type" = int ] || return 1; json_get_var sleep_value dnsSleep; [ -z "$sleep_value" ] || [ "$sleep_value" -ge 0 ] || return 1
		json_get_var dns dnsApi; json_get_var credential_mode credentialMode; json_get_var webroot webroot; json_get_var listen_port listenPort; json_get_var alias challengeAlias
		case "$validation" in
			dns) acmesh_profile_string dnsApi 1 || return 1; printf '%s\n' "$dns" | grep -Eq '^dns_[A-Za-z0-9_]+$' || return 1; acmesh_profile_string credentialMode 1 || return 1; [ -z "$webroot$listen_port" ] || return 1; acmesh_profile_dns_credentials_valid "$dns" "$credential_mode" || return 1 ;;
			webroot) [ -z "$dns$credential_mode$listen_port$alias$sleep_value" ] || return 1; acmesh_profile_abs_path "$webroot" || return 1; json_get_type ctype credentials 2>/dev/null && return 1 || : ;;
			standalone|alpn) [ -z "$dns$credential_mode$webroot$alias$sleep_value" ] || return 1; [ -z "$listen_port" ] || acmesh_profile_port "$listen_port" || return 1; json_get_type ctype credentials 2>/dev/null && return 1 || : ;;
		esac
		json_select ..
	done
	json_select ..
}

acmesh_config_validate_file() (
	set +u
	path="${1:-}"; [ -f "$path" ] && [ ! -L "$path" ] || return 1; acmesh_profile_jshn || return 1
	jsonfilter -i "$path" -e '@' >/dev/null 2>&1 || return 1
	[ "$(jsonfilter -i "$path" -t '@.global' 2>/dev/null)" = object ] || return 1; [ "$(jsonfilter -i "$path" -t '@.accountProfiles' 2>/dev/null)" = array ] || return 1; [ "$(jsonfilter -i "$path" -t '@.issueProfiles' 2>/dev/null)" = array ] || return 1; [ "$(jsonfilter -i "$path" -t '@.deployProfiles' 2>/dev/null)" = array ] || return 1
	json_load_file "$path" >/dev/null 2>&1 || return 1; json_get_keys keys; acmesh_profile_allowed_keys 'schemaVersion global accountProfiles issueProfiles deployProfiles' $keys || return 1
	json_get_type vtype schemaVersion 2>/dev/null || vtype=; case "$vtype" in '') ;; int) json_get_var version schemaVersion; [ "$version" = 2 ] || return 1;; *) return 1;; esac
	acmesh_profile_validate_global && acmesh_profile_validate_accounts && acmesh_profile_validate_deploys && acmesh_profile_validate_issues
)

acmesh_profile_extract() (
	set +u
	kind="$1" id="$2" output="$3"; acmesh_profile_validate_id "$id" || return 2; acmesh_config_validate_file "$ACMESH_CONSOLE_CONFIG" || return 1; acmesh_profile_jshn || return 1
	case "$kind" in account) array=accountProfiles;; issue) array=issueProfiles;; deploy) array=deployProfiles;; *) return 2;; esac
	json_load_file "$ACMESH_CONSOLE_CONFIG" || return 1; json_select "$array"; json_get_keys indexes; found=
	for index in $indexes; do json_select "$index"; json_get_var candidate id; if [ "$candidate" = "$id" ]; then [ -z "$found" ] || return 1; found="$index"; fi; json_select ..; done
	[ -n "$found" ] || return 1; json_index=$((found - 1)); jsonfilter -i "$ACMESH_CONSOLE_CONFIG" -e "@.$array[$json_index]" | acmesh_atomic_write "$output" 600
)

acmesh_profile_resolve_issue() (
	set +u
	id="$1" output="$2"; acmesh_profile_validate_id "$id" || return 2; acmesh_config_validate_file "$ACMESH_CONSOLE_CONFIG" || return 1; acmesh_profile_jshn || return 1; json_load_file "$ACMESH_CONSOLE_CONFIG" || return 1
	json_select global; json_get_var default_email defaultAccountEmail; json_select ..
	json_select issueProfiles; json_get_keys indexes; found=; for index in $indexes; do json_select "$index"; json_get_var candidate id; [ "$candidate" = "$id" ] && found="$index"; json_select ..; done; [ -n "$found" ] || return 1
	json_select "$found"; json_get_var account_id accountProfileId; json_get_var domain domain; json_get_var key_type keyType; json_get_var validation validationMethod; json_get_var dns dnsApi || dns=; json_get_var credential_mode credentialMode || credential_mode=; json_get_var alias challengeAlias || alias=; json_get_var sleep_value dnsSleep || sleep_value=; json_get_var webroot webroot || webroot=; json_get_var listen_port listenPort || listen_port=; json_get_var deploy_id deployProfileId || deploy_id=; json_get_var policy testModeOverride; json_select ..; json_select ..
	account_email="$default_email"; ca=letsencrypt; json_select accountProfiles; json_get_keys indexes; for index in $indexes; do json_select "$index"; json_get_var candidate id; if [ "$candidate" = "$account_id" ]; then json_get_var overlay accountEmail || overlay=; json_get_var ca ca; [ -z "$overlay" ] || account_email="$overlay"; fi; json_select ..; done
	case "$policy" in
		force-test-mode) test_mode=true ;;
		force-real-mode) test_mode=false ;;
		inherit-global-test-mode) test_mode=false ;;
		*) return 1 ;;
	esac
	[ -n "$sleep_value" ] || sleep_value=0
	json_index=$((found - 1)); cred_json="$(jsonfilter -i "$ACMESH_CONSOLE_CONFIG" -e "@.issueProfiles[$json_index].credentials" 2>/dev/null || true)"; [ -n "$cred_json" ] || cred_json='{}'
	domains_json="$(jsonfilter -i "$ACMESH_CONSOLE_CONFIG" -e "@.issueProfiles[$json_index].domains" 2>/dev/null || true)"; [ -n "$domains_json" ] || domains_json="[\"$(acmesh_json_escape "$domain")\"]"
	printf '{"id":"%s","accountId":"%s","accountEmail":"%s","ca":"%s","domains":%s,"keyType":"%s","validationMethod":"%s","dnsApi":"%s","credentialMode":"%s","challengeAlias":"%s","dnsSleep":%s,"webroot":"%s","listenPort":"%s","deployProfileId":"%s","testMode":%s,"credentials":%s}\n' "$(acmesh_json_escape "$id")" "$(acmesh_json_escape "$account_id")" "$(acmesh_json_escape "$account_email")" "$(acmesh_json_escape "$ca")" "$domains_json" "$(acmesh_json_escape "$key_type")" "$(acmesh_json_escape "$validation")" "$(acmesh_json_escape "$dns")" "$(acmesh_json_escape "$credential_mode")" "$(acmesh_json_escape "$alias")" "$sleep_value" "$(acmesh_json_escape "$webroot")" "$(acmesh_json_escape "$listen_port")" "$(acmesh_json_escape "$deploy_id")" "$test_mode" "$cred_json" | acmesh_atomic_write "$output" 600
)

acmesh_profile_resolve_deploy() (
	set +u
	id="$1" output="$2"; tmp="${output}.profile.$$"; trap 'rm -f "$tmp"' EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM; acmesh_profile_extract deploy "$id" "$tmp" || return $?
	type="$(jsonfilter -i "$tmp" -e '@.type')"; source="$(jsonfilter -i "$tmp" -e '@.certSource')"
	domain="$(jsonfilter -i "$tmp" -e '@.domain' 2>/dev/null || true)"; key_type="$(jsonfilter -i "$tmp" -e '@.keyType' 2>/dev/null || true)"
	host="$(jsonfilter -i "$tmp" -e '@.host' 2>/dev/null || true)"; user="$(jsonfilter -i "$tmp" -e '@.user' 2>/dev/null || true)"; port="$(jsonfilter -i "$tmp" -e '@.port' 2>/dev/null || true)"; ssh_key="$(jsonfilter -i "$tmp" -e '@.sshKey' 2>/dev/null || true)"
	source_key="$(jsonfilter -i "$tmp" -e '@.sourceKeyFile' 2>/dev/null || true)"; source_chain="$(jsonfilter -i "$tmp" -e '@.sourceFullchainFile' 2>/dev/null || true)"
	key_pem="$(jsonfilter -i "$tmp" -e '@.keyPem' 2>/dev/null || true)"; chain_pem="$(jsonfilter -i "$tmp" -e '@.fullchainPem' 2>/dev/null || true)"
	key_file="$(jsonfilter -i "$tmp" -e '@.keyFile')"; chain_file="$(jsonfilter -i "$tmp" -e '@.fullchainFile')"
	cert_file="$(jsonfilter -i "$tmp" -e '@.certFile' 2>/dev/null || true)"; ca_file="$(jsonfilter -i "$tmp" -e '@.caFile' 2>/dev/null || true)"
	reload="$(jsonfilter -i "$tmp" -e '@.reloadcmd' 2>/dev/null || true)"; sudo_mode="$(jsonfilter -i "$tmp" -e '@.sudoMode' 2>/dev/null || true)"
	owner="$(jsonfilter -i "$tmp" -e '@.owner' 2>/dev/null || true)"; group="$(jsonfilter -i "$tmp" -e '@.group' 2>/dev/null || true)"; mode="$(jsonfilter -i "$tmp" -e '@.mode' 2>/dev/null || true)"
	digest="$(sha256sum "$ACMESH_CONSOLE_CONFIG" | awk '{print $1}')"; rm -f "$tmp"
	printf '{"id":"%s","source":{"config":"%s","digest":"%s","certSource":"%s","domain":"%s","keyType":"%s","keyFile":"%s","fullchainFile":"%s","keyPem":"%s","fullchainPem":"%s"},"target":{"type":"%s","host":"%s","port":%s,"user":"%s","sshKey":"%s","sudoMode":"%s"},"destinations":{"keyFile":"%s","fullchainFile":"%s","certFile":"%s","caFile":"%s","owner":"%s","group":"%s","mode":"%s"},"reloadCommand":"%s"}\n' \
		"$(acmesh_json_escape "$id")" "$(acmesh_json_escape "$ACMESH_CONSOLE_CONFIG")" "$digest" "$(acmesh_json_escape "$source")" "$(acmesh_json_escape "$domain")" "$(acmesh_json_escape "$key_type")" "$(acmesh_json_escape "$source_key")" "$(acmesh_json_escape "$source_chain")" "$(acmesh_json_escape "$key_pem")" "$(acmesh_json_escape "$chain_pem")" \
		"$(acmesh_json_escape "$type")" "$(acmesh_json_escape "$host")" "${port:-22}" "$(acmesh_json_escape "$user")" "$(acmesh_json_escape "$ssh_key")" "$(acmesh_json_escape "$sudo_mode")" \
		"$(acmesh_json_escape "$key_file")" "$(acmesh_json_escape "$chain_file")" "$(acmesh_json_escape "$cert_file")" "$(acmesh_json_escape "$ca_file")" "$(acmesh_json_escape "$owner")" "$(acmesh_json_escape "$group")" "$(acmesh_json_escape "$mode")" "$(acmesh_json_escape "$reload")" | acmesh_atomic_write "$output" 600
)

acmesh_profile_load_deploy_file() {
	path="$1"
	ACMESH_DEPLOY_TYPE="$(jsonfilter -i "$path" -e '@.target.type')" || return 1
	ACMESH_DEPLOY_CERT_SOURCE="$(jsonfilter -i "$path" -e '@.source.certSource')" || return 1
	ACMESH_DEPLOY_DOMAIN="$(jsonfilter -i "$path" -e '@.source.domain' 2>/dev/null || true)"
	ACMESH_DEPLOY_KEY_TYPE="$(jsonfilter -i "$path" -e '@.source.keyType' 2>/dev/null || true)"
	ACMESH_DEPLOY_SOURCE_KEY="$(jsonfilter -i "$path" -e '@.source.keyFile' 2>/dev/null || true)"
	ACMESH_DEPLOY_SOURCE_CHAIN="$(jsonfilter -i "$path" -e '@.source.fullchainFile' 2>/dev/null || true)"
	ACMESH_DEPLOY_KEY_PEM="$(jsonfilter -i "$path" -e '@.source.keyPem' 2>/dev/null || true)"
	ACMESH_DEPLOY_CHAIN_PEM="$(jsonfilter -i "$path" -e '@.source.fullchainPem' 2>/dev/null || true)"
	ACMESH_DEPLOY_HOST="$(jsonfilter -i "$path" -e '@.target.host' 2>/dev/null || true)"; ACMESH_DEPLOY_PORT="$(jsonfilter -i "$path" -e '@.target.port')"
	ACMESH_DEPLOY_USER="$(jsonfilter -i "$path" -e '@.target.user' 2>/dev/null || true)"; ACMESH_DEPLOY_SSH_KEY="$(jsonfilter -i "$path" -e '@.target.sshKey' 2>/dev/null || true)"
	ACMESH_DEPLOY_KEY_FILE="$(jsonfilter -i "$path" -e '@.destinations.keyFile')" || return 1; ACMESH_DEPLOY_CHAIN_FILE="$(jsonfilter -i "$path" -e '@.destinations.fullchainFile')" || return 1
	ACMESH_DEPLOY_CERT_FILE="$(jsonfilter -i "$path" -e '@.destinations.certFile' 2>/dev/null || true)"; ACMESH_DEPLOY_CA_FILE="$(jsonfilter -i "$path" -e '@.destinations.caFile' 2>/dev/null || true)"
	ACMESH_DEPLOY_RELOAD="$(jsonfilter -i "$path" -e '@.reloadCommand' 2>/dev/null || true)"
	ACMESH_DEPLOY_SUDO_MODE="$(jsonfilter -i "$path" -e '@.target.sudoMode' 2>/dev/null || true)"
	ACMESH_DEPLOY_OWNER="$(jsonfilter -i "$path" -e '@.destinations.owner' 2>/dev/null || true)"
	ACMESH_DEPLOY_GROUP="$(jsonfilter -i "$path" -e '@.destinations.group' 2>/dev/null || true)"
	ACMESH_DEPLOY_MODE="$(jsonfilter -i "$path" -e '@.destinations.mode' 2>/dev/null || true)"
}

acmesh_profile_load_issue_file() {
	set +u
	path="$1"; acmesh_profile_jshn || return 1; json_load_file "$path" || return 1
	json_get_var ACMESH_PROFILE_ACCOUNT_EMAIL accountEmail
	json_get_var ACMESH_PROFILE_CA ca
	json_get_var ACMESH_PROFILE_KEY_TYPE keyType
	json_get_var ACMESH_PROFILE_VALIDATION validationMethod
	json_get_var ACMESH_PROFILE_DNS_API dnsApi || ACMESH_PROFILE_DNS_API=
	json_get_var ACMESH_PROFILE_CREDENTIAL_MODE credentialMode || ACMESH_PROFILE_CREDENTIAL_MODE=
	json_get_var ACMESH_PROFILE_TEST_MODE testMode
	case "$ACMESH_PROFILE_TEST_MODE" in 1|true) ACMESH_PROFILE_TEST_MODE=true;; *) ACMESH_PROFILE_TEST_MODE=false;; esac
	json_get_var ACMESH_PROFILE_WEBROOT webroot || ACMESH_PROFILE_WEBROOT=
	json_get_var ACMESH_PROFILE_LISTEN_PORT listenPort || ACMESH_PROFILE_LISTEN_PORT=
	json_get_var ACMESH_PROFILE_CHALLENGE_ALIAS challengeAlias || ACMESH_PROFILE_CHALLENGE_ALIAS=
	json_get_var ACMESH_PROFILE_DNS_SLEEP dnsSleep || ACMESH_PROFILE_DNS_SLEEP=0
	ACMESH_PROFILE_DOMAINS=; json_select domains; json_get_keys domain_indexes; for domain_index in $domain_indexes; do json_get_var domain_value "$domain_index"; ACMESH_PROFILE_DOMAINS="${ACMESH_PROFILE_DOMAINS}${ACMESH_PROFILE_DOMAINS:+
}$domain_value"; done; json_select ..
	ACMESH_PROFILE_DOMAIN="$(printf '%s\n' "$ACMESH_PROFILE_DOMAINS" | sed -n '1p')"
	ACMESH_PROFILE_CREDENTIALS=
	json_select credentials; json_get_keys credential_keys
	for credential_key in $credential_keys; do
		json_get_var credential_value "$credential_key"
		ACMESH_PROFILE_CREDENTIALS="${ACMESH_PROFILE_CREDENTIALS}${ACMESH_PROFILE_CREDENTIALS:+
}$credential_key=$credential_value"
	done
	json_select ..
}

acmesh_profile_find_linked_deploy() (
	domain="$1" key_type="${2:-}"
	acmesh_config_validate_file "$ACMESH_CONSOLE_CONFIG" || return 1
	acmesh_profile_jshn || return 1; json_load_file "$ACMESH_CONSOLE_CONFIG" || return 1
	json_select issueProfiles; json_get_keys indexes; found=
	for index in $indexes; do
		json_select "$index"; json_get_var candidate domain; json_get_var variant keyType; json_get_var deploy deployProfileId || deploy=
		if [ "$candidate" = "$domain" ] && { [ -z "$key_type" ] || [ "$variant" = "$key_type" ] || { acmesh_key_type_is_ecc "$variant" && acmesh_key_type_is_ecc "$key_type"; }; }; then
			[ -z "$found" ] || return 1; found="$deploy"
		fi
		json_select ..
	done
	[ -n "$found" ] || return 1; printf '%s\n' "$found"
)
