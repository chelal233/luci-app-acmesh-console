#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PO="$ROOT/po/zh_Hans/acmesh-console.po"
OPS="$ROOT/htdocs/luci-static/resources/view/acmesh/operations_v2.js"
LMO="$ROOT/tests/.tmp/acmesh-console.zh-cn.lmo"

require_file_text() {
	file="$1"
	needle="$2"
	if ! grep -Fq -- "$needle" "$file"; then
		echo "missing i18n marker: $needle"
		exit 1
	fi
}

[ -f "$PO" ] || { echo "missing Simplified Chinese i18n catalog"; exit 1; }

require_file_text "$PO" 'Language: zh_Hans'
require_file_text "$PO" 'msgid "Operations"'
require_file_text "$PO" 'msgstr "操作"'
require_file_text "$PO" 'msgid "Certificates"'
require_file_text "$PO" 'msgstr "证书"'
require_file_text "$PO" 'msgid "Core & Defaults"'
require_file_text "$PO" 'msgstr "核心与默认值"'
require_file_text "$PO" 'msgid "Deploy Profiles"'
require_file_text "$PO" 'msgstr "部署配置"'
require_file_text "$PO" 'msgid "DNS Test"'
require_file_text "$PO" 'msgstr "DNS 测试"'
require_file_text "$PO" 'msgid "Issue succeeded; starting deploy profile"'
require_file_text "$PO" 'msgstr "证书签发成功，开始执行部署配置"'
require_file_text "$PO" 'msgid "Imported issue profiles"'
require_file_text "$PO" 'msgstr "已导入签发配置"'
require_file_text "$PO" 'msgid "Summary"'
require_file_text "$PO" 'msgstr "摘要"'
require_file_text "$PO" 'msgid "The DNS provider rejected the TXT record. Check that the domain belongs to this DNS account and that the selected DNS API credentials match the provider."'
require_file_text "$PO" 'msgid "Cloudflare API Token"'
require_file_text "$PO" 'msgstr "Cloudflare API 令牌"'
require_file_text "$PO" 'msgid "Paste PEM content"'
require_file_text "$PO" 'msgstr "粘贴 PEM 内容"'

require_file_text "$OPS" "label: _('Cloudflare API Token')"
require_file_text "$OPS" "title: _('Cloudflare')"
require_file_text "$OPS" "label: _('Aliyun AccessKey ID')"

command -v node >/dev/null || { echo "node is not available; skipping po2lmo generation check"; exit 0; }
node "$ROOT/tools/check_i18n_coverage.js"
node "$ROOT/tools/po2lmo.js" "$PO" "$LMO"

[ -s "$LMO" ] || { echo "generated lmo is empty"; exit 1; }

node - "$LMO" <<'NODE'
const fs = require('fs');
const file = process.argv[2];
const data = fs.readFileSync(file);
if (data.length < 20) {
	console.error('generated lmo is too small');
	process.exit(1);
}
const offset = data.readUInt32BE(data.length - 4);
const entries = (data.length - offset - 4) / 16;
if (offset <= 0 || offset >= data.length || entries < 10 || entries % 1 !== 0) {
	console.error(`invalid lmo index: offset=${offset} entries=${entries}`);
	process.exit(1);
}
for (const text of ['操作', '部署配置', 'Cloudflare API 令牌']) {
	if (!data.includes(Buffer.from(text, 'utf8'))) {
		console.error(`missing generated lmo text: ${text}`);
		process.exit(1);
	}
}
NODE

duplicates="$(awk '/^msgid "/ && $0 != "msgid \"\"" { if (seen[$0]++) print $0 }' "$PO")"
if [ -n "$duplicates" ]; then
	echo "duplicate i18n msgid entries:"
	echo "$duplicates"
	exit 1
fi

echo "test_i18n_support: ok"
