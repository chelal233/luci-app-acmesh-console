#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const poPath = path.join(root, 'po', 'zh_Hans', 'acmesh-console.po');
const viewDir = path.join(root, 'htdocs', 'luci-static', 'resources', 'view', 'acmesh');

function unescapePo(text) {
	return text.replace(/\\"/g, '"').replace(/\\n/g, '\n').replace(/\\\\/g, '\\');
}

function unescapeJs(text) {
	return text.replace(/\\'/g, "'").replace(/\\n/g, '\n').replace(/\\\\/g, '\\');
}

const po = fs.readFileSync(poPath, 'utf8');
const msgids = new Set();
for (const match of po.matchAll(/^msgid "((?:\\.|[^"])*)"/gm)) {
	const id = unescapePo(match[1]);
	if (id)
		msgids.add(id);
}

const missing = [];
for (const file of fs.readdirSync(viewDir).filter(name => name.endsWith('.js')).sort()) {
	const text = fs.readFileSync(path.join(viewDir, file), 'utf8');
	for (const match of text.matchAll(/_\('((?:\\.|[^'])*)'\)/g)) {
		const id = unescapeJs(match[1]);
		if (!msgids.has(id))
			missing.push(`${file}: ${id}`);
	}
}

if (missing.length) {
	console.error('Missing i18n msgids:');
	for (const item of missing)
		console.error(`  ${item}`);
	process.exit(1);
}

console.log(`i18n coverage ok: ${msgids.size} msgids`);
