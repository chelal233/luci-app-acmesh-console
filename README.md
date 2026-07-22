# luci-app-acmesh-console

## Purpose

`luci-app-acmesh-console` is a LuCI operator console for the official `acme.sh` client. It manages accounts, issuance profiles, certificate discovery, deployment profiles, task logs, SSH host identity, and explicit authorization for operations with external consequences.

## Supported OpenWrt and LuCI baseline

The package targets current OpenWrt/ImmortalWrt releases with LuCI, `rpcd`, POSIX `sh`, `jsonfilter`, OpenSSL, curl, tar, Dropbear conversion tools, and OpenSSH client utilities. The package build metadata is the authoritative dependency list for a given release.

## Official acme.sh relationship

[`acmesh-official/acme.sh`](https://github.com/acmesh-official/acme.sh) is the only ACME behavior authority. This project is an independent console and does not replace, fork, or reinterpret the client. Command construction and supported CA/DNS behavior must remain compatible with the official client.

## Installation and dependencies

Build the package in an OpenWrt SDK or buildroot and install the resulting package with the platform package manager. Required runtime dependencies are declared in `Makefile`; do not remove `jsonfilter`, `dropbearconvert`, or the SSH client utilities from a custom build.

For the verified Windows + WSL2 workflow covering SDK APK builds, x86-64/ext4 ImageBuilder images, the existing third-party plugin set, full source builds, router tests, and release gates, see [`docs/IMMORTALWRT_BUILD_WORKFLOW.md`](docs/IMMORTALWRT_BUILD_WORKFLOW.md).

GitHub Actions can build release packages for ten common architectures. Run **Build release packages** manually to obtain workflow artifacts, or push a tag matching `v<PKG_VERSION>` (for example, `v0.1.0`) to build and attach all packages to a GitHub release. OpenWrt 24.10 jobs produce `.ipk` files for `opkg`; OpenWrt SNAPSHOT jobs produce `.apk` files for `apk`. This LuCI application is not an Entware package, so the workflow deliberately does not publish misleading `.opk` aliases.

After installation, open **Services → acme.sh Console** in LuCI. The package keeps private state under `/etc/acmesh-console` with directory mode `0700` and private files mode `0600`.

## Accounts, issue profiles, deploy profiles

Account profiles select the CA and effective contact address. Issue profiles hold the primary domain, normalized SAN list, key type, validation method, DNS provider settings, and optional linked deployment. Deploy profiles identify a managed certificate or local source and define local or SSH destinations plus the reload command.

Production issue and deploy actions submit profile identifiers to the backend. The backend reloads the saved profile and creates the final operation snapshot; the browser does not claim that a payload is authorized.

## Test mode versus Let's Encrypt staging

Test mode is a no-mutation command-validation path: it must not send an ACME request, change DNS, deploy files, reload a service, consume a challenge, or create remembered authorization. It is separate from selecting the Let's Encrypt staging directory. Staging is still a real remote ACME service and may perform DNS validation, so staging operations require the same risk authorization as other real operations.

There is no global test-mode or global debug bypass. Select test behavior on the operation/profile that needs it.

## Risk authorization and revocation

Real issue, renew, deploy, core install/upgrade, SSH key conversion, and secret export require either a matching router-local remembered authorization or an explicit decision. The dialog and CLI offer **Run once** and, where permitted, **Run and remember**. Certificate revoke/remove, profile deletion, and import overwrite are always one-time decisions.

Authorization accepts the business consequences shown in the exact backend-generated summary. It never disables secret masking, private files, ACL separation, host-key verification, validated destinations, atomic task state, or deployment rollback guarantees.

Remembered records are local to the router and can be revoked individually or all at once from **Operations → Authorization records**. Material changes to the operation invalidate reuse.

For direct CLI calls, sensitive JSON is read from stdin and never supplied as process arguments:

```sh
printf '%s\n' '{"profileId":"example"}' | \
  /usr/libexec/acmesh-console/acmeshctl issue --request-stdin
```

When a real call returns `authorizationRequired`, execute the returned challenge once or remember it:

```sh
/usr/libexec/acmesh-console/acmeshctl --acknowledge-risk CHALLENGE_ID
/usr/libexec/acmesh-console/acmeshctl --remember-authorization CHALLENGE_ID
```

There is no global `--yes`, `--force-all`, or disable-confirmations option.

## SSH host-key pinning and temporary key conversion

Unknown SSH hosts require a separate display of host, port, key algorithm, and SHA-256 fingerprint. Confirmation pins that identity in the console-owned private `known_hosts`. A changed key is a hard stop; verify the host independently before replacing trust.

When Dropbear requires conversion of an OpenSSH private key, conversion is separately authorized, uses a private temporary file only for that deployment, and removes it afterward.

## Configuration migration exclusions

Configuration migration can include profiles and their operational secrets. Treat exported JSON as sensitive. It deliberately excludes router identity, remembered authorizations, pinned SSH host identities, the console SSH private key, tasks, logs, and pending challenges. Importing configuration on another router never imports trust.

## Router-side verification commands

From the installed source/test tree, run:

```sh
sh /usr/libexec/acmesh-console/tests/run_host_tests.sh
busybox stat -c '%a %n' \
  /etc/acmesh-console \
  /etc/acmesh-console/authorizations.json \
  /var/run/acmesh-console/requests \
  /var/run/acmesh-console/authorization-challenges
ls /www/luci-static/resources/view/acmesh/operations*.js
```

The full suite must end with `all host tests passed`; private directories/files must remain `700/600`; only `operations_v2.js` should be installed.

## Security reporting and license

Do not include DNS tokens, passwords, PEM content, task-private files, or exported configuration in public reports. Report a suspected security issue privately to the package maintainer with the affected version, operation, and a redacted reproduction.

This project is licensed under GPL-3.0-or-later. See `LICENSE`.
