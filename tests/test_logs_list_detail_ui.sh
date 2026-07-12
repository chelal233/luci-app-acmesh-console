#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PAGE="$ROOT/htdocs/luci-static/resources/view/acmesh/logs.js"
CTL="$ROOT/root/usr/libexec/acmesh-console/acmeshctl"
TASK_LIB="$ROOT/root/usr/libexec/acmesh-console/lib/task.sh"

require_text() {
	needle="$1"
	if ! grep -Fq -- "$needle" "$PAGE"; then
		echo "logs page missing: $needle"
		exit 1
	fi
}

require_text "renderTaskList"
require_text "renderTaskDetail"
require_text "acmeshApi.read('task_list'"
require_text "View task"
require_text "Refresh"
require_text "Back to tasks"

if ! grep -Fq "acmesh_task_list" "$TASK_LIB"; then
	echo "task library missing acmesh_task_list"
	exit 1
fi

if ! grep -Fq "task-list)" "$CTL"; then
	echo "acmeshctl missing task-list command"
	exit 1
fi

echo "test_logs_list_detail_ui: ok"
