#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PAGE="$ROOT/htdocs/luci-static/resources/view/acmesh/certificates_v2.js"
MENU="$ROOT/root/usr/share/luci/menu.d/luci-app-acmesh-console.json"

require_text() {
	needle="$1"
	if ! grep -Fq -- "$needle" "$PAGE"; then
		echo "certificates page missing: $needle"
		exit 1
	fi
}

reject_text() {
	needle="$1"
	if grep -Fq -- "$needle" "$PAGE"; then
		echo "certificates page still has old card marker: $needle"
		exit 1
	fi
}

require_text "renderTable"
require_text "renderCertificateList"
require_text "renderCertificateDetail"
require_text "setView"
require_text "View certificate"
require_text "Native variables"
reject_text "source: 'history'"
require_text "Renew"
require_text "Deploy"
require_text "deployProfiles"
require_text "deployProfileSelect"
require_text "deployCertificateWithProfile"
require_text "prepareDeploy"
require_text "saveCoreDefaults"
require_text "Save defaults"
require_text "Test this core action"
reject_text "Global Test Mode"
require_text "Core tag candidates"
require_text "Current core version"
require_text "Install selected tag"
require_text "Upgrade selected tag"
require_text "acmesh-summary-controls"
require_text "acmesh-control-panel"
require_text "acmesh-version-panel"
require_text "acmesh-version-title"
require_text "acmesh-controls-shell"
require_text "acmesh-control-hint"
require_text "acmesh-mode-panel"
require_text "acmesh-primary-actions"
require_text "acmesh-summary-actions"
require_text "text-overflow:ellipsis"
require_text "flex-wrap:nowrap"
require_text "grid-template-columns:minmax(220px, 1fr) minmax(220px, 1fr) minmax(260px, 1.15fr) minmax(150px, .55fr) minmax(360px, max-content)"
require_text "background:rgba(127,127,127,.10)"
require_text "border-bottom:1px solid rgba(127,127,127,.24)"
require_text "coreTaskPayload"
require_text "acmeshApi.write('config_save'"
require_text "L.resolveDefault(acmeshApi.write('config_get', {}), {})"
require_text "authorization.run('core_install'"
require_text "authorization.run('core_upgrade'"

if ! grep -Fq -- '"path": "acmesh/certificates_v2"' "$MENU"; then
	echo "certificates menu still points at old view module"
	exit 1
fi

reject_text "certCard"
reject_text "acmesh-cert-card"
reject_text "Core & Defaults"
reject_text "renderCoreDefaults"
reject_text "acmesh-core-defaults"
reject_text "renderCoreDefaults(),"
reject_text "acmesh-panel is-editable"
reject_text ".acmesh-panel.is-editable input"
reject_text "panel(_('Core version')"
reject_text "background:#fff; }"
reject_text "grid-template-columns:repeat(auto-fit, minmax(280px, 1fr))"
reject_text "background:#f1f4f8"
reject_text "border-bottom:1px solid #e2e7ef"
reject_text "display:block; margin-top:5px"
reject_text "'deploy-test', '--domain'"
reject_text "'/etc/ssl/' + (cert.mainDomain || 'example')"

install_line="$(grep -n "authorization.run('core_install'" "$PAGE" | cut -d: -f1)"
upgrade_line="$(grep -n "authorization.run('core_upgrade'" "$PAGE" | cut -d: -f1)"
for line in "$install_line" "$upgrade_line"; do
	start=$((line - 4))
	sed -n "${start},${line}p" "$PAGE" | grep -F "if (!res.ok)" >/dev/null || {
		echo "core action does not stop after saveConfig failure near line $line"
		exit 1
	}
done

echo "test_certificates_list_detail_ui: ok"
