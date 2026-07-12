#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
export ACME_OPENSSL_BIN="$ROOT/tests/.tmp/missing-openssl"
home="$ROOT/tests/.tmp/core-install-no-openssl-home"
fakebin="$ROOT/tests/.tmp/core-install-fakebin"
rm -rf "$home" "$fakebin"
mkdir -p "$fakebin"
cat > "$fakebin/curl" <<'SH'
#!/bin/sh
printf '%s\n' 'echo "Downloading https://github.com/acmesh-official/acme.sh/archive/master.tar.gz"'
SH
chmod +x "$fakebin/curl"
export PATH="$fakebin:$PATH"

. "$ACMESH_LIB_DIR/command.sh"

set +e
out="$(acmesh_execute_core_install "$home" admin@example.com 2>&1)"
rc=$?
set -e

[ "$rc" -ne 0 ] || { echo "core install should fail without openssl"; echo "$out"; exit 1; }
case "$out" in
	*"openssl is required"*"apk add openssl-util"*) ;;
	*) echo "missing actionable openssl error"; echo "$out"; exit 1 ;;
esac
case "$out" in
	*"Downloading https://github.com"*)
		echo "core install should fail before official download"
		echo "$out"
		exit 1
		;;
esac

echo "test_core_install_requires_openssl: ok"
