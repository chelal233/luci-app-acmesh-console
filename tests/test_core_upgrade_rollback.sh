#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"; TMP="${TMPDIR:-/tmp}/acmesh-core-rollback.$$"; trap 'rm -rf "$TMP"' 0 HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/home" "$TMP/src/acme.sh-3.1.4"; export ACMESH_LIB_DIR="$ROOT/root/usr/libexec/acmesh-console/lib"
. "$ACMESH_LIB_DIR/command.sh"
cat > "$TMP/home/acme.sh" <<'SH'
#!/bin/sh
[ "${1:-}" = --version ] && echo 'old v1.0.0'
SH
chmod +x "$TMP/home/acme.sh"; original="$(sha256sum "$TMP/home/acme.sh" | awk '{print $1}')"
cp "$TMP/home/acme.sh" "$TMP/original-acme.sh"
cat > "$TMP/bin/openssl" <<'SH'
#!/bin/sh
exit 0
SH
cat > "$TMP/bin/curl" <<'SH'
#!/bin/sh
[ "$CORE_STAGE" != download ] || exit 9
seen_url=0
while [ "$#" -gt 0 ]; do
	[ "$1" != "$EXPECT_CORE_URL" ] || seen_url=1
	[ "$1" != -o ] || { [ "$seen_url" = 1 ] || { echo "unexpected core url" >&2; exit 8; }; cp "$CORE_ARCHIVE" "$2"; exit; }
	shift
done
SH
chmod +x "$TMP/bin/openssl" "$TMP/bin/curl"; export PATH="$TMP/bin:$PATH" ACME_OPENSSL_BIN=openssl
make_archive() {
	stage="$1"
	cat > "$TMP/src/acme.sh-3.1.4/acme.sh" <<SH
#!/bin/sh
case "\${1:-}" in
 --version) echo 'new v3.1.4'; exit 0;;
 --install) [ '$stage' != install ] || exit 7; printf '#!/bin/sh\nexit 1\n' > '$TMP/home/acme.sh'; chmod +x '$TMP/home/acme.sh'; exit 0;;
esac
SH
	chmod +x "$TMP/src/acme.sh-3.1.4/acme.sh"; tar -czf "$TMP/$stage.tar.gz" -C "$TMP/src" acme.sh-3.1.4
}
for stage in download extract install postcheck; do
	cp "$TMP/original-acme.sh" "$TMP/home/acme.sh"; chmod +x "$TMP/home/acme.sh"
	case "$stage" in extract) printf bad > "$TMP/extract.tar.gz";; *) make_archive "$stage";; esac
	export CORE_STAGE="$stage" CORE_ARCHIVE="$TMP/$stage.tar.gz" ACMESH_CORE_TMPDIR="$TMP/work-$stage" EXPECT_CORE_URL='https://codeload.github.com/acmesh-official/acme.sh/tar.gz/refs/tags/3.1.4'
	set +e; acmesh_execute_core_install "$TMP/home" '' v3.1.4 >/dev/null 2>&1; rc=$?; set -e
	[ "$rc" -ne 0 ] || { echo "$stage failure was not injected"; exit 1; }
	[ "$(sha256sum "$TMP/home/acme.sh" | awk '{print $1}')" = "$original" ] || { echo "$stage did not restore original SHA"; exit 1; }
done
echo "test_core_upgrade_rollback: ok"
