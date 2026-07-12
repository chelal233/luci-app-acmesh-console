. "${ACMESH_LIB_DIR:-/usr/libexec/acmesh-console/lib}/json.sh"

acmesh_providers_json() {
	cat <<'JSON'
{"ok":true,"providers":[
{"id":"cloudflare","title":"Cloudflare","dnsApi":"dns_cf","fields":[{"name":"token","env":"CF_Token","secret":true},{"name":"zoneId","env":"CF_Zone_ID","secret":false},{"name":"accountId","env":"CF_Account_ID","secret":false},{"name":"email","env":"CF_Email","secret":false},{"name":"globalKey","env":"CF_Key","secret":true}]},
{"id":"aliyun","title":"Aliyun","dnsApi":"dns_ali","fields":[{"name":"key","env":"Ali_Key","secret":false},{"name":"secret","env":"Ali_Secret","secret":true}]},
{"id":"dnspod","title":"DNSPod.cn","dnsApi":"dns_dp","fields":[{"name":"id","env":"DP_Id","secret":false},{"name":"key","env":"DP_Key","secret":true}]},
{"id":"tencentcloud","title":"Tencent Cloud DNSPod","dnsApi":"dns_tencent","fields":[{"name":"secretId","env":"Tencent_SecretId","secret":false},{"name":"secretKey","env":"Tencent_SecretKey","secret":true}]},
{"id":"duckdns","title":"DuckDNS","dnsApi":"dns_duckdns","fields":[{"name":"token","env":"DuckDNS_Token","secret":true}]},
{"id":"dynv6","title":"dynv6","dnsApi":"dns_dynv6","fields":[{"name":"token","env":"DYNV6_TOKEN","secret":true},{"name":"sshKey","env":"KEY","secret":true}]},
{"id":"godaddy","title":"GoDaddy","dnsApi":"dns_gd","fields":[{"name":"key","env":"GD_Key","secret":false},{"name":"secret","env":"GD_Secret","secret":true}]},
{"id":"aws","title":"Amazon Route 53","dnsApi":"dns_aws","fields":[{"name":"accessKey","env":"AWS_ACCESS_KEY_ID","secret":false},{"name":"secretKey","env":"AWS_SECRET_ACCESS_KEY","secret":true},{"name":"slowRate","env":"AWS_DNS_SLOWRATE","secret":false}]},
{"id":"baidu","title":"Baidu Cloud DNS","dnsApi":"dns_baidu","fields":[{"name":"accessKey","env":"Baidu_AK","secret":false},{"name":"secretKey","env":"Baidu_SK","secret":true},{"name":"apiPreference","env":"Baidu_API_Preference","secret":false},{"name":"view","env":"Baidu_View","secret":false},{"name":"line","env":"Baidu_Line","secret":false}]},
{"id":"azure","title":"Azure DNS","dnsApi":"dns_azure","fields":[{"name":"subscriptionId","env":"AZUREDNS_SUBSCRIPTIONID","secret":false},{"name":"tenantId","env":"AZUREDNS_TENANTID","secret":false},{"name":"appId","env":"AZUREDNS_APPID","secret":false},{"name":"clientSecret","env":"AZUREDNS_CLIENTSECRET","secret":true},{"name":"managedIdentity","env":"AZUREDNS_MANAGEDIDENTITY","secret":false},{"name":"bearerToken","env":"AZUREDNS_BEARERTOKEN","secret":true}]},
{"id":"cloudns","title":"ClouDNS","dnsApi":"dns_cloudns","fields":[{"name":"authId","env":"CLOUDNS_AUTH_ID","secret":false},{"name":"subAuthId","env":"CLOUDNS_SUB_AUTH_ID","secret":false},{"name":"authPassword","env":"CLOUDNS_AUTH_PASSWORD","secret":true}]},
{"id":"he","title":"Hurricane Electric","dnsApi":"dns_he","fields":[{"name":"username","env":"HE_Username","secret":false},{"name":"password","env":"HE_Password","secret":true}]},
{"id":"huaweicloud","title":"Huawei Cloud DNS","dnsApi":"dns_huaweicloud","fields":[{"name":"username","env":"HUAWEICLOUD_Username","secret":false},{"name":"password","env":"HUAWEICLOUD_Password","secret":true},{"name":"domainName","env":"HUAWEICLOUD_DomainName","secret":false},{"name":"region","env":"HUAWEICLOUD_Region","secret":false}]},
{"id":"gcore","title":"Gcore DNS","dnsApi":"dns_gcore","fields":[{"name":"apiKey","env":"GCORE_Key","secret":true}]},
{"id":"namecheap","title":"Namecheap","dnsApi":"dns_namecheap","fields":[{"name":"username","env":"NAMECHEAP_USERNAME","secret":false},{"name":"apiKey","env":"NAMECHEAP_API_KEY","secret":true},{"name":"sourceIp","env":"NAMECHEAP_SOURCEIP","secret":false}]},
{"id":"dnsla","title":"DNS.LA","dnsApi":"dns_la","fields":[{"name":"apiId","env":"LA_Id","secret":false},{"name":"apiSecret","env":"LA_Sk","secret":true},{"name":"apiToken","env":"LA_Token","secret":true}]},
{"id":"namecom","title":"Name.com","dnsApi":"dns_namecom","fields":[{"name":"username","env":"Namecom_Username","secret":false},{"name":"apiToken","env":"Namecom_Token","secret":true}]},
{"id":"namesilo","title":"NameSilo","dnsApi":"dns_namesilo","fields":[{"name":"apiKey","env":"Namesilo_Key","secret":true}]},
{"id":"nsone","title":"IBM NS1 Connect","dnsApi":"dns_nsone","fields":[{"name":"apiKey","env":"NS1_Key","secret":true}]},
{"id":"porkbun","title":"Porkbun","dnsApi":"dns_porkbun","fields":[{"name":"apiKey","env":"PORKBUN_API_KEY","secret":true},{"name":"secretApiKey","env":"PORKBUN_SECRET_API_KEY","secret":true}]},
{"id":"volcengine","title":"Volcengine DNS","dnsApi":"dns_volcengine","fields":[{"name":"accessKeyId","env":"Volcengine_ACCESS_KEY_ID","secret":false},{"name":"secretAccessKey","env":"Volcengine_SECRET_ACCESS_KEY","secret":true},{"name":"sessionToken","env":"Volcengine_SESSION_TOKEN","secret":true}]},
{"id":"spaceship","title":"Spaceship","dnsApi":"dns_spaceship","fields":[{"name":"apiKey","env":"SPACESHIP_API_KEY","secret":true},{"name":"apiSecret","env":"SPACESHIP_API_SECRET","secret":true},{"name":"rootDomain","env":"SPACESHIP_ROOT_DOMAIN","secret":false}]},
{"id":"vercel","title":"Vercel","dnsApi":"dns_vercel","fields":[{"name":"apiToken","env":"VERCEL_TOKEN","secret":true}]},
{"id":"linode","title":"Linode","dnsApi":"dns_linode_v4","fields":[{"name":"apiKey","env":"LINODE_V4_API_KEY","secret":true}]},
{"id":"digitalocean","title":"DigitalOcean","dnsApi":"dns_dgon","fields":[{"name":"apiKey","env":"DO_API_KEY","secret":true}]},
{"id":"gcloud","title":"Google Cloud DNS","dnsApi":"dns_gcloud","fields":[{"name":"activeConfig","env":"CLOUDSDK_ACTIVE_CONFIG_NAME","secret":false}]},
{"id":"zonomi","title":"Zonomi","dnsApi":"dns_zonomi","fields":[{"name":"apiKey","env":"ZM_Key","secret":true}]}
]}
JSON
}
