. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/authorization.sh"

# Closed, backend-owned operation router.  Parameters supplied by an RPC are
# used only to select an existing backend object; they are never persisted in a
# challenge and are never trusted by authorization_execute.
acmesh_operation_subject_type() {
	case "$1" in
		issue) printf '%s\n' issueProfile ;;
		renew) printf '%s\n' certificate ;;
		deploy-run) printf '%s\n' deployProfile ;;
		core-install|core-upgrade) printf '%s\n' global ;;
		ssh-key-convert) printf '%s\n' sshKey ;;
		*) return 2 ;;
	esac
}

acmesh_operation_snapshot_reset() {
	unset ACMESH_AUTH_ACCOUNT_ID ACMESH_AUTH_ACCOUNT_EMAIL ACMESH_AUTH_CA ACMESH_AUTH_PRIMARY_DOMAIN ACMESH_AUTH_DOMAINS
	unset ACMESH_AUTH_KEY_TYPE ACMESH_AUTH_VALIDATION ACMESH_AUTH_DNS_API ACMESH_AUTH_CREDENTIAL_MODE ACMESH_AUTH_CREDENTIAL_KEYS ACMESH_AUTH_CHALLENGE_ALIAS
	unset ACMESH_AUTH_DNS_SLEEP ACMESH_AUTH_WEBROOT ACMESH_AUTH_LISTEN_PORT ACMESH_AUTH_DEPLOY_PROFILE_ID ACMESH_AUTH_DEPLOY_FINGERPRINT
	unset ACMESH_AUTH_CERT_IDENTITY_DIGEST ACMESH_AUTH_TEST_MODE ACMESH_AUTH_DEPLOY_TYPE ACMESH_AUTH_SOURCE_TYPE ACMESH_AUTH_SOURCE_IDENTITY
	unset ACMESH_AUTH_SOURCE_DIGEST ACMESH_AUTH_KEY_VARIANT ACMESH_AUTH_SOURCE_KEY_FILE ACMESH_AUTH_SOURCE_FULLCHAIN_FILE ACMESH_AUTH_KEY_PEM
	unset ACMESH_AUTH_FULLCHAIN_PEM ACMESH_AUTH_HOST ACMESH_AUTH_PORT ACMESH_AUTH_USER ACMESH_AUTH_SSH_CLIENT ACMESH_AUTH_HOSTKEY_ALGORITHM
	unset ACMESH_AUTH_HOSTKEY_FINGERPRINT ACMESH_AUTH_KEY_FILE ACMESH_AUTH_FULLCHAIN_FILE ACMESH_AUTH_CERT_FILE ACMESH_AUTH_CA_FILE
	unset ACMESH_AUTH_RELOAD ACMESH_AUTH_SUDO_MODE ACMESH_AUTH_OWNER ACMESH_AUTH_GROUP ACMESH_AUTH_MODE ACMESH_AUTH_ACME_HOME ACMESH_AUTH_CORE_TAG ACMESH_AUTH_CORE_EMAIL
	unset ACMESH_AUTH_PUBLIC_IDENTITY_DIGEST ACMESH_AUTH_SOURCE_FORMAT ACMESH_AUTH_TARGET_CLIENT ACMESH_AUTH_TARGET_FORMAT
	unset ACMESH_OPERATION_USES_ONCE_CONVERSION ACMESH_OPERATION_CONVERSION_FINGERPRINT ACMESH_OPERATION_RESOLVED_FILE
}

acmesh_operation_snapshot_issue() {
	profile_id="$1" out="$2" summary="$3" resolved="$4"
	acmesh_operation_snapshot_reset
	acmesh_profile_resolve_issue "$profile_id" "$resolved" || return 1
	acmesh_profile_load_issue_file "$resolved" || return 1
	ACMESH_AUTH_ACCOUNT_ID="$(jsonfilter -i "$resolved" -e '@.accountId')"
	ACMESH_AUTH_ACCOUNT_EMAIL="$ACMESH_PROFILE_ACCOUNT_EMAIL" ACMESH_AUTH_CA="$ACMESH_PROFILE_CA"
	ACMESH_AUTH_PRIMARY_DOMAIN="$ACMESH_PROFILE_DOMAIN" ACMESH_AUTH_DOMAINS="$ACMESH_PROFILE_DOMAINS"
	ACMESH_AUTH_KEY_TYPE="$ACMESH_PROFILE_KEY_TYPE" ACMESH_AUTH_VALIDATION="$ACMESH_PROFILE_VALIDATION"
	ACMESH_AUTH_DNS_API="$ACMESH_PROFILE_DNS_API" ACMESH_AUTH_CREDENTIAL_MODE="$ACMESH_PROFILE_CREDENTIAL_MODE" ACMESH_AUTH_CHALLENGE_ALIAS="$ACMESH_PROFILE_CHALLENGE_ALIAS"
	ACMESH_AUTH_DNS_SLEEP="$ACMESH_PROFILE_DNS_SLEEP" ACMESH_AUTH_WEBROOT="$ACMESH_PROFILE_WEBROOT"
	ACMESH_AUTH_LISTEN_PORT="$ACMESH_PROFILE_LISTEN_PORT" ACMESH_AUTH_DEPLOY_PROFILE_ID="$(jsonfilter -i "$resolved" -e '@.deployProfileId' 2>/dev/null || true)"
	ACMESH_AUTH_TEST_MODE=false
	issue_deploy_id="$ACMESH_AUTH_DEPLOY_PROFILE_ID" issue_deploy_fingerprint=
	if [ -n "$ACMESH_AUTH_DEPLOY_PROFILE_ID" ]; then
		deploy_snapshot="${out}.linked-deploy" deploy_summary="${out}.linked-summary" deploy_resolved="${out}.linked-resolved"
		acmesh_operation_snapshot_deploy "$ACMESH_AUTH_DEPLOY_PROFILE_ID" "$deploy_snapshot" "$deploy_summary" "$deploy_resolved" || return 1
		issue_deploy_fingerprint="$(acmesh_auth_fingerprint "$deploy_snapshot")"
		# Restore issue fields overwritten while resolving linked deployment.
		acmesh_profile_load_issue_file "$resolved" || return 1
	fi
	ACMESH_AUTH_ACCOUNT_ID="$(jsonfilter -i "$resolved" -e '@.accountId')"
	ACMESH_AUTH_ACCOUNT_EMAIL="$ACMESH_PROFILE_ACCOUNT_EMAIL" ACMESH_AUTH_CA="$ACMESH_PROFILE_CA"
	ACMESH_AUTH_PRIMARY_DOMAIN="$ACMESH_PROFILE_DOMAIN" ACMESH_AUTH_DOMAINS="$ACMESH_PROFILE_DOMAINS"
	ACMESH_AUTH_KEY_TYPE="$ACMESH_PROFILE_KEY_TYPE" ACMESH_AUTH_VALIDATION="$ACMESH_PROFILE_VALIDATION"
	ACMESH_AUTH_DNS_API="$ACMESH_PROFILE_DNS_API" ACMESH_AUTH_CREDENTIAL_MODE="$ACMESH_PROFILE_CREDENTIAL_MODE" ACMESH_AUTH_CHALLENGE_ALIAS="$ACMESH_PROFILE_CHALLENGE_ALIAS"
	ACMESH_AUTH_CREDENTIAL_KEYS="$(printf '%s\n' "$ACMESH_PROFILE_CREDENTIALS" | sed -n 's/=.*//p' | LC_ALL=C sort)"
	ACMESH_AUTH_DNS_SLEEP="$ACMESH_PROFILE_DNS_SLEEP" ACMESH_AUTH_WEBROOT="$ACMESH_PROFILE_WEBROOT"
	ACMESH_AUTH_LISTEN_PORT="$ACMESH_PROFILE_LISTEN_PORT" ACMESH_AUTH_DEPLOY_PROFILE_ID="$issue_deploy_id" ACMESH_AUTH_DEPLOY_FINGERPRINT="$issue_deploy_fingerprint" ACMESH_AUTH_TEST_MODE=false
	export ACMESH_AUTH_ACCOUNT_ID ACMESH_AUTH_ACCOUNT_EMAIL ACMESH_AUTH_CA ACMESH_AUTH_PRIMARY_DOMAIN ACMESH_AUTH_DOMAINS ACMESH_AUTH_KEY_TYPE ACMESH_AUTH_VALIDATION ACMESH_AUTH_DNS_API ACMESH_AUTH_CREDENTIAL_MODE ACMESH_AUTH_CREDENTIAL_KEYS ACMESH_AUTH_CHALLENGE_ALIAS ACMESH_AUTH_DNS_SLEEP ACMESH_AUTH_WEBROOT ACMESH_AUTH_LISTEN_PORT ACMESH_AUTH_DEPLOY_PROFILE_ID ACMESH_AUTH_TEST_MODE
	export ACMESH_AUTH_DEPLOY_FINGERPRINT
	ACMESH_OPERATION_RESOLVED_FILE="$resolved"; export ACMESH_OPERATION_RESOLVED_FILE
	acmesh_auth_snapshot issue issueProfile "$profile_id" "$out" && acmesh_auth_summary "$out" "$summary"
}

acmesh_operation_snapshot_deploy() {
	profile_id="$1" out="$2" summary="$3" resolved="$4"
	acmesh_operation_snapshot_reset
	acmesh_profile_resolve_deploy "$profile_id" "$resolved" || return 1
	acmesh_profile_load_deploy_file "$resolved" || return 1
	if [ "$ACMESH_DEPLOY_TYPE" = ssh ]; then
		hostkey_file="${out}.hostkey"
		if ! acmesh_ssh_verify_pinned_host "$ACMESH_DEPLOY_HOST" "$ACMESH_DEPLOY_PORT" > "$hostkey_file"; then cat "$hostkey_file"; return 4; fi
		ACMESH_AUTH_HOSTKEY_ALGORITHM="$(jsonfilter -i "$hostkey_file" -e '@.algorithm')"
		ACMESH_AUTH_HOSTKEY_FINGERPRINT="$(jsonfilter -i "$hostkey_file" -e '@.fingerprint')"
		if acmesh_ssh_key_is_openssh_private "$ACMESH_DEPLOY_SSH_KEY" && acmesh_ssh_client_is_dropbear; then
			conversion_snapshot="${out}.conversion" conversion_summary="${out}.conversion-summary"
			acmesh_operation_snapshot_conversion "$profile_id" "$conversion_snapshot" "$conversion_summary" "$resolved" || return 1
			conversion_fp="$(acmesh_auth_fingerprint "$conversion_snapshot")"
			if acmesh_auth_is_remembered ssh-key-convert "$conversion_fp"; then :
			elif acmesh_operation_conversion_grant_valid "$profile_id" "$conversion_fp"; then
				ACMESH_OPERATION_USES_ONCE_CONVERSION=1 ACMESH_OPERATION_CONVERSION_FINGERPRINT="$conversion_fp"; export ACMESH_OPERATION_USES_ONCE_CONVERSION ACMESH_OPERATION_CONVERSION_FINGERPRINT
			else ACMESH_OPERATION_CONVERSION_SUBJECT="$profile_id"; export ACMESH_OPERATION_CONVERSION_SUBJECT; return 6; fi
		fi
	fi
	ACMESH_AUTH_DEPLOY_TYPE="$ACMESH_DEPLOY_TYPE" ACMESH_AUTH_SOURCE_TYPE="$ACMESH_DEPLOY_CERT_SOURCE"
	ACMESH_AUTH_SOURCE_IDENTITY="$ACMESH_DEPLOY_DOMAIN" ACMESH_AUTH_KEY_VARIANT="$ACMESH_DEPLOY_KEY_TYPE"
	ACMESH_AUTH_SOURCE_KEY_FILE="$ACMESH_DEPLOY_SOURCE_KEY" ACMESH_AUTH_SOURCE_FULLCHAIN_FILE="$ACMESH_DEPLOY_SOURCE_CHAIN"
	ACMESH_AUTH_KEY_PEM="$ACMESH_DEPLOY_KEY_PEM" ACMESH_AUTH_FULLCHAIN_PEM="$ACMESH_DEPLOY_CHAIN_PEM"
	ACMESH_AUTH_HOST="$ACMESH_DEPLOY_HOST" ACMESH_AUTH_PORT="$ACMESH_DEPLOY_PORT" ACMESH_AUTH_USER="$ACMESH_DEPLOY_USER"
	ACMESH_AUTH_SSH_CLIENT="$(acmesh_ssh_client_type 2>/dev/null || printf unknown)" ACMESH_AUTH_KEY_FILE="$ACMESH_DEPLOY_KEY_FILE" ACMESH_AUTH_FULLCHAIN_FILE="$ACMESH_DEPLOY_CHAIN_FILE"
	ACMESH_AUTH_CERT_FILE="$ACMESH_DEPLOY_CERT_FILE" ACMESH_AUTH_CA_FILE="$ACMESH_DEPLOY_CA_FILE" ACMESH_AUTH_RELOAD="$ACMESH_DEPLOY_RELOAD"
	ACMESH_AUTH_SUDO_MODE="$ACMESH_DEPLOY_SUDO_MODE" ACMESH_AUTH_OWNER="$ACMESH_DEPLOY_OWNER" ACMESH_AUTH_GROUP="$ACMESH_DEPLOY_GROUP" ACMESH_AUTH_MODE="$ACMESH_DEPLOY_MODE"
	export ACMESH_AUTH_DEPLOY_TYPE ACMESH_AUTH_SOURCE_TYPE ACMESH_AUTH_SOURCE_IDENTITY ACMESH_AUTH_KEY_VARIANT ACMESH_AUTH_SOURCE_KEY_FILE ACMESH_AUTH_SOURCE_FULLCHAIN_FILE ACMESH_AUTH_KEY_PEM ACMESH_AUTH_FULLCHAIN_PEM ACMESH_AUTH_HOST ACMESH_AUTH_PORT ACMESH_AUTH_USER ACMESH_AUTH_SSH_CLIENT ACMESH_AUTH_HOSTKEY_ALGORITHM ACMESH_AUTH_HOSTKEY_FINGERPRINT ACMESH_AUTH_KEY_FILE ACMESH_AUTH_FULLCHAIN_FILE ACMESH_AUTH_CERT_FILE ACMESH_AUTH_CA_FILE ACMESH_AUTH_RELOAD ACMESH_AUTH_SUDO_MODE ACMESH_AUTH_OWNER ACMESH_AUTH_GROUP ACMESH_AUTH_MODE
	ACMESH_OPERATION_RESOLVED_FILE="$resolved"; export ACMESH_OPERATION_RESOLVED_FILE
	acmesh_auth_snapshot deploy-run deployProfile "$profile_id" "$out" && acmesh_auth_summary "$out" "$summary"
}

acmesh_operation_snapshot_conversion() {
	profile_id="$1" out="$2" summary="$3" resolved="$4"
	acmesh_operation_snapshot_reset
	[ -f "$resolved" ] || acmesh_profile_resolve_deploy "$profile_id" "$resolved" || return 1
	acmesh_profile_load_deploy_file "$resolved" || return 1
	[ -r "$ACMESH_DEPLOY_SSH_KEY" ] || return 1
	ssh_keygen="${ACMESH_SSH_KEYGEN_BIN:-ssh-keygen}"
	command -v "$ssh_keygen" >/dev/null 2>&1 || { echo "ssh-keygen is required to derive the SSH public identity" >&2; return 127; }
	public_identity="$($ssh_keygen -y -f "$ACMESH_DEPLOY_SSH_KEY" 2>/dev/null)" || return 1
	[ -n "$public_identity" ] || return 1
	ACMESH_AUTH_PUBLIC_IDENTITY_DIGEST="$(printf '%s\n' "$public_identity" | sha256sum | awk '{print $1}')"
	ACMESH_AUTH_SOURCE_FORMAT=openssh-private ACMESH_AUTH_TARGET_CLIENT=dropbear ACMESH_AUTH_TARGET_FORMAT=dropbear-private
	export ACMESH_AUTH_PUBLIC_IDENTITY_DIGEST ACMESH_AUTH_SOURCE_FORMAT ACMESH_AUTH_TARGET_CLIENT ACMESH_AUTH_TARGET_FORMAT
	acmesh_auth_snapshot ssh-key-convert sshKey "$profile_id" "$out" && acmesh_auth_summary "$out" "$summary"
}

acmesh_operation_conversion_grant_path() { printf '%s/.conversion-once.%s\n' "$ACMESH_AUTH_CHALLENGE_DIR" "$1"; }
acmesh_operation_conversion_grant_valid() {
	profile_id="$1" fingerprint="$2" now="$(acmesh_auth_now)" grant="$(acmesh_operation_conversion_grant_path "$profile_id")"
	[ -f "$grant" ] && [ ! -L "$grant" ] && acmesh_private_file_is_secure "$grant" || return 1
	grant_fp="$(sed -n '1p' "$grant")" grant_expiry="$(sed -n '2p' "$grant")"
	case "$grant_expiry" in ''|*[!0-9]*) return 1 ;; esac
	[ "$grant_fp" = "$fingerprint" ] && [ "$now" -lt "$grant_expiry" ]
}
acmesh_operation_consume_conversion_grant() {
	[ "${ACMESH_OPERATION_USES_ONCE_CONVERSION:-0}" = 1 ] || return 0
	grant="$(acmesh_operation_conversion_grant_path "$1")"
	acmesh_operation_conversion_grant_valid "$1" "${ACMESH_OPERATION_CONVERSION_FINGERPRINT:-}" || return 1
	rm -f "$grant"
}

acmesh_operation_convert_key_task() {
	profile_id="$1" resolved="$2"; acmesh_profile_resolve_deploy "$profile_id" "$resolved" || return 1
	acmesh_profile_load_deploy_file "$resolved" || return 1
	ACMESH_DEPLOY_ALLOW_KEY_CONVERT=1 acmesh_deploy_resolve_ssh_key "$ACMESH_DEPLOY_SSH_KEY" 1 || return 1
	acmesh_deploy_cleanup_temp_key
	printf 'Temporary SSH key conversion verified and deleted.\n'
}

acmesh_operation_recompute() {
	operation="$1" subject_type="$2" subject_id="$3" snapshot="$4" summary="$5"
	resolved="${snapshot}.resolved"
	case "$operation:$subject_type" in
		issue:issueProfile) acmesh_operation_snapshot_issue "$subject_id" "$snapshot" "$summary" "$resolved" ;;
		deploy-run:deployProfile) acmesh_operation_snapshot_deploy "$subject_id" "$snapshot" "$summary" "$resolved" ;;
		ssh-key-convert:sshKey) acmesh_operation_snapshot_conversion "$subject_id" "$snapshot" "$summary" "$resolved" ;;
		renew:certificate)
			acmesh_operation_snapshot_reset
			renew_snapshot="$4" renew_summary="$5"
			case "$subject_id" in ecc.*) renew_domain="${subject_id#ecc.}"; renew_variant=ecc;; rsa.*) renew_domain="${subject_id#rsa.}"; renew_variant=rsa;; *) renew_domain="$subject_id"; renew_variant=rsa;; esac
			cert_dir="$ACMESH_ACME_HOME/$renew_domain"; [ "$renew_variant" = ecc ] && cert_dir="${cert_dir}_ecc"
			cert_conf="$cert_dir/$renew_domain.conf"; [ -f "$cert_conf" ] && [ ! -L "$cert_conf" ] || return 1
			renew_ca="$(sed -n "s/^Le_API='\([^']*\)'.*/\1/p" "$cert_conf" | head -n 1)"; [ -n "$renew_ca" ] || renew_ca=letsencrypt
			renew_alt="$(sed -n "s/^Le_Alt='\([^']*\)'.*/\1/p" "$cert_conf" | head -n 1 | tr ',' '\n')"
			renew_key="$(sed -n "s/^Le_Keylength='\([^']*\)'.*/\1/p" "$cert_conf" | head -n 1)"; [ -n "$renew_key" ] || renew_key="$renew_variant"
			renew_webroot="$(sed -n "s/^Le_Webroot='\([^']*\)'.*/\1/p" "$cert_conf" | head -n 1)"
			case "$renew_webroot" in dns_*) renew_validation=dns; renew_dns_api="$renew_webroot" ;; no|standalone) renew_validation=standalone; renew_dns_api= ;; tls_alpn_01) renew_validation=alpn; renew_dns_api= ;; *) renew_validation=webroot; renew_dns_api= ;; esac
			renew_domains="$(printf '%s\n%s\n' "$renew_domain" "$renew_alt")"
			# Certificate bytes and acme.sh renewal timestamps are expected to change
			# after every successful renew and therefore are not authorization identity.
			renew_deploy_id="$(acmesh_profile_find_linked_deploy "$renew_domain" "$renew_key" 2>/dev/null || true)" renew_deploy_fingerprint=
			if [ -n "$renew_deploy_id" ]; then deploy_snapshot="${renew_snapshot}.linked-deploy"; acmesh_operation_snapshot_deploy "$renew_deploy_id" "$deploy_snapshot" "${renew_summary}.linked" "${renew_snapshot}.linked-resolved" || return 1; renew_deploy_fingerprint="$(acmesh_auth_fingerprint "$deploy_snapshot")"; fi
			ACMESH_AUTH_ACCOUNT_ID=certificate ACMESH_AUTH_CA="$renew_ca" ACMESH_AUTH_PRIMARY_DOMAIN="$renew_domain" ACMESH_AUTH_DOMAINS="$renew_domains" ACMESH_AUTH_KEY_TYPE="$renew_key" ACMESH_AUTH_VALIDATION="$renew_validation" ACMESH_AUTH_DNS_API="$renew_dns_api" ACMESH_AUTH_WEBROOT="$renew_webroot" ACMESH_AUTH_DNS_SLEEP=0 ACMESH_AUTH_TEST_MODE=false ACMESH_AUTH_CERT_IDENTITY_DIGEST= ACMESH_AUTH_DEPLOY_PROFILE_ID="$renew_deploy_id" ACMESH_AUTH_DEPLOY_FINGERPRINT="$renew_deploy_fingerprint"
			export ACMESH_AUTH_ACCOUNT_ID ACMESH_AUTH_CA ACMESH_AUTH_PRIMARY_DOMAIN ACMESH_AUTH_DOMAINS ACMESH_AUTH_KEY_TYPE ACMESH_AUTH_VALIDATION ACMESH_AUTH_DNS_API ACMESH_AUTH_WEBROOT ACMESH_AUTH_DNS_SLEEP ACMESH_AUTH_TEST_MODE ACMESH_AUTH_CERT_IDENTITY_DIGEST ACMESH_AUTH_DEPLOY_PROFILE_ID ACMESH_AUTH_DEPLOY_FINGERPRINT
			acmesh_auth_snapshot renew certificate "$subject_id" "$renew_snapshot" && acmesh_auth_summary "$renew_snapshot" "$renew_summary" ;;
		core-install:global|core-upgrade:global)
			acmesh_operation_snapshot_reset
			ACMESH_AUTH_ACME_HOME="$(acmesh_config_string acmeHome /etc/acme)" ACMESH_AUTH_CORE_TAG="$(acmesh_config_string coreTag "${ACMESH_CORE_TAG:-v3.1.4}")" ACMESH_AUTH_CORE_EMAIL="$(acmesh_config_string defaultAccountEmail '')"
			export ACMESH_AUTH_ACME_HOME ACMESH_AUTH_CORE_TAG ACMESH_AUTH_CORE_EMAIL
			acmesh_auth_snapshot "$operation" global "$subject_id" "$snapshot" && acmesh_auth_summary "$snapshot" "$summary" ;;
		*) return 2 ;;
	esac
}

acmesh_operation_admit() {
	operation="$1" subject_type="$2" subject_id="$3" decision="$4"
	case "$operation:$subject_type" in
		issue:issueProfile)
			task_id="$(acmesh_task_create issue-profile)"; workspace="$(acmesh_task_workspace "$task_id")"; task_resolved="$workspace/issue-profile.json"
			[ -f "$ACMESH_OPERATION_RESOLVED_FILE" ] && [ ! -L "$ACMESH_OPERATION_RESOLVED_FILE" ] || return 1
			cp "$ACMESH_OPERATION_RESOLVED_FILE" "$task_resolved" && chmod 600 "$task_resolved" || return 1
			( ACMESH_OPERATION_USE_RESOLVED=1; export ACMESH_OPERATION_USE_RESOLVED; acmesh_task_run "$task_id" issue acme-sh acmesh_run_issue_profile "$subject_id" "$task_resolved" "$ACMESH_ACME_HOME" ) & ;;
		deploy-run:deployProfile)
			acmesh_operation_consume_conversion_grant "$subject_id" || return 1
			task_id="$(acmesh_task_create deploy-profile)"; workspace="$(acmesh_task_workspace "$task_id")"; task_resolved="$workspace/deploy-profile.json"
			[ -f "$ACMESH_OPERATION_RESOLVED_FILE" ] && [ ! -L "$ACMESH_OPERATION_RESOLVED_FILE" ] || return 1
			cp "$ACMESH_OPERATION_RESOLVED_FILE" "$task_resolved" && chmod 600 "$task_resolved" || return 1
			( ACMESH_DEPLOY_ALLOW_KEY_CONVERT=1 ACMESH_OPERATION_USE_RESOLVED=1; export ACMESH_DEPLOY_ALLOW_KEY_CONVERT ACMESH_OPERATION_USE_RESOLVED; acmesh_task_run "$task_id" deploy-run deploy acmesh_run_deploy_profile "$subject_id" "$task_resolved" ) & ;;
		ssh-key-convert:sshKey)
			if [ "$decision" = once ]; then
				tmp="$(acmesh_operation_conversion_grant_path "$subject_id")"; acmesh_private_dir "${tmp%/*}" || return 1
				snapshot="${tmp}.snapshot" summary="${tmp}.summary" resolved="${tmp}.resolved"
				acmesh_operation_snapshot_conversion "$subject_id" "$snapshot" "$summary" "$resolved" || return 1
				fp="$(acmesh_auth_fingerprint "$snapshot")"; expires=$(( $(acmesh_auth_now) + 300 ))
				printf '%s\n%s\n' "$fp" "$expires" | acmesh_atomic_write "$tmp" 600 || return 1
				rm -f "$snapshot" "$summary" "$resolved"
			fi
			ACMESH_OPERATION_TASK_ID=; export ACMESH_OPERATION_TASK_ID; return 0 ;;
		renew:certificate)
			task_id="$(acmesh_task_create renew)"; workspace="$(acmesh_task_workspace "$task_id")"
			( acmesh_task_run "$task_id" renew acme-sh acmesh_operation_run_renew "$subject_id" "$ACMESH_OPERATION_FINGERPRINT" "$workspace" ) & ;;
		core-install:global) task_id="$(acmesh_task_create core-install)"; ( acmesh_task_run "$task_id" core-install install acmesh_execute_core_install "$ACMESH_AUTH_ACME_HOME" "$ACMESH_AUTH_CORE_EMAIL" "$ACMESH_AUTH_CORE_TAG" ) & ;;
		core-upgrade:global) task_id="$(acmesh_task_create core-upgrade)"; ( acmesh_task_run "$task_id" core-upgrade upgrade acmesh_execute_core_upgrade "$ACMESH_AUTH_ACME_HOME" "$ACMESH_AUTH_CORE_TAG" ) & ;;
		*) return 2 ;;
	esac
	ACMESH_OPERATION_TASK_ID="$task_id"
	export ACMESH_OPERATION_TASK_ID
}

acmesh_operation_run_renew() {
	subject_id="$1" expected="$2" workspace="$3"
	lock_id="$(printf '%s\n' "$ACMESH_ACME_HOME:$subject_id" | sha256sum | awk '{print $1}')"
	acmesh_lock_run "${ACMESH_RUNTIME_DIR:-/var/run/acmesh-console}/renew-locks/$lock_id.lock" acmesh_operation_run_renew_locked "$subject_id" "$expected" "$workspace"
}

acmesh_operation_run_renew_locked() {
	subject_id="$1" expected="$2" workspace="$3"
	snapshot="$workspace/renew-final.snapshot" summary="$workspace/renew-final-summary.json"
	acmesh_operation_recompute renew certificate "$subject_id" "$snapshot" "$summary" || return 1
	[ "$(acmesh_auth_fingerprint "$snapshot")" = "$expected" ] || { echo "renew authorization identity changed before execution" >&2; return 1; }
	case "$subject_id" in ecc.*) renew_domain="${subject_id#ecc.}"; renew_key=ecc;; rsa.*) renew_domain="${subject_id#rsa.}"; renew_key=rsa;; *) renew_domain="$subject_id"; renew_key=rsa;; esac
	acmesh_execute_renew "$ACMESH_ACME_HOME" "$renew_domain" "$renew_key"
}

acmesh_operation_is_remembered() {
	operation="$1" subject_type="$2" subject_id="$3"
	[ "$(acmesh_operation_subject_type "$operation")" = "$subject_type" ] || return 2
	tmp="${ACMESH_AUTH_CHALLENGE_DIR}/.check.$$.$(date +%s)"; acmesh_private_dir "$tmp" || return 1
	rc=0; acmesh_operation_recompute "$operation" "$subject_type" "$subject_id" "$tmp/snapshot" "$tmp/summary" || rc=$?
	if [ "$rc" = 0 ]; then fingerprint="$(acmesh_auth_fingerprint "$tmp/snapshot")" || rc=$?; fi
	if [ "$rc" = 0 ]; then acmesh_auth_is_remembered "$operation" "$fingerprint" || rc=$?; fi
	rm -rf "$tmp"
	return "$rc"
}

acmesh_operation_start() {
	op_start_operation="$1" op_start_subject_type="$2" op_start_subject_id="$3" op_start_parameters_file="${4:-}"
	[ "$(acmesh_operation_subject_type "$op_start_operation")" = "$op_start_subject_type" ] || return 2
	op_start_tmp="${ACMESH_AUTH_CHALLENGE_DIR}/.prepare.$$.$(date +%s)"; acmesh_private_dir "$op_start_tmp" || return 1
	trap 'rm -rf "$op_start_tmp"' HUP INT TERM EXIT
	ACMESH_AUTH_RECOMPUTE_CALLBACK=acmesh_operation_recompute ACMESH_AUTH_ADMIT_CALLBACK=acmesh_operation_admit
	ACMESH_AUTH_REQUIRE_REMEMBERED="${ACMESH_OPERATION_REQUIRE_REMEMBERED:-0}"
	export ACMESH_AUTH_RECOMPUTE_CALLBACK ACMESH_AUTH_ADMIT_CALLBACK ACMESH_AUTH_REQUIRE_REMEMBERED
	recompute_rc=0; acmesh_operation_recompute "$op_start_operation" "$op_start_subject_type" "$op_start_subject_id" "$op_start_tmp/snapshot" "$op_start_tmp/summary" || recompute_rc=$?
	if [ "$recompute_rc" = 6 ]; then
		rm -rf "$op_start_tmp"; trap - HUP INT TERM EXIT
		acmesh_operation_start ssh-key-convert sshKey "${ACMESH_OPERATION_CONVERSION_SUBJECT:-$op_start_subject_id}" "$op_start_parameters_file"; return $?
	fi
	[ "$recompute_rc" = 0 ] || return "$recompute_rc"
	rc=0; acmesh_auth_prepare "$op_start_operation" "$op_start_subject_type" "$op_start_subject_id" "$op_start_tmp/snapshot" "$op_start_tmp/summary" > "$op_start_tmp/response" || rc=$?
	if [ "$rc" = 0 ]; then printf '{"ok":true,"taskId":"%s"}\n' "$(acmesh_json_escape "$ACMESH_OPERATION_TASK_ID")"; else cat "$op_start_tmp/response"; fi
	rm -rf "$op_start_tmp"; trap - HUP INT TERM EXIT
	return "$rc"
}

acmesh_operation_execute_challenge() {
	request_file="$1"
	challenge_id="$(acmesh_request_value "$request_file" challengeId '')" decision="$(acmesh_request_value "$request_file" decision '')"
	acmesh_auth_valid_id "$challenge_id" || { printf '{"ok":false,"error":"invalid authorization challenge"}\n'; return 2; }
	case "$decision" in once|remember) ;; *) printf '{"ok":false,"error":"invalid authorization decision"}\n'; return 2 ;; esac
	ACMESH_AUTH_RECOMPUTE_CALLBACK=acmesh_operation_recompute ACMESH_AUTH_ADMIT_CALLBACK=acmesh_operation_admit
	export ACMESH_AUTH_RECOMPUTE_CALLBACK ACMESH_AUTH_ADMIT_CALLBACK
	tmp="${ACMESH_AUTH_CHALLENGE_DIR}/.execute.$$.$(date +%s)"; acmesh_private_dir "$tmp" || return 1
	rc=0; acmesh_auth_execute "$challenge_id" "$decision" > "$tmp/response" || rc=$?
	if [ "$rc" = 0 ] && [ "${ACMESH_AUTH_EXECUTED_OPERATION:-}" = ssh-key-convert ]; then
		rm -rf "$tmp"; acmesh_operation_start deploy-run deployProfile "$ACMESH_AUTH_EXECUTED_SUBJECT_ID" "$request_file"; return $?
	elif [ "$rc" = 0 ]; then printf '{"ok":true,"authorized":true,"taskId":"%s"}\n' "$(acmesh_json_escape "$ACMESH_OPERATION_TASK_ID")"; else cat "$tmp/response"; fi
	rm -rf "$tmp"
	return "$rc"
}
