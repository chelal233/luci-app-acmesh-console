#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
. "$ACMESH_LIB_DIR/json.sh"
. "$ROOT/tests/lib/cli_request.sh"

run_ctl() {
	case "$1" in
		dns-test) acmesh_test_cli_request "$@" ;;
		*) sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" "$@" ;;
	esac
}

cf_ok="$(run_ctl dns-test \
	--domain example.com \
	--dns-api dns_cf \
	--credential CF_Token=secret-token \
	--credential CF_Zone_ID= \
	--credential CF_Account_ID=none \
	--test-mode)"
case "$cf_ok" in
	*"\"taskId\""*) ;;
	*) echo "dns-test should create a task"; echo "$cf_ok"; exit 1 ;;
esac
task_id="$(printf '%s' "$cf_ok" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
sleep 1
cf_log="$(run_ctl task-log --task-id "$task_id")"
case "$cf_log" in
	*"Cloudflare token mode selected"*"CF_Zone_ID is empty"*"CF_Account_ID is empty"*) ;;
	*) echo "cloudflare diagnostic missing optional-id findings"; echo "$cf_log"; exit 1 ;;
esac
case "$cf_log" in
	*"secret-token"*) echo "cloudflare diagnostic leaked token"; echo "$cf_log"; exit 1 ;;
esac
cf_status="$(run_ctl task-status --task-id "$task_id")"
case "$cf_status" in
	*"\"status\":\"success\""*) ;;
	*) echo "cloudflare diagnostic should succeed"; echo "$cf_status"; echo "$cf_log"; exit 1 ;;
esac

cf_bad="$(run_ctl dns-test --domain example.com --dns-api dns_cf --test-mode)"
bad_task_id="$(printf '%s' "$cf_bad" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
sleep 1
bad_log="$(run_ctl task-log --task-id "$bad_task_id")"
case "$bad_log" in
	*"requires either CF_Token"*) ;;
	*) echo "cloudflare diagnostic should explain missing credentials"; echo "$bad_log"; exit 1 ;;
esac
bad_status="$(run_ctl task-status --task-id "$bad_task_id")"
case "$bad_status" in
	*"\"status\":\"failed\""*) ;;
	*) echo "cloudflare missing credential diagnostic should fail"; echo "$bad_status"; echo "$bad_log"; exit 1 ;;
esac

aliyun_ok="$(run_ctl dns-test \
	--domain example.com \
	--dns-api dns_ali \
	--credential Ali_Key=ali-key \
	--credential Ali_Secret=ali-secret \
	--test-mode)"
aliyun_task_id="$(printf '%s' "$aliyun_ok" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
sleep 1
aliyun_log="$(run_ctl task-log --task-id "$aliyun_task_id")"
case "$aliyun_log" in
	*"Aliyun required credentials are present"*) ;;
	*) echo "aliyun diagnostic should pass"; echo "$aliyun_log"; exit 1 ;;
esac
case "$aliyun_log" in
	*"ali-secret"*) echo "aliyun diagnostic leaked secret"; echo "$aliyun_log"; exit 1 ;;
esac

baidu_ok="$(run_ctl dns-test \
	--domain example.com \
	--dns-api dns_baidu \
	--credential Baidu_AK=baidu-ak \
	--credential Baidu_SK=baidu-secret \
	--test-mode)"
baidu_task_id="$(printf '%s' "$baidu_ok" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
sleep 1
baidu_log="$(run_ctl task-log --task-id "$baidu_task_id")"
case "$baidu_log" in
	*"Baidu Cloud DNS required credentials are present"*) ;;
	*) echo "baidu diagnostic should pass"; echo "$baidu_log"; exit 1 ;;
esac
case "$baidu_log" in
	*"baidu-secret"*) echo "baidu diagnostic leaked secret"; echo "$baidu_log"; exit 1 ;;
esac

cloudns_ok="$(run_ctl dns-test \
	--domain example.com \
	--dns-api dns_cloudns \
	--credential CLOUDNS_SUB_AUTH_ID=cloudns-sub \
	--credential CLOUDNS_AUTH_PASSWORD=cloudns-pass \
	--test-mode)"
cloudns_task_id="$(printf '%s' "$cloudns_ok" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
sleep 1
cloudns_log="$(run_ctl task-log --task-id "$cloudns_task_id")"
case "$cloudns_log" in
	*"ClouDNS sub-auth mode required credentials are present"*) ;;
	*) echo "cloudns diagnostic should pass"; echo "$cloudns_log"; exit 1 ;;
esac

dnsla_ok="$(run_ctl dns-test \
	--domain example.com \
	--dns-api dns_la \
	--credential LA_Token=la-token \
	--test-mode)"
dnsla_task_id="$(printf '%s' "$dnsla_ok" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
sleep 1
dnsla_log="$(run_ctl task-log --task-id "$dnsla_task_id")"
case "$dnsla_log" in
	*"DNS.LA token mode required credentials are present"*) ;;
	*) echo "dnsla diagnostic should pass"; echo "$dnsla_log"; exit 1 ;;
esac

azure_ok="$(run_ctl dns-test \
	--domain example.com \
	--dns-api dns_azure \
	--credential AZUREDNS_SUBSCRIPTIONID=azure-sub \
	--credential AZUREDNS_TENANTID=azure-tenant \
	--credential AZUREDNS_APPID=azure-app \
	--credential AZUREDNS_CLIENTSECRET=azure-secret \
	--test-mode)"
azure_task_id="$(printf '%s' "$azure_ok" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
sleep 1
azure_log="$(run_ctl task-log --task-id "$azure_task_id")"
case "$azure_log" in
	*"Azure service-principal mode required credentials are present"*) ;;
	*) echo "azure service-principal diagnostic should pass"; echo "$azure_log"; exit 1 ;;
esac
case "$azure_log" in
	*"azure-secret"*) echo "azure diagnostic leaked client secret"; echo "$azure_log"; exit 1 ;;
esac

azure_bearer_ok="$(run_ctl dns-test \
	--domain example.com \
	--dns-api dns_azure \
	--credential AZUREDNS_SUBSCRIPTIONID=azure-sub \
	--credential AZUREDNS_BEARERTOKEN=azure-bearer \
	--test-mode)"
azure_bearer_task_id="$(printf '%s' "$azure_bearer_ok" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
sleep 1
azure_bearer_log="$(run_ctl task-log --task-id "$azure_bearer_task_id")"
case "$azure_bearer_log" in
	*"Azure bearer-token mode required credentials are present"*) ;;
	*) echo "azure bearer-token diagnostic should pass"; echo "$azure_bearer_log"; exit 1 ;;
esac

huaweicloud_ok="$(run_ctl dns-test \
	--domain example.com \
	--dns-api dns_huaweicloud \
	--credential HUAWEICLOUD_Username=hw-user \
	--credential HUAWEICLOUD_Password=hw-pass \
	--credential HUAWEICLOUD_DomainName=hw-domain \
	--test-mode)"
huaweicloud_task_id="$(printf '%s' "$huaweicloud_ok" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
sleep 1
huaweicloud_log="$(run_ctl task-log --task-id "$huaweicloud_task_id")"
case "$huaweicloud_log" in
	*"Huawei Cloud DNS required credentials are present"*) ;;
	*) echo "huaweicloud diagnostic should pass"; echo "$huaweicloud_log"; exit 1 ;;
esac
case "$huaweicloud_log" in
	*"hw-pass"*) echo "huaweicloud diagnostic leaked password"; echo "$huaweicloud_log"; exit 1 ;;
esac

volcengine_ok="$(run_ctl dns-test \
	--domain example.com \
	--dns-api dns_volcengine \
	--credential Volcengine_ACCESS_KEY_ID=volc-id \
	--credential Volcengine_SECRET_ACCESS_KEY=volc-secret \
	--test-mode)"
volcengine_task_id="$(printf '%s' "$volcengine_ok" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
sleep 1
volcengine_log="$(run_ctl task-log --task-id "$volcengine_task_id")"
case "$volcengine_log" in
	*"Volcengine DNS required credentials are present"*) ;;
	*) echo "volcengine diagnostic should pass"; echo "$volcengine_log"; exit 1 ;;
esac
case "$volcengine_log" in
	*"volc-secret"*) echo "volcengine diagnostic leaked secret"; echo "$volcengine_log"; exit 1 ;;
esac

zonomi_ok="$(run_ctl dns-test \
	--domain example.com \
	--dns-api dns_zonomi \
	--credential ZM_Key=zonomi-key \
	--test-mode)"
zonomi_task_id="$(printf '%s' "$zonomi_ok" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
sleep 1
zonomi_log="$(run_ctl task-log --task-id "$zonomi_task_id")"
case "$zonomi_log" in
	*"Zonomi required credentials are present"*) ;;
	*) echo "zonomi diagnostic should pass"; echo "$zonomi_log"; exit 1 ;;
esac

custom_secret='dns-test-custom-secret'
custom_out="$(run_ctl dns-test --domain custom.example --dns-api dns_custom --credential ODD_VALUE="$custom_secret" --test-mode)"
custom_id="$(printf '%s' "$custom_out" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')"
for wait_round in 1 2 3 4 5; do custom_log="$(run_ctl task-log --task-id "$custom_id" 2>/dev/null || true)"; [ -n "$custom_log" ] && break; sleep 1; done
case "$custom_log" in *"$custom_secret"*) echo "dns-test leaked custom credential"; exit 1;; esac
case "$custom_log" in *"ODD_VALUE=***"*) ;; *) echo "dns-test did not redact custom credential"; echo "$custom_log"; exit 1;; esac
bad_custom='ODD_VALUE=line-one
line-two'
if bad_out="$(run_ctl dns-test --domain custom.example --dns-api dns_custom --credential "$bad_custom" --test-mode 2>&1)"; then
	echo "dns-test accepted a multiline custom credential"; exit 1
fi
case "$bad_out" in *line-one*|*line-two*) echo "dns-test echoed a rejected custom credential"; exit 1;; esac
case "$zonomi_log" in
	*"zonomi-key"*) echo "zonomi diagnostic leaked key"; echo "$zonomi_log"; exit 1 ;;
esac

echo "test_dns_test: ok"
