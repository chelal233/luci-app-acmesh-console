#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PAGE="$ROOT/htdocs/luci-static/resources/view/acmesh/operations_v2.js"

require_text() {
	needle="$1"
	if ! grep -Fq -- "$needle" "$PAGE"; then
		echo "operations page missing: $needle"
		exit 1
	fi
}

require_text "Test mode policy"
require_text "force-test-mode"
require_text "force-real-mode"
require_text "testModeOverride"
require_text "function requireConfig(response)"
require_text "acmeshApi.write('config_get', {}).then(requireConfig)"
require_text ".then(requireConfig).then(function(next)"

reject_text() {
	needle="$1"
	if grep -Fq -- "$needle" "$PAGE"; then
		echo "operations page should not contain duplicated defaults: $needle"
		exit 1
	fi
}

reject_text "Core & Defaults"
reject_text "renderDefaultsList"
reject_text "renderDefaultsForm"
reject_text "data-acmesh-tab': 'core'"
reject_text "field(_('Global Test Mode')"
reject_text "Inherit Global Test Mode"
reject_text "Install selected tag"
reject_text "Upgrade selected tag"

if grep -Fq "Core tag filter" "$PAGE" || grep -Fq "Selected core tag" "$PAGE" || grep -Fq "tagFilter" "$PAGE"; then
	echo "core defaults should only keep Core tag candidates"
	exit 1
fi

if grep -Fq "renderGlobal()" "$PAGE"; then
	echo "global defaults should not be rendered as repeated inline forms"
	exit 1
fi

if grep -Fq "setEdit('defaults'" "$PAGE"; then
	echo "core defaults should be editable inline without an edit button"
	exit 1
fi

if grep -Fq "Edit defaults" "$PAGE"; then
	echo "core defaults should not require entering an edit page"
	exit 1
fi

echo "test_operations_defaults_entry_ui: ok"
