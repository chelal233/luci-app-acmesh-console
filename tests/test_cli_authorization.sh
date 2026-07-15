#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CTL="$ROOT/root/usr/libexec/acmesh-console/acmeshctl"

require() { grep -F -- "$2" "$1" >/dev/null || { echo "missing CLI contract: $2"; exit 1; }; }
reject() { ! grep -F -- "$2" "$1" >/dev/null || { echo "forbidden CLI contract: $2"; exit 1; }; }

require "$CTL" '--request-stdin'
require "$CTL" '--acknowledge-risk'
require "$CTL" '--remember-authorization'
require "$CTL" 'authorization-execute'
require "$CTL" 'decision'
require "$CTL" 'mktemp'
require "$CTL" 'chmod 600'
require "$CTL" 'trap'

reject "$CTL" '--credential) credentials='
reject "$CTL" '--key-pem) key_pem='
reject "$CTL" '--fullchain-pem) fullchain_pem='
require "$CTL" 'sensitive request arguments are unsupported; use --request-stdin'
require "$CTL" '--credential=*'
require "$CTL" '--key-pem=*'
require "$CTL" '--fullchain-pem=*'
reject "$CTL" '--yes'
reject "$CTL" '--force-all'
reject "$CTL" 'disable-confirm'

set +e
out="$(printf '{}\n' | ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib" "$CTL" --acknowledge-risk invalid 2>&1)"
rc=$?
set -e
[ "$rc" != 0 ] || { echo 'invalid acknowledgement unexpectedly succeeded'; exit 1; }
case "$out" in *'invalid authorization challenge'*|*'authorization'*|*'jsonfilter is required'* ) ;; *) echo "$out"; exit 1;; esac

if command -v jsonfilter >/dev/null 2>&1; then
	TMP="$ROOT/tests/.tmp/cli-authorization.$$"
	rm -rf "$TMP"; mkdir -p "$TMP/state" "$TMP/log" "$TMP/work"; chmod 700 "$TMP" "$TMP/state" "$TMP/log" "$TMP/work"
	secret='CLI_SECRET_MUST_NOT_LEAK_83f19'
	payload="{\"domain\":\"example.org\",\"dnsApi\":\"dns_cf\",\"credentials\":[\"CF_Token=$secret\"],\"testMode\":true}"
	printf '%s\n' "$payload" | TMPDIR="$TMP/work" ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib" ACMESH_TASK_STATE_DIR="$TMP/state" ACMESH_TASK_LOG_DIR="$TMP/log" "$CTL" dns-test --request-stdin > "$TMP/output" &
	pid=$!
	if [ -r "/proc/$pid/cmdline" ]; then
		! tr '\000' ' ' < "/proc/$pid/cmdline" | grep -F "$secret" >/dev/null || { echo 'secret leaked through process arguments'; exit 1; }
	fi
	wait "$pid"
	sleep 1
	! grep -R -F "$secret" "$TMP/output" "$TMP/state" "$TMP/log" >/dev/null 2>&1 || { echo 'secret leaked through CLI output or task artifacts'; exit 1; }
	[ -z "$(find "$TMP/work" -type f -name 'acmesh-cli-request.*' -print)" ] || { echo 'stdin request file was not removed'; exit 1; }
	rm -rf "$TMP"
fi

echo 'test_cli_authorization: ok'
