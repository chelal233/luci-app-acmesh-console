#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"

. "$ACMESH_LIB_DIR/command.sh"

cmd="$(acmesh_build_issue_command /etc/acme example.com ecc dns_cf)"

case "$cmd" in
	*"--home '/etc/acme'"*"--issue"*"--dns 'dns_cf'"*"-d 'example.com'"*"--keylength ec-256"*) ;;
	*) echo "bad command: $cmd"; exit 1 ;;
esac

cmd_ec384="$(acmesh_build_issue_command /etc/acme example.com ec384 dns dns_cf)"
case "$cmd_ec384" in
	*"--dns 'dns_cf'"*"--keylength ec-384"*) ;;
	*) echo "ec384 dns command is wrong: $cmd_ec384"; exit 1 ;;
esac

cmd_rsa4096="$(acmesh_build_issue_command /etc/acme example.com rsa4096 standalone '' '' 8080)"
case "$cmd_rsa4096" in
	*"--standalone"*"--httpport 8080"*"--keylength 4096"*) ;;
	*) echo "rsa4096 standalone command is wrong: $cmd_rsa4096"; exit 1 ;;
esac

cmd_rsa8192="$(acmesh_build_issue_command /etc/acme example.com rsa8192 dns dns_cf)"
case "$cmd_rsa8192" in
	*"--keylength 8192"*) ;;
	*) echo "rsa8192 command is wrong: $cmd_rsa8192"; exit 1 ;;
esac

custom_credentials='CUSTOM_LOGIN=visible
ODD_VARIABLE=custom-secret'
redacted="$(acmesh_redact_credentials "$custom_credentials")"
case "$redacted" in
	*"CUSTOM_LOGIN=***"*"ODD_VARIABLE=***"*) ;;
	*) echo "credential-value redaction is incomplete: $redacted"; exit 1 ;;
esac
case "$redacted" in *visible*|*custom-secret*) echo "custom credential leaked: $redacted"; exit 1;; esac

cmd_webroot="$(acmesh_build_issue_command /etc/acme example.com ec256 webroot '' /www 80)"
case "$cmd_webroot" in
	*"--webroot '/www'"*"--keylength ec-256"*) ;;
	*) echo "webroot command is wrong: $cmd_webroot"; exit 1 ;;
esac

cmd_alpn="$(acmesh_build_issue_command /etc/acme example.com ec521 alpn '' '' 443)"
case "$cmd_alpn" in
	*"--alpn"*"--tlsport 443"*"--keylength ec-521"*) ;;
	*) echo "alpn command is wrong: $cmd_alpn"; exit 1 ;;
esac

cmd_staging="$(acmesh_build_issue_command /etc/acme example.com ec256 dns dns_cf '' '' '' letsencrypt_staging)"
case "$cmd_staging" in
	*"--server 'letsencrypt_test'"*"--dns 'dns_cf'"*"--keylength ec-256"*) ;;
	*) echo "staging command is wrong: $cmd_staging"; exit 1 ;;
esac

cmd_email="$(acmesh_build_issue_command /etc/acme example.com ec256 dns dns_cf '' '' '' letsencrypt user@example.org)"
case "$cmd_email" in
	*"ACCOUNT_EMAIL='user@example.org'"*"--accountemail 'user@example.org'"*"--dns 'dns_cf'"*) ;;
	*) echo "account email command is wrong: $cmd_email"; exit 1 ;;
esac

masked="$(acmesh_mask_secret "CF_Token='abcdef'")"
case "$masked" in
	*"CF_Token='***'"*) ;;
	*) echo "secret was not masked: $masked"; exit 1 ;;
esac

masked_abbrev="$(acmesh_mask_secret "Baidu_AK='public' Baidu_SK='supersecret' LA_Sk='lasecret' ZM_Key='zonomi'")"
case "$masked_abbrev" in
	*"Baidu_AK='public'"*"Baidu_SK='***'"*"LA_Sk='***'"*"ZM_Key='***'"*) ;;
	*) echo "abbreviated DNS secrets were not masked: $masked_abbrev"; exit 1 ;;
esac
case "$masked_abbrev" in
	*"supersecret"*|*"lasecret"*|*"zonomi"*) echo "abbreviated DNS secret leaked: $masked_abbrev"; exit 1 ;;
esac

echo "test_command_builder: ok"
