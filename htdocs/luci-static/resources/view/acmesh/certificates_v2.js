'use strict';
'require view';
'require ui';
'require acmesh.api as acmeshApi';

function panel(title, value, warning) {
	return E('div', { 'class': 'acmesh-panel ' + (warning ? 'is-warning' : '') }, [
		E('span', {}, title),
		E('strong', {}, value || '-')
	]);
}

function editablePanel(title, node, warning) {
	return E('div', { 'class': 'acmesh-control-panel ' + (warning ? 'is-warning' : '') }, [
		E('span', {}, title),
		node
	]);
}

function coreVersionLabel(value) {
	value = (value == null ? '' : String(value)).trim();
	const matched = value.match(/v[0-9][0-9A-Za-z._-]*/);
	if (matched)
		return matched[0];
	if (value.indexOf('github.com/acmesh-official/acme.sh') >= 0)
		return _('Installed');
	return value || _('Unknown');
}

function versionPanel(title, node, currentVersion) {
	const label = coreVersionLabel(currentVersion);
	return E('div', { 'class': 'acmesh-control-panel acmesh-version-panel' }, [
		E('div', { 'class': 'acmesh-version-title' }, [
			E('span', {}, title),
			E('small', { 'class': 'acmesh-control-hint', 'title': currentVersion || '' }, _('Current core version') + ': ' + label)
		]),
		node,
	]);
}

function modePanel(title, node) {
	return E('div', { 'class': 'acmesh-control-panel acmesh-mode-panel' }, [
		E('span', {}, title),
		node
	]);
}

function renderTable(headers, rows, emptyText) {
	if (!rows.length)
		return E('div', { 'class': 'acmesh-empty' }, emptyText || _('No entries'));
	return E('table', { 'class': 'table acmesh-table' }, [
		E('thead', {}, E('tr', {}, headers.map(function(header) {
			return E('th', {}, header);
		}))),
		E('tbody', {}, rows.map(function(row) {
			return E('tr', {}, row.map(function(cell) {
				return E('td', {}, cell);
			}));
		}))
	]);
}

return view.extend({
	load: function() {
		return Promise.all([ acmeshApi.read('status'), acmeshApi.read('core_status'), acmeshApi.read('config_get') ]);
	},

	render: function(results) {
		let data = results[0] || {};
		const core = results[1] || {};
		const config = results[2] || {};
		config.global = config.global || {};
		const global = config.global;
		const deps = core.dependencies || {};
		let certs = Array.isArray(data.certificates) ? data.certificates : [];
		const deployProfiles = Array.isArray(config.deployProfiles) ? config.deployProfiles : [];
		let selectedKey = '';
		const body = E('div', { 'class': 'acmesh-body' });
		const taskBox = E('pre', { 'class': 'acmesh-terminal' }, '');

		const certKey = function(cert) {
			return [ cert.mainDomain || '', cert.keyType || '', cert.domainConf || '' ].join('|');
		};

		const setView = function(key) {
			selectedKey = key || '';
			renderBody();
			return Promise.resolve();
		};

		const selectedCert = function() {
			return certs.filter(function(cert) { return certKey(cert) === selectedKey; })[0] || null;
		};

		const saveConfig = function() {
			return acmeshApi.write('config_save', config).then(function(res) {
				if (!res.ok)
					ui.addNotification(null, E('p', {}, res.error || _('Unable to save config')), 'danger');
				return res;
			});
		};

		const refreshCertificates = function() {
			return acmeshApi.read('status').then(function(next) {
				data = next || {};
				certs = Array.isArray(data.certificates) ? data.certificates : [];
				selectedKey = '';
				renderBody();
			});
		};

		const showTask = function(res) {
			if (!res.taskId) {
				taskBox.textContent = res.error || _('Unable to create task');
				return Promise.resolve();
			}
			return new Promise(function(resolve) {
				window.setTimeout(resolve, 900);
			}).then(function() {
				return Promise.all([
					acmeshApi.read('task_status', [ res.taskId ]),
					acmeshApi.read('task_log', [ res.taskId ])
				]).then(function(taskResults) {
					taskBox.textContent = [
						'Task: ' + res.taskId,
						'Status: ' + (taskResults[0].status || '-'),
						'Stage: ' + (taskResults[0].stage || '-'),
						'',
						taskResults[1].log || ''
					].join('\n');
				});
			});
		};

		const input = function(value, placeholder) {
			return E('input', {
				'class': 'cbi-input-text',
				'type': 'text',
				'value': value || '',
				'placeholder': placeholder || ''
			});
		};

		const select = function(value, choices) {
			return E('select', { 'class': 'cbi-input-select' }, choices.map(function(choice) {
				return E('option', { 'value': choice[0], 'selected': choice[0] === value ? 'selected' : null }, choice[1]);
			}));
		};

		const field = function(label, node) {
			return E('label', { 'class': 'acmesh-field' }, [
				E('span', {}, label),
				node
			]);
		};

		const deployProfileById = function(profileId) {
			return deployProfiles.filter(function(profile) {
				return profile.id === profileId;
			})[0] || null;
		};

		const deployProfileLabel = function(profile) {
			return (profile.name || profile.id || _('Deploy profile')) + ' / ' + (profile.type || 'local');
		};

		const deployProfileSelect = function(cert) {
			const choices = [[ '', deployProfiles.length ? _('Select deploy profile') : _('No deploy profile') ]].concat(deployProfiles.map(function(profile) {
				return [ profile.id, deployProfileLabel(profile) ];
			}));
			const node = select('', choices);
			node.setAttribute('data-acmesh-cert-domain', cert.mainDomain || '');
			return node;
		};

		const validateDeployProfile = function(profile) {
			const missing = [];
			const certSource = profile.certSource || 'managed-acme';
			const deployType = profile.type || 'local';
			if (certSource === 'managed-acme' && !profile.domain)
				missing.push(_('Certificate domain'));
			if (certSource === 'local-files') {
				if (!profile.sourceKeyFile)
					missing.push(_('Source key file'));
				if (!profile.sourceFullchainFile)
					missing.push(_('Source fullchain file'));
			}
			if (certSource === 'paste-pem') {
				if (!profile.keyPem)
					missing.push(_('Private key PEM'));
				if (!profile.fullchainPem)
					missing.push(_('Fullchain PEM'));
			}
			if (!profile.keyFile)
				missing.push(deployType === 'ssh' ? _('Remote key file') : _('Local key file'));
			if (!profile.fullchainFile)
				missing.push(deployType === 'ssh' ? _('Remote fullchain file') : _('Local fullchain file'));
			if (deployType === 'ssh' && !profile.host)
				missing.push(_('SSH host'));
			return missing.length ? _('Missing deploy fields') + ': ' + missing.join(', ') : '';
		};

		const prepareDeploy = function(profile, cert) {
			return {
				method: global.testMode === false ? 'deploy_run' : 'deploy_test',
				payload: { profileId: profile.id },
				profile: profile
			};
		};

		const coreTagChoices = [
			[ 'v3.1.4', 'v3.1.4' ],
			[ 'v3.1.3', 'v3.1.3' ],
			[ 'v3.1.2', 'v3.1.2' ],
			[ 'v3.0.9', 'v3.0.9' ]
		];

		const saveCoreDefaults = function(email, testMode, acmeHome, tagList) {
			global.defaultAccountEmail = email.value.trim();
			global.testMode = !!testMode.checked;
			global.acmeHome = acmeHome.value.trim() || '/etc/acme';
			global.coreTag = tagList.value || 'v3.1.4';
			return saveConfig();
		};

		const coreTaskPayload = function(email, testMode, acmeHome, tagList) {
			return {
				home: acmeHome.value.trim() || '/etc/acme',
				tag: tagList.value || 'v3.1.4',
				email: email.value.trim(),
				testMode: !!testMode.checked
			};
		};

		const importHistory = function() {
			taskBox.textContent = _('Creating task') + '...';
			return acmeshApi.write('import_apply', { source: 'history' }).then(showTask).then(refreshCertificates);
		};

		const renewCertificate = function(cert) {
			taskBox.textContent = _('Creating task') + '...';
			return acmeshApi.write('renew', {
				domain: cert.mainDomain || '',
				keyType: cert.keyType || '',
				testMode: global.testMode !== false
			}).then(showTask);
		};

		const deployCertificateWithProfile = function(cert, profileSelect) {
			const profile = deployProfileById(profileSelect.value);
			if (!profile) {
				taskBox.textContent = _('Select deploy profile');
				ui.addNotification(null, E('p', {}, _('Select deploy profile')), 'danger');
				return Promise.resolve();
			}
			const prepared = prepareDeploy(profile, cert);
			const validationError = validateDeployProfile(prepared.profile);
			if (validationError) {
				taskBox.textContent = validationError;
				ui.addNotification(null, E('p', {}, validationError), 'danger');
				return Promise.resolve();
			}
			taskBox.textContent = _('Creating task') + '...';
			return acmeshApi.write(prepared.method, prepared.payload).then(showTask);
		};

		const renderSummary = function() {
			const email = input(global.defaultAccountEmail || '', 'name@example.com');
			const testMode = E('input', { 'type': 'checkbox', 'checked': global.testMode !== false ? 'checked' : null });
			const acmeHome = input(global.acmeHome || core.home || data.home || '/etc/acme', '/etc/acme');
			const tagList = select(global.coreTag || 'v3.1.4', coreTagChoices);

			return E('div', { 'class': 'acmesh-summary-block' }, [
				E('div', { 'class': 'acmesh-summary' }, [
					panel(_('Core script'), core.script || _('Not installed'), !core.installed),
					panel(_('OpenSSL'), deps.openssl ? _('Ready') : _('Missing'), !deps.openssl)
				]),
				E('div', { 'class': 'acmesh-summary-controls acmesh-controls-shell' }, [
					editablePanel(_('acme.sh home'), acmeHome),
					editablePanel(_('Default account email'), email),
					versionPanel(_('Core tag candidates'), tagList, core.version),
					modePanel(_('Mode'), E('span', { 'class': 'acmesh-inline' }, [ testMode, E('span', {}, _('Global Test Mode')) ])),
					E('div', { 'class': 'acmesh-primary-actions acmesh-summary-actions' }, [
						E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': ui.createHandlerFn(this, function() {
							return saveCoreDefaults(email, testMode, acmeHome, tagList).then(function(res) {
								taskBox.textContent = res.ok ? 'OK' : (res.error || _('Unable to save config'));
							});
						}) }, _('Save defaults')),
						E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': ui.createHandlerFn(this, function() {
							return saveCoreDefaults(email, testMode, acmeHome, tagList).then(function(res) {
								if (!res.ok)
									return res;
								return acmeshApi.write('core_install', coreTaskPayload(email, testMode, acmeHome, tagList)).then(showTask);
							});
						}) }, _('Install selected tag')),
						E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': ui.createHandlerFn(this, function() {
							return saveCoreDefaults(email, testMode, acmeHome, tagList).then(function(res) {
								if (!res.ok)
									return res;
								return acmeshApi.write('core_upgrade', coreTaskPayload(email, testMode, acmeHome, tagList)).then(showTask);
							});
						}) }, _('Upgrade selected tag'))
					])
				])
			]);
		};

		const renderCertificateList = function() {
			const rows = certs.map(function(cert) {
				const raw = cert.rawVars || {};
				const profileSelect = deployProfileSelect(cert);
				return [
					cert.mainDomain || '-',
					(cert.keyType || '-').toUpperCase(),
					raw.Le_Domain || cert.mainDomain || '-',
					raw.Le_Alt || '-',
					cert.domainConf || '-',
					E('div', { 'class': 'acmesh-row-actions' }, [
						E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': ui.createHandlerFn(this, function() {
							return setView(certKey(cert));
						}) }, _('View certificate')),
						E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': ui.createHandlerFn(this, function() {
							return renewCertificate(cert);
						}) }, _('Renew')),
						profileSelect,
						E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': ui.createHandlerFn(this, function() {
							return deployCertificateWithProfile(cert, profileSelect);
						}) }, _('Deploy'))
					])
				];
			}, this);

			return E('div', { 'class': 'acmesh-section' }, [
				E('h2', {}, _('Certificates')),
				renderSummary(),
				E('div', { 'class': 'acmesh-actions' }, [
					E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': ui.createHandlerFn(this, importHistory) }, _('Import history')),
					E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': ui.createHandlerFn(this, refreshCertificates) }, _('Refresh'))
				]),
				renderTable([ _('Domain'), _('Key type'), _('Primary'), _('SAN'), _('Config'), '' ], rows, _('No certificates found'))
			]);
		}.bind(this);

		const renderCertificateDetail = function() {
			const cert = selectedCert();
			if (!cert)
				return renderCertificateList();
			const raw = cert.rawVars || {};
			const profileSelect = deployProfileSelect(cert);
			return E('div', { 'class': 'acmesh-section' }, [
				E('h2', {}, _('View certificate') + ': ' + (cert.mainDomain || '-')),
				renderSummary(),
				E('div', { 'class': 'acmesh-actions' }, [
					E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': ui.createHandlerFn(this, function() {
						return setView('');
					}) }, _('Back to certificates')),
					E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': ui.createHandlerFn(this, function() {
						return renewCertificate(cert);
					}) }, _('Renew')),
					profileSelect,
					E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': ui.createHandlerFn(this, function() {
						return deployCertificateWithProfile(cert, profileSelect);
					}) }, _('Deploy'))
				]),
				renderTable([ _('Field'), _('Value') ], [
					[ _('Domain'), cert.mainDomain || '-' ],
					[ _('Key type'), (cert.keyType || '-').toUpperCase() ],
					[ _('Config'), cert.domainConf || '-' ],
					[ 'Le_Domain', raw.Le_Domain || '-' ],
					[ 'Le_Alt', raw.Le_Alt || '-' ],
					[ 'Le_Webroot', raw.Le_Webroot || '-' ],
					[ 'Le_API', raw.Le_API || '-' ]
				], _('No certificate details')),
				E('h3', {}, _('Native variables')),
				E('pre', { 'class': 'acmesh-terminal' }, JSON.stringify(raw, null, 2))
			]);
		}.bind(this);

		function renderBody() {
			body.innerHTML = '';
			body.appendChild(selectedKey ? renderCertificateDetail() : renderCertificateList());
		}

		const root = E('div', { 'class': 'cbi-map acmesh-certs' }, [
			E('style', {}, `
.acmesh-certs .acmesh-section { margin:0 0 16px; padding:16px 0; border-bottom:1px solid rgba(127,127,127,.24); }
.acmesh-certs .acmesh-summary-block { display:grid; gap:12px; margin-bottom:16px; }
.acmesh-certs .acmesh-summary { display:grid; grid-template-columns:repeat(auto-fit, minmax(260px, 1fr)); gap:12px; }
.acmesh-certs .acmesh-panel { border:1px solid rgba(127,127,127,.28); border-radius:8px; padding:14px; background:rgba(127,127,127,.08); }
.acmesh-certs .acmesh-panel.is-warning { border-color:rgba(214,158,46,.55); background:rgba(214,158,46,.14); }
.acmesh-certs .acmesh-panel span { display:block; color:inherit; opacity:.72; }
.acmesh-certs .acmesh-panel strong { display:block; font-size:16px; margin-top:4px; word-break:break-all; }
.acmesh-certs .acmesh-summary-controls { display:grid; grid-template-columns:minmax(220px, 1fr) minmax(220px, 1fr) minmax(260px, 1.15fr) minmax(150px, .55fr) minmax(360px, max-content); gap:12px; align-items:end; padding:12px; border:1px solid rgba(127,127,127,.28); border-radius:8px; background:rgba(127,127,127,.08); }
.acmesh-certs .acmesh-control-panel { min-width:0; }
.acmesh-certs .acmesh-control-panel span { display:block; color:inherit; opacity:.82; font-weight:700; margin-bottom:6px; }
.acmesh-certs .acmesh-control-panel input, .acmesh-certs .acmesh-control-panel select { width:100%; box-sizing:border-box; min-height:34px; }
.acmesh-certs .acmesh-version-title { display:flex; align-items:baseline; gap:8px; min-width:0; margin-bottom:6px; }
.acmesh-certs .acmesh-version-title span { display:inline; flex:0 0 auto; margin-bottom:0; }
.acmesh-certs .acmesh-control-hint { display:inline; min-width:0; color:inherit; opacity:.68; line-height:1.35; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.acmesh-certs .acmesh-mode-panel { min-width:190px; }
.acmesh-certs .acmesh-mode-panel .acmesh-inline { min-height:34px; align-items:center; }
.acmesh-certs .acmesh-mode-panel input[type="checkbox"] { width:18px; min-width:18px; min-height:18px; margin:0; }
.acmesh-certs .acmesh-primary-actions { display:flex; flex-wrap:nowrap; justify-content:flex-end; align-self:end; gap:8px; }
.acmesh-certs .acmesh-primary-actions button { min-height:34px; white-space:nowrap; }
.acmesh-certs .acmesh-actions { display:flex; flex-wrap:wrap; gap:10px; margin:12px 0 16px; }
.acmesh-certs .acmesh-field span { display:block; font-weight:600; margin-bottom:6px; }
.acmesh-certs .acmesh-field input, .acmesh-certs .acmesh-field select { width:100%; box-sizing:border-box; }
.acmesh-certs .acmesh-inline { display:flex; gap:8px; align-items:center; min-height:30px; }
.acmesh-certs .acmesh-table { width:100%; border-collapse:collapse; margin-top:12px; }
.acmesh-certs .acmesh-table th { background:rgba(127,127,127,.10); font-weight:700; }
.acmesh-certs .acmesh-table th, .acmesh-certs .acmesh-table td { padding:11px 12px; border-bottom:1px solid rgba(127,127,127,.24); vertical-align:middle; }
.acmesh-certs .acmesh-row-actions { display:flex; justify-content:flex-end; gap:8px; }
.acmesh-certs .acmesh-row-actions select { min-width:190px; max-width:260px; }
.acmesh-certs .acmesh-empty { padding:18px; background:rgba(127,127,127,.08); border:1px solid rgba(127,127,127,.28); border-radius:8px; color:inherit; opacity:.72; }
.acmesh-certs .acmesh-terminal { margin-top:10px; min-height:160px; padding:12px; border-radius:8px; background:#101418; color:#d7e1ea; overflow:auto; line-height:1.45; white-space:pre-wrap; overflow-wrap:anywhere; }
@media (max-width:1450px) {
	.acmesh-certs .acmesh-summary-controls { grid-template-columns:repeat(2, minmax(240px, 1fr)); }
	.acmesh-certs .acmesh-primary-actions { justify-content:flex-start; }
}
			`),
			body,
			E('h3', {}, _('Last action')),
			taskBox
		]);

		window.setTimeout(renderBody, 0);
		return root;
	}
});
