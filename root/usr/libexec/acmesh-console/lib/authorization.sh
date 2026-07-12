#!/bin/sh

# Canonical material snapshots.  Callers must populate ACMESH_AUTH_* only from
# validated, resolved backend values; browser supplied fingerprints are never
# accepted.
LC_ALL=C
export LC_ALL

if ! command -v acmesh_private_dir >/dev/null 2>&1; then
	. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/io.sh"
fi
if ! command -v acmesh_json_escape >/dev/null 2>&1; then
	. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/json.sh"
fi

: "${ACMESH_AUTH_CANON_VERSION:=1}"
: "${ACMESH_AUTH_ACK_VERSION:=1}"
: "${ACMESH_AUTH_STATE_DIR:=/etc/acmesh-console}"
: "${ACMESH_AUTH_INSTANCE_FILE:=$ACMESH_AUTH_STATE_DIR/instance-id}"

acmesh_canon_safe() {
	! printf '%s' "${1-}" | LC_ALL=C grep -q '[[:cntrl:]]'
}

acmesh_canon_string() {
	key="$1" value="${2-}"
	acmesh_canon_safe "$key$value" || return 2
	printf 's:%s:%s:%s:%s\n' "${#key}" "$key" "${#value}" "$value"
}

acmesh_canon_bool() {
	key="$1" value="$2"
	acmesh_canon_safe "$key" || return 2
	case "$value" in true|1) value=true ;; false|0) value=false ;; *) return 2 ;; esac
	printf 'b:%s:%s\n' "$key" "$value"
}

acmesh_canon_null() {
	acmesh_canon_safe "$1" || return 2
	printf 'n:%s\n' "$1"
}

acmesh_canon_array() {
	key="$1" values="${2-}"
	acmesh_canon_safe "$key" || return 2
	index=0
	printf '%s\n' "$values" | sed '/^$/d' | LC_ALL=C sort -u | while IFS= read -r value; do
		acmesh_canon_safe "$value" || exit 2
		printf 'a:%s:%s:%s:%s\n' "$key" "$index" "${#value}" "$value"
		index=$((index + 1))
	done
}

acmesh_auth_random_id() {
	if [ -r /dev/urandom ]; then
		hexdump -n 16 -v -e '16/1 "%02x" "\n"' /dev/urandom
	else
		printf '%s:%s:%s\n' "$$" "$(date +%s)" "${RANDOM:-0}" | sha256sum | awk '{print substr($1,1,32)}'
	fi
}

acmesh_auth_instance_id() {
	file="$ACMESH_AUTH_INSTANCE_FILE"
	[ ! -L "$file" ] || return 1
	if [ ! -f "$file" ]; then
		dir="${file%/*}"
		acmesh_private_dir "$dir" || return 1
		id="$(acmesh_auth_random_id)" || return 1
		if ! (umask 077; set -C; printf '%s\n' "$id" > "$file") 2>/dev/null; then
			attempt=0
			while [ ! -s "$file" ] && [ "$attempt" -lt 3 ]; do
				attempt=$((attempt + 1))
				sleep 1
			done
		fi
	fi
	[ -f "$file" ] && [ ! -L "$file" ] || return 1
	chmod 600 "$file" || return 1
	id="$(sed -n '1p' "$file")"
	printf '%s\n' "$id" | grep -Eq '^[a-f0-9]{32}$' || return 1
	printf '%s\n' "$id"
}

acmesh_auth_emit_optional() {
	key="$1" value="${2-}"
	if [ -n "$value" ]; then acmesh_canon_string "$key" "$value"; else acmesh_canon_null "$key"; fi
}

acmesh_auth_digest_text() {
	printf '%s' "${1-}" | sha256sum | awk '{print $1}'
}

acmesh_auth_emit_issue() {
	acmesh_canon_string accountId "${ACMESH_AUTH_ACCOUNT_ID-}" || return $?
	acmesh_auth_emit_optional accountEmail "${ACMESH_AUTH_ACCOUNT_EMAIL-}" || return $?
	acmesh_canon_string ca "${ACMESH_AUTH_CA-}" || return $?
	acmesh_canon_string primaryDomain "$(printf '%s' "${ACMESH_AUTH_PRIMARY_DOMAIN-}" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')" || return $?
	acmesh_canon_array domains "$(printf '%s\n' "${ACMESH_AUTH_DOMAINS-}" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')" || return $?
	acmesh_canon_string keyType "${ACMESH_AUTH_KEY_TYPE-}" || return $?
	acmesh_canon_string validationMethod "${ACMESH_AUTH_VALIDATION-}" || return $?
	acmesh_auth_emit_optional dnsApi "${ACMESH_AUTH_DNS_API-}" || return $?
	acmesh_auth_emit_optional credentialMode "${ACMESH_AUTH_CREDENTIAL_MODE-}" || return $?
	acmesh_auth_emit_optional challengeAlias "${ACMESH_AUTH_CHALLENGE_ALIAS-}" || return $?
	acmesh_canon_string dnsSleep "${ACMESH_AUTH_DNS_SLEEP:-0}" || return $?
	acmesh_auth_emit_optional webroot "${ACMESH_AUTH_WEBROOT-}" || return $?
	acmesh_auth_emit_optional listenPort "${ACMESH_AUTH_LISTEN_PORT-}" || return $?
	acmesh_auth_emit_optional deployProfileId "${ACMESH_AUTH_DEPLOY_PROFILE_ID-}" || return $?
	acmesh_auth_emit_optional deployFingerprint "${ACMESH_AUTH_DEPLOY_FINGERPRINT-}" || return $?
	acmesh_canon_bool testMode "${ACMESH_AUTH_TEST_MODE:-false}" || return $?
}

acmesh_auth_emit_deploy() {
	acmesh_canon_string deployType "${ACMESH_AUTH_DEPLOY_TYPE-}" || return $?
	acmesh_canon_string sourceType "${ACMESH_AUTH_SOURCE_TYPE-}" || return $?
	acmesh_auth_emit_optional sourceIdentity "${ACMESH_AUTH_SOURCE_IDENTITY-}" || return $?
	acmesh_auth_emit_optional sourceDigest "${ACMESH_AUTH_SOURCE_DIGEST-}" || return $?
	acmesh_auth_emit_optional keyVariant "${ACMESH_AUTH_KEY_VARIANT-}" || return $?
	if [ "${ACMESH_AUTH_SOURCE_TYPE-}" = paste-pem ]; then
		acmesh_canon_string keyPemDigest "$(acmesh_auth_digest_text "${ACMESH_AUTH_KEY_PEM-}")" || return $?
		acmesh_canon_string fullchainPemDigest "$(acmesh_auth_digest_text "${ACMESH_AUTH_FULLCHAIN_PEM-}")" || return $?
	else
		acmesh_auth_emit_optional sourceKeyFile "${ACMESH_AUTH_SOURCE_KEY_FILE-}" || return $?
		acmesh_auth_emit_optional sourceFullchainFile "${ACMESH_AUTH_SOURCE_FULLCHAIN_FILE-}" || return $?
	fi
	acmesh_auth_emit_optional host "$(printf '%s' "${ACMESH_AUTH_HOST-}" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')" || return $?
	acmesh_canon_string port "${ACMESH_AUTH_PORT:-22}" || return $?
	acmesh_auth_emit_optional user "${ACMESH_AUTH_USER-}" || return $?
	acmesh_auth_emit_optional sshClient "${ACMESH_AUTH_SSH_CLIENT-}" || return $?
	acmesh_auth_emit_optional hostKeyAlgorithm "${ACMESH_AUTH_HOSTKEY_ALGORITHM-}" || return $?
	acmesh_auth_emit_optional hostKeyFingerprint "${ACMESH_AUTH_HOSTKEY_FINGERPRINT-}" || return $?
	acmesh_canon_string keyFile "${ACMESH_AUTH_KEY_FILE-}" || return $?
	acmesh_canon_string fullchainFile "${ACMESH_AUTH_FULLCHAIN_FILE-}" || return $?
	acmesh_auth_emit_optional certFile "${ACMESH_AUTH_CERT_FILE-}" || return $?
	acmesh_auth_emit_optional caFile "${ACMESH_AUTH_CA_FILE-}" || return $?
	acmesh_auth_emit_optional reloadCommand "${ACMESH_AUTH_RELOAD-}" || return $?
	acmesh_auth_emit_optional sudoMode "${ACMESH_AUTH_SUDO_MODE-}" || return $?
	acmesh_auth_emit_optional owner "${ACMESH_AUTH_OWNER-}" || return $?
	acmesh_auth_emit_optional group "${ACMESH_AUTH_GROUP-}" || return $?
	acmesh_auth_emit_optional mode "${ACMESH_AUTH_MODE-}" || return $?
	acmesh_canon_string transactionStrategy "${ACMESH_AUTH_TRANSACTION_STRATEGY:-pair-rollback-v1}" || return $?
}

acmesh_auth_emit_core() {
	acmesh_canon_string sourceRepository "${ACMESH_AUTH_SOURCE_REPOSITORY:-acmesh-official/acme.sh}" || return $?
	acmesh_canon_string acmeHome "${ACMESH_AUTH_ACME_HOME-}" || return $?
	acmesh_canon_string tag "${ACMESH_AUTH_CORE_TAG-}" || return $?
	acmesh_canon_string backupPolicy "${ACMESH_AUTH_BACKUP_POLICY:-rollback-v1}" || return $?
}

acmesh_auth_snapshot() {
	operation="${1:-}" subject_type="${2:-}" subject_id="${3:-}" output="${4:-}"
	[ -n "$operation" ] && [ -n "$subject_type" ] && [ -n "$subject_id" ] && [ -n "$output" ] || return 2
	instance_id="$(acmesh_auth_instance_id)" || return 1
	dir="${output%/*}"; acmesh_private_dir "$dir" || return 1
	tmp="$dir/.${output##*/}.$$.$(date +%s).tmp"
	trap 'rm -f "$tmp"' HUP INT TERM EXIT
	( umask 077
	set -e
	{
		acmesh_canon_string canonicalVersion "$ACMESH_AUTH_CANON_VERSION" || exit $?
		acmesh_canon_string ackVersion "$ACMESH_AUTH_ACK_VERSION" || exit $?
		acmesh_canon_string instanceId "$instance_id" || exit $?
		acmesh_canon_string operation "$operation" || exit $?
		acmesh_canon_string subjectType "$subject_type" || exit $?
		acmesh_canon_string subjectId "$subject_id" || exit $?
		case "$operation" in
			issue|renew) acmesh_auth_emit_issue || exit $? ;;
			deploy|deploy-run) acmesh_auth_emit_deploy || exit $? ;;
			core-install|core-upgrade) acmesh_auth_emit_core || exit $? ;;
			import|import-apply) acmesh_canon_string configDigest "${ACMESH_AUTH_CONFIG_DIGEST-}" && acmesh_canon_string overwriteMode "${ACMESH_AUTH_OVERWRITE_MODE-}" || exit $? ;;
			export|secret-export) acmesh_canon_string configDigest "${ACMESH_AUTH_CONFIG_DIGEST-}" && acmesh_canon_string exportScope "${ACMESH_AUTH_EXPORT_SCOPE-}" || exit $? ;;
			ssh-key-convert) acmesh_canon_string publicIdentityDigest "${ACMESH_AUTH_PUBLIC_IDENTITY_DIGEST-}" && acmesh_canon_string sourceFormat "${ACMESH_AUTH_SOURCE_FORMAT-}" && acmesh_canon_string targetClient "${ACMESH_AUTH_TARGET_CLIENT-}" && acmesh_canon_string targetFormat "${ACMESH_AUTH_TARGET_FORMAT-}" || exit $? ;;
			certificate-revoke|certificate-remove|profile-delete|authorization-revoke) acmesh_canon_string objectIdentity "${ACMESH_AUTH_OBJECT_IDENTITY-}" && acmesh_canon_string variant "${ACMESH_AUTH_VARIANT-}" || exit $? ;;
			*) return 2 ;;
		esac
	} > "$tmp"
	) || { rm -f "$tmp"; trap - HUP INT TERM EXIT; return 1; }
	chmod 600 "$tmp" && mv -f "$tmp" "$output" && chmod 600 "$output" || return 1
	trap - HUP INT TERM EXIT
}

acmesh_auth_fingerprint() {
	snapshot="${1:-}"
	[ -f "$snapshot" ] && [ ! -L "$snapshot" ] || return 2
	printf 'sha256:%s\n' "$(sha256sum "$snapshot" | awk '{print $1}')"
}

acmesh_auth_summary() {
	snapshot="${1:-}" output="${2:-}"
	[ -f "$snapshot" ] && [ -n "$output" ] || return 2
	dir="${output%/*}"; acmesh_private_dir "$dir" || return 1
	operation="$(sed -n 's/^s:[0-9][0-9]*:operation:[0-9][0-9]*://p' "$snapshot")"
	subject_type="$(sed -n 's/^s:[0-9][0-9]*:subjectType:[0-9][0-9]*://p' "$snapshot")"
	subject_id="$(sed -n 's/^s:[0-9][0-9]*:subjectId:[0-9][0-9]*://p' "$snapshot")"
	canonical_version="$(sed -n 's/^s:[0-9][0-9]*:canonicalVersion:[0-9][0-9]*://p' "$snapshot")"
	ack_version="$(sed -n 's/^s:[0-9][0-9]*:ackVersion:[0-9][0-9]*://p' "$snapshot")"
	printf '%s\n' "$canonical_version" | grep -Eq '^[1-9][0-9]*$' || return 2
	printf '%s\n' "$ack_version" | grep -Eq '^[1-9][0-9]*$' || return 2
	fingerprint="$(acmesh_auth_fingerprint "$snapshot")" || return 1
	(umask 077; printf '{"operation":"%s","subjectType":"%s","subjectId":"%s","fingerprint":"%s","canonicalVersion":%s,"ackVersion":%s}\n' \
		"$(acmesh_json_escape "$operation")" \
		"$(acmesh_json_escape "$subject_type")" \
		"$(acmesh_json_escape "$subject_id")" \
		"$(acmesh_json_escape "$fingerprint")" \
		"$canonical_version" "$ack_version" > "$output") || return 1
	chmod 600 "$output"
}
