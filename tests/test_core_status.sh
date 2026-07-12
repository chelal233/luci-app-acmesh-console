#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
home="$ROOT/tests/.tmp/core-home"
rm -rf "$home"
mkdir -p "$home"

missing="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" core-status --home "$home")"
case "$missing" in
	*'"home":"'"$home"'"'*'"installed":false'*) ;;
	*) echo "missing core status is wrong"; echo "$missing"; exit 1 ;;
esac
case "$missing" in
	*'"dependencies":'*'"opensslBin":"openssl"'*) ;;
	*) echo "core status missing dependency details"; echo "$missing"; exit 1 ;;
esac

cat > "$home/acme.sh" <<'SH'
#!/bin/sh
case "$1" in
	--version) printf '%s\n%s\n' "https://github.com/acmesh-official/acme.sh" "v9.9.9-test" ;;
	*) echo "fake acme $*" ;;
esac
SH
chmod +x "$home/acme.sh"

installed="$(sh "$ROOT/root/usr/libexec/acmesh-console/acmeshctl" core-status --home "$home")"
case "$installed" in
	*'"installed":true'*) ;;
	*) echo "installed core status missing installed=true"; echo "$installed"; exit 1 ;;
esac
case "$installed" in
	*"$home/acme.sh"*) ;;
	*) echo "installed core status missing script path"; echo "$installed"; exit 1 ;;
esac
case "$installed" in
	*'"version":"v9.9.9-test"'*) ;;
	*) echo "installed core status missing parsed version"; echo "$installed"; exit 1 ;;
esac
case "$installed" in
	*'github.com/acmesh-official/acme.sh'*) echo "installed core status leaked version URL"; echo "$installed"; exit 1 ;;
	*) ;;
esac

echo "test_core_status: ok"
