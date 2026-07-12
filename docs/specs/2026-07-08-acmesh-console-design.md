# luci-app-acmesh-console Design

## Purpose

Build a new OpenWrt LuCI application for acmesh-official/acme.sh. The project is not a patch of OpenWrt's old `luci-app-acme`; it is a new acme.sh console. OpenWrt is only the runtime environment. The source of truth is acme.sh itself:

- acme.sh commands
- acme.sh home directory
- `account.conf`
- per-domain `*.conf`
- `dnsapi`
- `deploy` hooks
- `--install-cert`
- `--reloadcmd`
- acme.sh upgrade behavior

The old OpenWrt packages are useful as reference material, but they do not define compatibility requirements for this project.

## Product Principles

1. acme.sh owns certificate state. LuCI reads and explains it.
2. Command line changes must appear in the web UI after refresh.
3. Web UI operations must compile down to acme.sh-native commands, variables, install-cert options, or deploy hooks.
4. UCI is not the certificate source of truth. It may store UI preferences and console metadata only.
5. Dangerous actions require explicit confirmation: upgrading acme.sh, deleting certificates, replacing remote files, or running remote commands.
6. Unknown acme.sh variables must be preserved and visible in an advanced raw view.

## Package Shape

The package name is:

```text
luci-app-acmesh-console
```

Expected source layout:

```text
luci-app-acmesh-console/
  Makefile
  htdocs/luci-static/resources/view/acmesh/
  htdocs/luci-static/resources/acmesh/
  root/usr/share/luci/menu.d/
  root/usr/share/rpcd/acl.d/
  root/usr/libexec/acmesh-console/
  root/etc/init.d/
  root/etc/config/
  root/etc/acmesh-console/
  tests/
```

The application exposes a LuCI dashboard and a backend RPC helper. The backend may be implemented as POSIX shell plus OpenWrt JSON helpers. It must not require Python, Node, or jq on the router.

## Runtime Locations

Default acme.sh home candidates:

```text
/etc/acme
/root/.acme.sh
/usr/lib/acme
```

Users may set a custom home path. Detection succeeds when the candidate has enough acme.sh-native evidence:

- executable `acme.sh`, or a configured acme.sh binary path
- `account.conf`, or domain directories containing `*.conf`
- acme.sh can run with `--home <path> --info` or an equivalent read-only command

The console stores its own non-authoritative metadata under:

```text
/etc/acmesh-console/
```

Examples:

```text
/etc/acmesh-console/config.json
/etc/acmesh-console/certs/example.com_ecc.json
/etc/acmesh-console/ssh/id_ed25519
/etc/acmesh-console/ssh/id_ed25519.pub
/etc/acmesh-console/ssh/known_hosts
```

## Backend RPC

The backend provides these capability groups:

### Status

- Detect acme.sh home and version.
- Read account registration state.
- Scan domain directories.
- Parse domain configuration files.
- Read certificate validity with `openssl x509`.
- Return ECC and RSA certificates separately but grouped by main domain.
- Report cron or scheduled renewal state when detectable.

### Core Management

- Check installed acme.sh version.
- Check current upstream status when network is available.
- Upgrade acme.sh from acmesh-official/acme.sh only after confirmation.
- Create a local backup before replacing the script.
- Keep upgrade logs.

### Certificate Operations

- Issue.
- Renew.
- Install certificate.
- Revoke.
- Remove.

The frontend cannot pass arbitrary shell snippets for these operations. It sends structured JSON. The backend builds a whitelisted command.

### DNS Templates

The UI presents provider-specific forms. The backend maps friendly fields to acme.sh variables and `--dns dns_xxx` identifiers.

Initial providers:

- Cloudflare
- Aliyun
- Tencent Cloud / DNSPod
- DuckDNS
- dynv6
- Advanced `dns_xxx` mode

Provider definitions live under:

```text
/usr/libexec/acmesh-console/providers/
```

### Deploy And Post-Action

The console supports:

- local `--install-cert`
- local reload command
- remote SSH certificate upload
- remote reload command
- connection test
- upload test
- real deploy with confirmation

Remote deploy is implemented as an acme.sh deploy hook where possible. It must participate in the renewal lifecycle instead of being a one-time copy button.

### Task Logs

Every long operation creates a task id and writes:

```text
/var/run/acmesh-console/tasks/<task-id>.json
/var/log/acmesh-console/tasks/<task-id>.log
```

The task state includes:

- task id
- operation
- stage
- status
- start time
- end time
- exit code
- last error
- command preview with secrets masked

The frontend polls task state and appended log output.

## Data Model

Backend status response:

```json
{
  "home": "/etc/acme",
  "acmeVersion": "3.x",
  "account": {
    "email": "admin@example.com",
    "ca": "letsencrypt",
    "registered": true,
    "rawVars": {}
  },
  "certificates": [
    {
      "mainDomain": "example.com",
      "domains": ["example.com", "*.example.com"],
      "keyType": "ecc",
      "ca": "letsencrypt",
      "issueMode": "dns",
      "dnsProvider": "dns_cf",
      "status": "valid",
      "notBefore": "2026-07-01T00:00:00Z",
      "notAfter": "2026-09-29T00:00:00Z",
      "daysLeft": 83,
      "paths": {
        "domainConf": "/etc/acme/example.com_ecc/example.com.conf",
        "cert": "/etc/acme/example.com_ecc/example.com.cer",
        "key": "/etc/acme/example.com_ecc/example.com.key",
        "fullchain": "/etc/acme/example.com_ecc/fullchain.cer"
      },
      "deploy": {
        "managedByConsole": false,
        "targets": []
      },
      "rawVars": {}
    }
  ]
}
```

Recognition rules:

- ECC directories commonly end in `_ecc`.
- RSA and ECC for the same main domain are shown as sibling certificate variants.
- Validity dates come from the certificate file, not only from `domain.conf`.
- Known acme.sh variables are mapped to friendly fields.
- Unknown variables stay in `rawVars`.
- Advanced editing must show a diff and preserve unrelated variables.

## DNS Signing Flow

The signing wizard:

1. Enter main domain and SAN domains.
2. Detect wildcard names and force DNS-01 when needed.
3. Select CA: ZeroSSL, Let's Encrypt, Google Trust Services, or custom ACME server.
4. Select key type: ECC by default, RSA optional.
5. Select validation mode.
6. Select DNS provider template when using DNS-01.
7. Configure deploy target if desired.
8. Preview the masked acme.sh command.
9. Run issue and stream the task log.

Cloudflare example template:

```json
{
  "id": "cloudflare",
  "title": "Cloudflare",
  "acmeDnsApi": "dns_cf",
  "recommendedMode": "token",
  "modes": [
    {
      "id": "token",
      "title": "Token",
      "fields": [
        {
          "name": "token",
          "label": "API Token",
          "secret": true,
          "mapsTo": "CF_Token"
        }
      ]
    },
    {
      "id": "global_key",
      "title": "Global Key",
      "fields": [
        {
          "name": "email",
          "label": "Account Email",
          "mapsTo": "CF_Email"
        },
        {
          "name": "key",
          "label": "Global API Key",
          "secret": true,
          "mapsTo": "CF_Key"
        }
      ]
    }
  ]
}
```

Advanced fields such as challenge alias and domain alias are collapsed by default and described in plain Chinese. Normal users are told to leave them empty.

## Deploy Flow

The deploy page has three target types:

1. Local install.
2. Remote SSH upload and reload.
3. Command-only post-action.

Remote SSH fields:

- host
- port
- user
- private key path
- remote key path
- remote fullchain path
- remote cert path
- remote CA path
- remote reload command

The console provides:

- generate SSH key
- show public key
- copy public key
- fetch and confirm host key
- connection test
- upload test
- real deploy

Remote deploy environment:

```text
ACMESH_DEPLOY_HOST=1.2.3.4
ACMESH_DEPLOY_PORT=22
ACMESH_DEPLOY_USER=root
ACMESH_DEPLOY_KEY=/etc/acmesh-console/ssh/id_ed25519
ACMESH_DEPLOY_FULLCHAIN=/etc/ssl/private/example.fullchain.pem
ACMESH_DEPLOY_KEYFILE=/etc/ssl/private/example.key
ACMESH_DEPLOY_CERTFILE=
ACMESH_DEPLOY_CAFILE=
ACMESH_DEPLOY_RELOADCMD=sudo systemctl restart ocserv
```

The hook uploads to temporary files first, sets permissions, atomically replaces the target files, then runs the reload command.

## Dashboard

The first screen is the working dashboard:

- acme.sh version
- acme.sh home
- account status
- CA
- automatic renewal status
- certificate cards grouped by main domain
- ECC and RSA badges
- expiration progress
- deploy health
- recent tasks
- update check

Each certificate detail page has:

- overview
- issue configuration
- DNS and alias
- deploy and reload
- native variables
- logs

Failure display must include:

- failed stage
- last error
- full log link
- suggested cause when known
- retry button

## Milestones

1. Read-only dashboard.
2. Task system and renew skeleton.
3. DNS provider signing wizard.
4. Local install-cert.
5. Remote SSH deploy hook.
6. acme.sh upgrade workflow.
7. UI polish and additional providers.

The first implementation slice should be milestone 1 plus enough of milestone 2 to prove task logging.
