. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/json.sh"

acmesh_dns_credential_value() {
	credentials="${1:-}"
	name="$2"
	[ -n "$credentials" ] || return 1
	printf '%s\n' "$credentials" | while IFS= read -r cred; do
		case "$cred" in
			"$name="*)
				printf '%s\n' "${cred#*=}"
				exit 0
				;;
		esac
	done
}

acmesh_dns_credential_present() {
	value="$(acmesh_dns_credential_value "$1" "$2" 2>/dev/null || true)"
	[ -n "$value" ] || return 1
	case "$value" in
		-|none|null|NONE|NULL) return 1 ;;
	esac
	return 0
}

acmesh_dns_print_credentials() {
	credentials="${1:-}"
	[ -n "$credentials" ] || {
		printf '  (none)\n'
		return 0
	}
	printf '%s\n' "$credentials" | while IFS= read -r cred; do
		[ -n "$cred" ] || continue
		case "$cred" in
			*=*)
				name="${cred%%=*}"
				value="${cred#*=}"
				[ -n "$value" ] && value="***"
				[ -n "$value" ] || value="(empty)"
				printf '  %s=%s\n' "$name" "$value"
				;;
		esac
	done
}

acmesh_dns_require_any() {
	credentials="$1"
	label="$2"
	shift 2
	for env in "$@"; do
		if acmesh_dns_credential_present "$credentials" "$env"; then
			printf 'OK: %s uses %s.\n' "$label" "$env"
			return 0
		fi
	done
	printf 'ERROR: %s requires one of: %s.\n' "$label" "$*"
	return 1
}

acmesh_dns_require_all() {
	credentials="$1"
	label="$2"
	shift 2
	missing=""
	for env in "$@"; do
		if ! acmesh_dns_credential_present "$credentials" "$env"; then
			missing="${missing}${missing:+ }$env"
		fi
	done
	if [ -n "$missing" ]; then
		printf 'ERROR: %s missing required credential(s): %s.\n' "$label" "$missing"
		return 1
	fi
	printf 'OK: %s required credentials are present: %s.\n' "$label" "$*"
	return 0
}

acmesh_dns_check_cloudflare() {
	credentials="$1"
	rc=0
	token=0
	global=0
	acmesh_dns_credential_present "$credentials" CF_Token && token=1
	if acmesh_dns_credential_present "$credentials" CF_Email || acmesh_dns_credential_present "$credentials" CF_Key; then
		global=1
	fi
	if [ "$token" = 1 ] && [ "$global" = 1 ]; then
		printf 'WARN: Cloudflare token mode and global-key mode are both filled; choose one mode to avoid acme.sh ambiguity.\n'
	fi
	if [ "$token" = 1 ]; then
		printf 'OK: Cloudflare token mode selected; CF_Token is present.\n'
		if acmesh_dns_credential_present "$credentials" CF_Zone_ID; then
			printf 'OK: CF_Zone_ID is set and will be submitted.\n'
		else
			printf 'OK: CF_Zone_ID is empty; it is optional and will not be submitted.\n'
		fi
		if acmesh_dns_credential_present "$credentials" CF_Account_ID; then
			printf 'OK: CF_Account_ID is set and will be submitted.\n'
		else
			printf 'OK: CF_Account_ID is empty; it is optional and will not be submitted.\n'
		fi
		return 0
	fi
	if [ "$global" = 1 ]; then
		acmesh_dns_require_all "$credentials" "Cloudflare global-key mode" CF_Email CF_Key || rc=1
		return "$rc"
	fi
	printf 'ERROR: Cloudflare requires either CF_Token, or CF_Email plus CF_Key.\n'
	return 1
}

acmesh_dns_check_azure() {
	credentials="$1"
	if acmesh_dns_credential_present "$credentials" AZUREDNS_MANAGEDIDENTITY; then
		acmesh_dns_require_all "$credentials" "Azure managed identity mode" AZUREDNS_SUBSCRIPTIONID AZUREDNS_MANAGEDIDENTITY
		return $?
	fi
	if acmesh_dns_credential_present "$credentials" AZUREDNS_BEARERTOKEN; then
		acmesh_dns_require_all "$credentials" "Azure bearer-token mode" AZUREDNS_SUBSCRIPTIONID AZUREDNS_BEARERTOKEN
		return $?
	fi
	acmesh_dns_require_all "$credentials" "Azure service-principal mode" AZUREDNS_SUBSCRIPTIONID AZUREDNS_TENANTID AZUREDNS_APPID AZUREDNS_CLIENTSECRET
}

acmesh_dns_check_cloudns() {
	credentials="$1"
	if acmesh_dns_credential_present "$credentials" CLOUDNS_SUB_AUTH_ID; then
		acmesh_dns_require_all "$credentials" "ClouDNS sub-auth mode" CLOUDNS_SUB_AUTH_ID CLOUDNS_AUTH_PASSWORD
		return $?
	fi
	acmesh_dns_require_all "$credentials" "ClouDNS regular-auth mode" CLOUDNS_AUTH_ID CLOUDNS_AUTH_PASSWORD
}

acmesh_dns_check_dnsla() {
	credentials="$1"
	if acmesh_dns_credential_present "$credentials" LA_Token; then
		acmesh_dns_require_all "$credentials" "DNS.LA token mode" LA_Token
		return $?
	fi
	acmesh_dns_require_all "$credentials" "DNS.LA id-secret mode" LA_Id LA_Sk
}

acmesh_dns_credential_mode_valid() {
	case "$1:$2" in
		dns_cf:token|dns_cf:global-key|dns_ali:access-key|dns_dp:token|dns_tencent:secret|dns_duckdns:token|dns_cloudns:regular-auth|dns_cloudns:sub-auth|dns_dynv6:token|dns_dynv6:ssh-key|dns_gd:key-secret|dns_gcore:api-key|dns_aws:access-key|dns_baidu:access-key|dns_azure:service-principal|dns_azure:bearer-token|dns_azure:managed-identity|dns_he:password|dns_huaweicloud:password|dns_namecheap:api-key|dns_la:id-secret|dns_la:token|dns_namecom:api-token|dns_namesilo:api-key|dns_nsone:api-key|dns_porkbun:api-key|dns_volcengine:access-key|dns_spaceship:api-key|dns_vercel:api-token|dns_linode_v4:token|dns_dgon:token|dns_gcloud:gcloud|dns_zonomi:api-key) return 0 ;;
		dns_*:custom) return 0 ;;
		*) return 1 ;;
	esac
}

acmesh_dns_validate_mode_credentials() {
	dns_api="$1" mode="$2" credentials="$3"
	case "$dns_api:$mode" in
		dns_cf:token) acmesh_dns_require_all "$credentials" "Cloudflare token mode" CF_Token >/dev/null && ! acmesh_dns_credential_present "$credentials" CF_Key && ! acmesh_dns_credential_present "$credentials" CF_Email ;;
		dns_cf:global-key) acmesh_dns_require_all "$credentials" "Cloudflare global-key mode" CF_Email CF_Key >/dev/null && ! acmesh_dns_credential_present "$credentials" CF_Token ;;
		dns_azure:service-principal) acmesh_dns_require_all "$credentials" "Azure service-principal mode" AZUREDNS_SUBSCRIPTIONID AZUREDNS_TENANTID AZUREDNS_APPID AZUREDNS_CLIENTSECRET >/dev/null && ! acmesh_dns_credential_present "$credentials" AZUREDNS_MANAGEDIDENTITY && ! acmesh_dns_credential_present "$credentials" AZUREDNS_BEARERTOKEN ;;
		dns_azure:managed-identity) acmesh_dns_require_all "$credentials" "Azure managed identity mode" AZUREDNS_SUBSCRIPTIONID AZUREDNS_MANAGEDIDENTITY >/dev/null && ! acmesh_dns_credential_present "$credentials" AZUREDNS_TENANTID && ! acmesh_dns_credential_present "$credentials" AZUREDNS_APPID && ! acmesh_dns_credential_present "$credentials" AZUREDNS_CLIENTSECRET && ! acmesh_dns_credential_present "$credentials" AZUREDNS_BEARERTOKEN ;;
		dns_azure:bearer-token) acmesh_dns_require_all "$credentials" "Azure bearer-token mode" AZUREDNS_SUBSCRIPTIONID AZUREDNS_BEARERTOKEN >/dev/null && ! acmesh_dns_credential_present "$credentials" AZUREDNS_MANAGEDIDENTITY && ! acmesh_dns_credential_present "$credentials" AZUREDNS_TENANTID && ! acmesh_dns_credential_present "$credentials" AZUREDNS_APPID && ! acmesh_dns_credential_present "$credentials" AZUREDNS_CLIENTSECRET ;;
		dns_cloudns:regular-auth) acmesh_dns_require_all "$credentials" "ClouDNS regular mode" CLOUDNS_AUTH_ID CLOUDNS_AUTH_PASSWORD >/dev/null && ! acmesh_dns_credential_present "$credentials" CLOUDNS_SUB_AUTH_ID ;;
		dns_cloudns:sub-auth) acmesh_dns_require_all "$credentials" "ClouDNS sub mode" CLOUDNS_SUB_AUTH_ID CLOUDNS_AUTH_PASSWORD >/dev/null && ! acmesh_dns_credential_present "$credentials" CLOUDNS_AUTH_ID ;;
		dns_dynv6:token) acmesh_dns_require_all "$credentials" "dynv6 token mode" DYNV6_TOKEN >/dev/null && ! acmesh_dns_credential_present "$credentials" KEY ;;
		dns_dynv6:ssh-key) acmesh_dns_require_all "$credentials" "dynv6 SSH key mode" KEY >/dev/null && ! acmesh_dns_credential_present "$credentials" DYNV6_TOKEN ;;
		dns_la:id-secret) acmesh_dns_require_all "$credentials" "DNS.LA id-secret mode" LA_Id LA_Sk >/dev/null && ! acmesh_dns_credential_present "$credentials" LA_Token ;;
		dns_la:token) acmesh_dns_require_all "$credentials" "DNS.LA token mode" LA_Token >/dev/null && ! acmesh_dns_credential_present "$credentials" LA_Id && ! acmesh_dns_credential_present "$credentials" LA_Sk ;;
		*) acmesh_dns_validate_credentials "$dns_api" "$credentials" >/dev/null 2>&1 ;;
	esac
}

acmesh_dns_validate_credentials() {
	dns_api="$1"
	credentials="$2"
	case "$dns_api" in
		dns_cf) acmesh_dns_check_cloudflare "$credentials" ;;
		dns_ali) acmesh_dns_require_all "$credentials" Aliyun Ali_Key Ali_Secret ;;
		dns_baidu) acmesh_dns_require_all "$credentials" "Baidu Cloud DNS" Baidu_AK Baidu_SK ;;
		dns_cloudns) acmesh_dns_check_cloudns "$credentials" ;;
		dns_dp) acmesh_dns_require_all "$credentials" DNSPod DP_Id DP_Key ;;
		dns_tencent) acmesh_dns_require_all "$credentials" "Tencent Cloud DNSPod" Tencent_SecretId Tencent_SecretKey ;;
		dns_duckdns) acmesh_dns_require_all "$credentials" DuckDNS DuckDNS_Token ;;
		dns_dynv6) acmesh_dns_require_any "$credentials" dynv6 DYNV6_TOKEN KEY ;;
		dns_gd) acmesh_dns_require_all "$credentials" GoDaddy GD_Key GD_Secret ;;
		dns_aws) acmesh_dns_require_all "$credentials" "Amazon Route 53" AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY ;;
		dns_azure) acmesh_dns_check_azure "$credentials" ;;
		dns_he) acmesh_dns_require_all "$credentials" "Hurricane Electric" HE_Username HE_Password ;;
		dns_huaweicloud) acmesh_dns_require_all "$credentials" "Huawei Cloud DNS" HUAWEICLOUD_Username HUAWEICLOUD_Password HUAWEICLOUD_DomainName ;;
		dns_gcore) acmesh_dns_require_all "$credentials" "Gcore DNS" GCORE_Key ;;
		dns_la) acmesh_dns_check_dnsla "$credentials" ;;
		dns_namecheap) acmesh_dns_require_all "$credentials" Namecheap NAMECHEAP_USERNAME NAMECHEAP_API_KEY NAMECHEAP_SOURCEIP ;;
		dns_namecom) acmesh_dns_require_all "$credentials" "Name.com" Namecom_Username Namecom_Token ;;
		dns_namesilo) acmesh_dns_require_all "$credentials" NameSilo Namesilo_Key ;;
		dns_nsone) acmesh_dns_require_all "$credentials" "IBM NS1 Connect" NS1_Key ;;
		dns_porkbun) acmesh_dns_require_all "$credentials" Porkbun PORKBUN_API_KEY PORKBUN_SECRET_API_KEY ;;
		dns_volcengine) acmesh_dns_require_all "$credentials" "Volcengine DNS" Volcengine_ACCESS_KEY_ID Volcengine_SECRET_ACCESS_KEY ;;
		dns_spaceship) acmesh_dns_require_all "$credentials" Spaceship SPACESHIP_API_KEY SPACESHIP_API_SECRET ;;
		dns_vercel) acmesh_dns_require_all "$credentials" Vercel VERCEL_TOKEN ;;
		dns_linode_v4) acmesh_dns_require_all "$credentials" Linode LINODE_V4_API_KEY ;;
		dns_dgon) acmesh_dns_require_all "$credentials" DigitalOcean DO_API_KEY ;;
		dns_gcloud)
			printf 'OK: Google Cloud DNS uses the active gcloud configuration; CLOUDSDK_ACTIVE_CONFIG_NAME is optional.\n'
			;;
		dns_zonomi) acmesh_dns_require_all "$credentials" Zonomi ZM_Key ;;
		dns_*)
			printf 'WARN: Custom DNS API %s is not known by the console template; only command shape can be checked.\n' "$dns_api"
			;;
		*)
			printf 'ERROR: DNS API must look like dns_xxx, got: %s.\n' "$dns_api"
			return 1
			;;
	esac
}

acmesh_dns_test_log() {
	domain="$1"
	dns_api="$2"
	credentials="$(acmesh_sanitize_credentials "${3:-}")"
	test_mode="${4:-1}"

	[ -n "$domain" ] || { echo "domain is required" >&2; return 1; }
	[ -n "$dns_api" ] || dns_api="dns_cf"

	printf 'DNS API diagnostic\n'
	if [ "$test_mode" = 1 ] || [ "$test_mode" = true ]; then
		printf 'TEST MODE: no real DNS record will be created or removed.\n'
	else
		printf 'REAL MODE: live DNS mutation is not enabled by this diagnostic yet; run issue for a real acme.sh DNS transaction.\n'
	fi
	printf 'Domain: %s\n' "$domain"
	printf 'Provider: %s\n' "$dns_api"
	printf 'Credentials:\n'
	acmesh_dns_print_credentials "$credentials"
	printf 'Findings:\n'
	acmesh_dns_validate_credentials "$dns_api" "$credentials"
}
