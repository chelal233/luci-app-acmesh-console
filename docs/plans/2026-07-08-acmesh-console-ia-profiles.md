# Acmesh Console IA And Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse the LuCI app into Certificates, Operations, and Logs, while adding persistent UI profiles and global defaults so page switches never discard user work.

**Architecture:** acme.sh remains the certificate source of truth under `/etc/acme`. The console stores only UI defaults and operation profiles in `/etc/acmesh-console/config.json`; frontends load/edit/save this JSON through `acmeshctl config-get/config-save`. Operations reads global defaults for test mode, core tag, and default account email, then allows Account/Issue/Deploy entries to override where appropriate.

**Tech Stack:** OpenWrt LuCI JavaScript views, POSIX shell backend, JSON files without jq on router, host shell tests under `luci-app-acmesh-console/tests`.

## Global Constraints

- acme.sh state stays native and authoritative.
- UI defaults and profiles may persist under `/etc/acmesh-console/config.json`.
- Router runtime must not require Python, Node, or jq.
- Global Test Mode is a console default, not a per-tab checkbox.
- Account email is a default with account-profile overlay, not a Core field.
- Core tag is selectable/filterable and tag-pinned.

---

### Task 1: Persistent Console Config

**Files:**
- Create: `root/usr/libexec/acmesh-console/lib/config.sh`
- Modify: `root/usr/libexec/acmesh-console/acmeshctl`
- Create: `tests/test_config_profiles.sh`
- Modify: `tests/run_host_tests.sh`

**Interfaces:**
- Produces: `acmesh_config_get`, `acmesh_config_save`, `acmesh_config_value`.
- CLI: `acmeshctl config-get`, `acmeshctl config-save --json <json>`.

- [ ] Write a failing test that `config-get` emits defaults with `global.defaultAccountEmail`, `global.testMode`, `global.coreTag`, and empty account/issue/deploy arrays.
- [ ] Implement `config.sh` with default JSON and full-file save.
- [ ] Wire `config-get/config-save` into `acmeshctl`.
- [ ] Run `test_config_profiles.sh` and full host tests.

### Task 2: Global Defaults Drive Core And Issue

**Files:**
- Modify: `root/usr/libexec/acmesh-console/acmeshctl`
- Modify: `root/usr/libexec/acmesh-console/rpc`
- Modify: `tests/test_config_profiles.sh`

**Interfaces:**
- Consumes: `acmesh_config_value`.
- Behavior: missing `--test-mode` and `--tag` inherit from config; explicit CLI args still override.

- [ ] Extend tests to save `testMode=true` and `coreTag=v3.1.4`, then verify issue/core test-mode defaults.
- [ ] Modify issue/core command parsing to read config defaults.
- [ ] Modify RPC core methods to pass tag/email/testMode if supplied and otherwise let backend defaults apply.
- [ ] Run affected tests and full host tests.

### Task 3: Navigation Collapse

**Files:**
- Modify: `root/usr/share/luci/menu.d/luci-app-acmesh-console.json`
- Create: `htdocs/luci-static/resources/view/acmesh/operations.js`
- Modify: `htdocs/luci-static/resources/view/acmesh/certificates.js`
- Keep files but remove menu entries: `dashboard.js`, `core.js`, `issue.js`, `deploy.js`, `settings.js`.

**Interfaces:**
- Menu only exposes `Certificates`, `Operations`, and `Logs`.
- Root route aliases to `acmesh/certificates`.

- [ ] Modify menu JSON and validate parse.
- [ ] Add operations view with Account Profiles, Issue Profiles, Deploy Profiles, and Core panels.
- [ ] Merge dashboard/runtime summary into certificates view.
- [ ] Run JS syntax checks.

### Task 4: Profile CRUD UI

**Files:**
- Modify: `htdocs/luci-static/resources/view/acmesh/operations.js`

**Interfaces:**
- Uses `config-get/config-save` over `fs.exec_direct`.
- Persists `global`, `accountProfiles`, `issueProfiles`, `deployProfiles`.

- [ ] Implement global defaults editor.
- [ ] Implement account profile add/delete with inherited/effective email display.
- [ ] Implement issue profile add/delete with account/deploy selectors.
- [ ] Implement deploy profile add/delete for local and SSH.
- [ ] Make Core install/upgrade and Issue run buttons consume global defaults/profile fields.

### Task 5: Tag Filter UI

**Files:**
- Modify: `htdocs/luci-static/resources/view/acmesh/operations.js`

**Interfaces:**
- UI filters a local candidate list and permits manual tag entry.
- Default candidate list contains at least `v3.1.4`.

- [ ] Add core tag filter box and candidate selector.
- [ ] Selecting a tag updates `global.coreTag`.
- [ ] Core install/upgrade buttons use selected tag.
- [ ] Run JS syntax checks.

### Task 6: Deploy And Verify

**Files:**
- Deploy changed backend/menu/views to `10.0.0.228`.

**Verification:**
- Host tests all pass.
- Shell syntax passes.
- JS syntax passes.
- OpenWrt verifies menu, `config-get/config-save`, Operations resource, global testMode issue behavior, and tag-pinned core test-mode logs.
