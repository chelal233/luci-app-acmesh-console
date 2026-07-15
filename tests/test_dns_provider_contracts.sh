#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
. "$ACMESH_LIB_DIR/json.sh"
. "$ROOT/tests/lib/cli_request.sh"
OPS="$ROOT/htdocs/luci-static/resources/view/acmesh/operations_v2.js"
PROVIDER="$ROOT/root/usr/libexec/acmesh-console/lib/provider.sh"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"

require_text() {
	file="$1"
	needle="$2"
	if ! grep -Fq -- "$needle" "$file"; then
		echo "missing provider contract item in $file: $needle"
		exit 1
	fi
}

# Keep this list aligned with acmesh-official/acme.sh dnsapi/*_info blocks.
for item in \
	"dns_cf CF_Token CF_Account_ID CF_Zone_ID CF_Key CF_Email" \
	"dns_ali Ali_Key Ali_Secret" \
	"dns_dp DP_Id DP_Key" \
	"dns_tencent Tencent_SecretId Tencent_SecretKey" \
	"dns_duckdns DuckDNS_Token" \
	"dns_dynv6 DYNV6_TOKEN KEY" \
	"dns_gd GD_Key GD_Secret" \
	"dns_aws AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DNS_SLOWRATE" \
	"dns_baidu Baidu_AK Baidu_SK Baidu_API_Preference Baidu_View Baidu_Line" \
	"dns_azure AZUREDNS_SUBSCRIPTIONID AZUREDNS_TENANTID AZUREDNS_APPID AZUREDNS_CLIENTSECRET AZUREDNS_MANAGEDIDENTITY AZUREDNS_BEARERTOKEN" \
	"dns_cloudns CLOUDNS_AUTH_ID CLOUDNS_SUB_AUTH_ID CLOUDNS_AUTH_PASSWORD" \
	"dns_he HE_Username HE_Password" \
	"dns_huaweicloud HUAWEICLOUD_Username HUAWEICLOUD_Password HUAWEICLOUD_DomainName HUAWEICLOUD_Region" \
	"dns_gcore GCORE_Key" \
	"dns_la LA_Id LA_Sk LA_Token" \
	"dns_namecheap NAMECHEAP_API_KEY NAMECHEAP_USERNAME NAMECHEAP_SOURCEIP" \
	"dns_namecom Namecom_Username Namecom_Token" \
	"dns_namesilo Namesilo_Key" \
	"dns_nsone NS1_Key" \
	"dns_porkbun PORKBUN_API_KEY PORKBUN_SECRET_API_KEY" \
	"dns_volcengine Volcengine_ACCESS_KEY_ID Volcengine_SECRET_ACCESS_KEY Volcengine_SESSION_TOKEN" \
	"dns_spaceship SPACESHIP_API_KEY SPACESHIP_API_SECRET SPACESHIP_ROOT_DOMAIN" \
	"dns_vercel VERCEL_TOKEN" \
	"dns_linode_v4 LINODE_V4_API_KEY" \
	"dns_dgon DO_API_KEY" \
	"dns_gcloud CLOUDSDK_ACTIVE_CONFIG_NAME" \
	"dns_zonomi ZM_Key"
do
	set -- $item
	dns_api="$1"
	shift
	require_text "$OPS" "$dns_api"
	require_text "$PROVIDER" "$dns_api"
	for env in "$@"; do
		require_text "$OPS" "$env"
		require_text "$PROVIDER" "$env"
	done
done

check_preview_envs() {
	dns_api="$1"
	shift
	out="$(acmesh_test_cli_request preview-issue --domain example.com --key-type ec256 --validation-method dns --dns-api "$dns_api" --test-mode "$@")"
	case "$out" in
		*"--dns '$dns_api'"*) ;;
		*) echo "preview command missing dns api $dns_api"; echo "$out"; exit 1 ;;
	esac
	while [ "$#" -gt 0 ]; do
		case "$1" in
			--credential)
				env=${2%%=*}
				value=${2#*=}
				case "$out" in
					*"$env="*) ;;
					*) echo "preview command missing credential env $env for $dns_api"; echo "$out"; exit 1 ;;
				esac
				case "$env" in
					*Token*|*TOKEN*|*token*|*Key*|*KEY*|*key*|*Secret*|*SECRET*|*secret*|*Password*|*PASSWORD*|*password*|*Authorization*|*AUTHORIZATION*|*authorization*|*Credential*|*CREDENTIAL*|*credential*|*_SK|*_Sk|*_sk)
						case "$out" in
							*"$value"*) echo "preview command leaked credential value $env for $dns_api"; echo "$out"; exit 1 ;;
						esac
						;;
				esac
				shift 2
				;;
			*)
				shift
				;;
		esac
	done
}

check_preview_envs dns_ali --credential Ali_Key=ali-key --credential Ali_Secret=ali-secret
check_preview_envs dns_dp --credential DP_Id=dp-id --credential DP_Key=dp-key
check_preview_envs dns_tencent --credential Tencent_SecretId=tencent-id --credential Tencent_SecretKey=tencent-key
check_preview_envs dns_duckdns --credential DuckDNS_Token=duck-token
check_preview_envs dns_dynv6 --credential DYNV6_TOKEN=dynv6-token
check_preview_envs dns_dynv6 --credential KEY=/root/.ssh/dynv6
check_preview_envs dns_gd --credential GD_Key=gd-key --credential GD_Secret=gd-secret
check_preview_envs dns_aws --credential AWS_ACCESS_KEY_ID=aws-id --credential AWS_SECRET_ACCESS_KEY=aws-secret --credential AWS_DNS_SLOWRATE=10
check_preview_envs dns_baidu --credential Baidu_AK=baidu-ak --credential Baidu_SK=baidu-sk --credential Baidu_API_Preference=auto --credential Baidu_View=DEFAULT --credential Baidu_Line=default
check_preview_envs dns_azure --credential AZUREDNS_SUBSCRIPTIONID=azure-sub --credential AZUREDNS_TENANTID=azure-tenant --credential AZUREDNS_APPID=azure-app --credential AZUREDNS_CLIENTSECRET=azure-secret
check_preview_envs dns_azure --credential AZUREDNS_SUBSCRIPTIONID=azure-sub --credential AZUREDNS_BEARERTOKEN=azure-bearer
check_preview_envs dns_azure --credential AZUREDNS_SUBSCRIPTIONID=azure-sub --credential AZUREDNS_MANAGEDIDENTITY=true
check_preview_envs dns_cloudns --credential CLOUDNS_AUTH_ID=cloudns-id --credential CLOUDNS_AUTH_PASSWORD=cloudns-pass
check_preview_envs dns_cloudns --credential CLOUDNS_SUB_AUTH_ID=cloudns-sub-id --credential CLOUDNS_AUTH_PASSWORD=cloudns-pass
check_preview_envs dns_he --credential HE_Username=he-user --credential HE_Password=he-pass
check_preview_envs dns_huaweicloud --credential HUAWEICLOUD_Username=hw-user --credential HUAWEICLOUD_Password=hw-pass --credential HUAWEICLOUD_DomainName=hw-domain --credential HUAWEICLOUD_Region=cn-north-4
check_preview_envs dns_gcore --credential GCORE_Key=gcore-key
check_preview_envs dns_la --credential LA_Id=la-id --credential LA_Sk=la-secret
check_preview_envs dns_la --credential LA_Token=la-token
check_preview_envs dns_namecheap --credential NAMECHEAP_API_KEY=namecheap-key --credential NAMECHEAP_USERNAME=namecheap-user --credential NAMECHEAP_SOURCEIP=192.0.2.10
check_preview_envs dns_namecom --credential Namecom_Username=namecom-user --credential Namecom_Token=namecom-token
check_preview_envs dns_namesilo --credential Namesilo_Key=namesilo-key
check_preview_envs dns_nsone --credential NS1_Key=nsone-key
check_preview_envs dns_porkbun --credential PORKBUN_API_KEY=porkbun-key --credential PORKBUN_SECRET_API_KEY=porkbun-secret
check_preview_envs dns_volcengine --credential Volcengine_ACCESS_KEY_ID=volc-id --credential Volcengine_SECRET_ACCESS_KEY=volc-secret --credential Volcengine_SESSION_TOKEN=volc-token
check_preview_envs dns_spaceship --credential SPACESHIP_API_KEY=spaceship-key --credential SPACESHIP_API_SECRET=spaceship-secret --credential SPACESHIP_ROOT_DOMAIN=example.com
check_preview_envs dns_vercel --credential VERCEL_TOKEN=vercel-token
check_preview_envs dns_linode_v4 --credential LINODE_V4_API_KEY=linode-key
check_preview_envs dns_dgon --credential DO_API_KEY=do-key
check_preview_envs dns_gcloud --credential CLOUDSDK_ACTIVE_CONFIG_NAME=default
check_preview_envs dns_zonomi --credential ZM_Key=zonomi-key

cf_token_preview="$(acmesh_test_cli_request preview-issue \
	--domain example.com \
	--key-type ec256 \
	--validation-method dns \
	--dns-api dns_cf \
	--credential CF_Token=secret-token \
	--credential CF_Zone_ID= \
	--credential CF_Account_ID=none \
	--test-mode)"
case "$cf_token_preview" in
	*"CF_Token='***'"*"--dns 'dns_cf'"*) ;;
	*) echo "cloudflare token preview should include masked token"; echo "$cf_token_preview"; exit 1 ;;
esac
case "$cf_token_preview" in
	*"CF_Zone_ID"*|*"CF_Account_ID"*) echo "empty cloudflare optional ids should not be submitted"; echo "$cf_token_preview"; exit 1 ;;
esac
case "$cf_token_preview" in
	*"secret-token"*) echo "cloudflare token leaked"; echo "$cf_token_preview"; exit 1 ;;
esac

cf_global_preview="$(acmesh_test_cli_request preview-issue \
	--domain example.com \
	--key-type ec256 \
	--validation-method dns \
	--dns-api dns_cf \
	--credential CF_Email=admin@example.org \
	--credential CF_Key=global-secret \
	--test-mode)"
case "$cf_global_preview" in
	*"CF_Email='admin@example.org'"*"CF_Key='***'"*"--dns 'dns_cf'"*) ;;
	*) echo "cloudflare global key preview should include email and masked key"; echo "$cf_global_preview"; exit 1 ;;
esac
case "$cf_global_preview" in
	*"global-secret"*) echo "cloudflare global key leaked"; echo "$cf_global_preview"; exit 1 ;;
esac

echo "test_dns_provider_contracts: ok"
