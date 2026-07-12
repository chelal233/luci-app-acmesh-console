# acmesh Console Config Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add full configuration import and export for migrating acmesh-console between routers or plugin versions.

**Architecture:** Use the existing JSON config as the source of truth. Add a frontend migration panel in `operations_v2.js` that exports an envelope containing metadata plus the raw config, and imports either that envelope or a raw config object by calling existing `config-save`.

**Tech Stack:** LuCI JavaScript view, existing `fs.exec_direct` acmeshctl bridge, shell host tests.

## Global Constraints

- Export includes sensitive fields such as DNS credentials, pasted PEM, and SSH deployment settings.
- Import is overwrite-only for now.
- Import accepts file upload or pasted JSON.
- Import shows a parsed summary before saving.
- Do not create a second database or a second config path.

---

### Task 1: Operations UI Migration Panel

**Files:**
- Modify: `htdocs/luci-static/resources/view/acmesh/operations_v2.js`
- Modify: `tests/test_operations_profile_edit_ui.sh`
- Modify: `tests/test_i18n_support.sh`

**Interfaces:**
- Consumes: existing `config`, `saveConfig()`, `run([ 'config-get' ])`, `ui.addNotification`.
- Produces: `buildMigrationEnvelope()`, `parseMigrationConfig()`, `renderConfigMigration()`.

- [ ] **Step 1: Write failing tests**

Add marker tests for `renderConfigMigration`, `buildMigrationEnvelope`, `parseMigrationConfig`, `Import configuration`, `Export configuration`, `Paste configuration JSON`, and `Overwrite current configuration`.

- [ ] **Step 2: Run tests to verify failure**

Run: `sh tests/test_operations_profile_edit_ui.sh`
Expected: FAIL because the new migration markers are absent.

- [ ] **Step 3: Implement frontend panel**

Add export download, pasted JSON import, file import, summary generation, and overwrite save using `config-save`.

- [ ] **Step 4: Run focused and full tests**

Run: `node --check htdocs/luci-static/resources/view/acmesh/operations_v2.js`
Run: `sh tests/test_operations_profile_edit_ui.sh`
Run: `sh tests/run_host_tests.sh`
Expected: all pass.
