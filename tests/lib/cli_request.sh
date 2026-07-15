#!/bin/sh

acmesh_test_cli_request() {
	command="$1"; shift
	fields= credentials= first_field=1 first_credential=1
	while [ "$#" -gt 0 ]; do
		case "$1" in
			--credential)
				[ "$#" -ge 2 ] || return 2
				[ "$first_credential" = 1 ] || credentials="$credentials,"
				first_credential=0
				credentials="$credentials\"$(acmesh_json_escape "$2")\""
				shift 2
				;;
			--test-mode|--real-mode|--allow-key-convert)
				case "$1" in --test-mode) key=testMode; value=true;; --real-mode) key=testMode; value=false;; --allow-key-convert) key=allowKeyConvert; value=true;; esac
				[ "$first_field" = 1 ] || fields="$fields,"
				first_field=0; fields="$fields\"$key\":$value"; shift
				;;
			--*)
				[ "$#" -ge 2 ] || return 2
				case "$1" in
					--domain) key=domain;; --key-type) key=keyType;; --validation-method) key=validationMethod;;
					--dns-api) key=dnsApi;; --ca) key=ca;; --webroot) key=webroot;; --listen-port) key=listenPort;;
					--account-email) key=accountEmail;; --type) key=type;; --cert-source) key=certSource;;
					--key-file) key=keyFile;; --fullchain-file) key=fullchainFile;; --cert-file) key=certFile;; --ca-file) key=caFile;;
					--reloadcmd) key=reloadcmd;; --source-key-file) key=sourceKeyFile;; --source-fullchain-file) key=sourceFullchainFile;;
					--key-pem) key=keyPem;; --fullchain-pem) key=fullchainPem;; --host) key=host;; --port) key=port;;
					--user) key=user;; --ssh-key) key=sshKey;; --profile-id) key=profileId;;
					*) echo "unsupported test CLI field: $1" >&2; return 2;;
				esac
				[ "$first_field" = 1 ] || fields="$fields,"
				first_field=0; fields="$fields\"$key\":\"$(acmesh_json_escape "$2")\""; shift 2
				;;
			*) echo "unsupported test CLI argument: $1" >&2; return 2;;
		esac
	done
	if [ "$first_credential" = 0 ]; then
		[ "$first_field" = 1 ] || fields="$fields,"
		fields="$fields\"credentials\":[$credentials]"
	fi
	printf '{%s}\n' "$fields" | sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" "$command" --request-stdin
}
