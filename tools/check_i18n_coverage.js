#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const poRoot = path.join(root, 'po');
const viewDir = path.join(root, 'htdocs', 'luci-static', 'resources', 'view', 'acmesh');
const sharedDir = path.join(root, 'htdocs', 'luci-static', 'resources', 'acmesh');

function unescapePo(text) {
	return text.replace(/\\"/g, '"').replace(/\\n/g, '\n').replace(/\\\\/g, '\\');
}

function unescapeJs(text) {
	return text.replace(/\\'/g, "'").replace(/\\n/g, '\n').replace(/\\\\/g, '\\');
}

function readCatalog(poPath) {
	const po = fs.readFileSync(poPath, 'utf8');
	const messages = new Map();
	const duplicates = [];
	const emptyTranslations = [];

	for (const match of po.matchAll(/^msgid "((?:\\.|[^"])*)"\r?\nmsgstr "((?:\\.|[^"])*)"/gm)) {
		const id = unescapePo(match[1]);
		if (!id)
			continue;

		if (messages.has(id))
			duplicates.push(id);

		const translation = unescapePo(match[2]);
		messages.set(id, translation);
		if (!translation)
			emptyTranslations.push(id);
	}

	return { messages, duplicates, emptyTranslations };
}

const sourceMsgids = new Set();
for (const entry of [ viewDir, sharedDir ].flatMap(dir => fs.readdirSync(dir).filter(name => name.endsWith('.js')).sort().map(file => [ dir, file ]))) {
	const text = fs.readFileSync(path.join(entry[0], entry[1]), 'utf8');
	for (const match of text.matchAll(/_\('((?:\\.|[^'])*)'\)/g))
		sourceMsgids.add(unescapeJs(match[1]));
}

const catalogs = fs.readdirSync(poRoot, { withFileTypes: true })
	.filter(entry => entry.isDirectory())
	.map(entry => ({
		locale: entry.name,
		path: path.join(poRoot, entry.name, 'acmesh-console.po')
	}))
	.filter(entry => fs.existsSync(entry.path))
	.sort((a, b) => a.locale.localeCompare(b.locale));

if (!catalogs.length) {
	console.error('No i18n catalogs found');
	process.exit(1);
}

const baselineEntry = catalogs.find(entry => entry.locale === 'zh_Hans');
if (!baselineEntry) {
	console.error('Missing baseline catalog: zh_Hans');
	process.exit(1);
}

const parsed = new Map(catalogs.map(entry => [ entry.locale, readCatalog(entry.path) ]));
const baseline = parsed.get('zh_Hans').messages;
const errors = [];

for (const id of sourceMsgids) {
	if (!baseline.has(id))
		errors.push(`zh_Hans: missing source msgid: ${id}`);
}

for (const entry of catalogs) {
	const catalog = parsed.get(entry.locale);
	for (const id of catalog.duplicates)
		errors.push(`${entry.locale}: duplicate msgid: ${id}`);
	for (const id of catalog.emptyTranslations)
		errors.push(`${entry.locale}: empty translation: ${id}`);
	for (const id of baseline.keys()) {
		if (!catalog.messages.has(id))
			errors.push(`${entry.locale}: missing baseline msgid: ${id}`);
	}
	for (const id of catalog.messages.keys()) {
		if (!baseline.has(id))
			errors.push(`${entry.locale}: unexpected msgid: ${id}`);
	}
}

if (errors.length) {
	console.error('i18n coverage errors:');
	for (const error of errors)
		console.error(`  ${error}`);
	process.exit(1);
}

console.log(`i18n coverage ok: ${catalogs.length} catalogs, ${baseline.size} msgids each, ${sourceMsgids.size} source strings`);
