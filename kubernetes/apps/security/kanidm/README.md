# Kanidm

> `${PUBLIC_DOMAIN}` below is the cluster domain from
> `kubernetes/components/common/vars/cluster-settings.yaml`. Substitute it
> when running the commands.

## Administration via Just

The `kanidm/server` image ships only the `kanidmd` **server** binary, and the
`kanidm` **client** CLI has no macOS package — so all administration runs
through the `just kanidm` module (`kubernetes/apps/security/kanidm/mod.just`).
Client commands execute in an ad-hoc `kanidm/tools` pod in the `security`
namespace; nothing is installed locally.

- `just kanidm` — list all recipes
- `just kanidm login` — authenticate as `idm_admin`; the session lives in the
  client pod until `just kanidm client-down`
- `just kanidm run <args>` — escape hatch for anything not covered by a
  recipe (append `-D idm_admin`)

## Initial setup

### 1. Recover the admin accounts

After the first deploy, recover both built-in accounts:

```bash
just kanidm recover-account admin
just kanidm recover-account idm_admin
```

Log in with each recovery token and set a real password via the web UI at
`https://idm.${PUBLIC_DOMAIN}/ui/reset`.

### 2. Create the provision service account

```bash
just kanidm login
just kanidm run service-account create kanidm-provision "Kanidm Provision" idm_admins -D idm_admin
just kanidm group-add-members idm_admins kanidm-provision
just kanidm run service-account api-token generate --readwrite kanidm-provision provision-token -D idm_admin
```

Store the token in 1Password as item `kanidm-provision` → field `token`.

### 3. Create groups

```bash
just kanidm group-create users
just kanidm group-create admins
```

### 4. Create your personal account

```bash
just kanidm person-create <username> "<Display Name>"
just kanidm run person update <username> --mail "<email>" -D idm_admin
just kanidm group-add-members users <username>
just kanidm group-add-members admins <username>
just kanidm group-add-members idm_admins <username>
just kanidm person-reset-token <username>
```

Use the reset token to set a password or enroll a passkey at
`https://idm.${PUBLIC_DOMAIN}`.
