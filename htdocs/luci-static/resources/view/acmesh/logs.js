'use strict';
'require view';
'require ui';
'require acmesh.api as acmeshApi';

function readTask(taskId) {
	return Promise.all([
		acmeshApi.read('task_status', [ taskId ]),
		acmeshApi.read('task_log', [ taskId ])
	]).then(function(results) {
		return {
			status: results[0] || {},
			log: (results[1] && results[1].log) || ''
		};
	});
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
		return acmeshApi.read('task_list', [ '80' ]);
	},

	render: function(initial) {
		let tasks = Array.isArray(initial.tasks) ? initial.tasks : [];
		let selectedTaskId = '';
		const body = E('div', { 'class': 'acmesh-body' });

		const refreshList = function() {
			return acmeshApi.read('task_list', [ '80' ]).then(function(res) {
				tasks = Array.isArray(res.tasks) ? res.tasks : [];
				selectedTaskId = '';
				renderBody();
			});
		};

		const openTask = function(taskId) {
			selectedTaskId = taskId;
			renderBody();
			return Promise.resolve();
		};

		const renderTaskList = function() {
			const rows = tasks.map(function(task) {
				return [
					task.taskId || '-',
					task.operation || '-',
					task.status || '-',
					task.stage || '-',
					task.exitCode == null ? '-' : String(task.exitCode),
					E('div', { 'class': 'acmesh-row-actions' }, [
						E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': ui.createHandlerFn(this, function() {
							return openTask(task.taskId);
						}) }, _('View task'))
					])
				];
			}, this);

			return E('div', { 'class': 'acmesh-section' }, [
				E('h2', {}, _('Task Logs')),
				E('div', { 'class': 'acmesh-actions' }, [
					E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': ui.createHandlerFn(this, refreshList) }, _('Refresh'))
				]),
				renderTable([ _('Task ID'), _('Operation'), _('Status'), _('Stage'), _('Exit'), '' ], rows, _('No tasks found'))
			]);
		}.bind(this);

		const renderTaskDetail = function() {
			const output = E('pre', { 'class': 'acmesh-terminal' }, _('Loading task') + '...');
			window.setTimeout(function() {
				readTask(selectedTaskId).then(function(res) {
					output.textContent = [
						JSON.stringify(res.status, null, 2),
						'',
						res.log
					].join('\n');
				});
			}, 0);

			return E('div', { 'class': 'acmesh-section' }, [
				E('h2', {}, _('View task') + ': ' + selectedTaskId),
				E('div', { 'class': 'acmesh-actions' }, [
					E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': ui.createHandlerFn(this, function() {
						selectedTaskId = '';
						renderBody();
						return Promise.resolve();
					}) }, _('Back to tasks')),
					E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': ui.createHandlerFn(this, function() {
						return readTask(selectedTaskId).then(function(res) {
							output.textContent = [
								JSON.stringify(res.status, null, 2),
								'',
								res.log
							].join('\n');
						});
					}) }, _('Refresh'))
				]),
				output
			]);
		}.bind(this);

		function renderBody() {
			body.innerHTML = '';
			body.appendChild(selectedTaskId ? renderTaskDetail() : renderTaskList());
		}

		const root = E('div', { 'class': 'cbi-map acmesh-logs' }, [
			E('style', {}, `
.acmesh-logs .acmesh-section { margin:0 0 16px; padding:16px 0; border-bottom:1px solid #e3e8ef; }
.acmesh-logs .acmesh-actions { display:flex; flex-wrap:wrap; gap:10px; margin:12px 0 16px; }
.acmesh-logs .acmesh-table { width:100%; border-collapse:collapse; margin-top:12px; }
.acmesh-logs .acmesh-table th { background:#f1f4f8; font-weight:700; }
.acmesh-logs .acmesh-table th, .acmesh-logs .acmesh-table td { padding:11px 12px; border-bottom:1px solid #e2e7ef; vertical-align:middle; }
.acmesh-logs .acmesh-row-actions { display:flex; justify-content:flex-end; gap:8px; }
.acmesh-logs .acmesh-empty { padding:18px; background:#f7f9fb; border:1px solid #d7dde5; border-radius:8px; color:#667085; }
.acmesh-logs .acmesh-terminal { min-height:260px; padding:12px; border-radius:8px; background:#101418; color:#d7e1ea; overflow:auto; line-height:1.45; white-space:pre-wrap; overflow-wrap:anywhere; }
			`),
			body
		]);

		window.setTimeout(renderBody, 0);
		return root;
	}
});
