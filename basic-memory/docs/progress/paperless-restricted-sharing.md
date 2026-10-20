---
title: paperless-restricted-sharing
type: progress
permalink: home-ops/docs/progress/paperless-restricted-sharing
tags:
- paperless
- iam
- permissions
- pocket-id
- workflows
---

# Progress — paperless-restricted-sharing (view-only sharing of a reviewed document slice)

Give one external account view-only access to a reviewed subset of the paperless archive — the
documents carrying any of a small set of "person" tags — and nothing else. Implemented 2026-10-20/21
on paperless-ngx 3.3.3; repo change pushed to main as commit f359f1a14, everything else is app
state. The detailed plan (with personal data) is deliberately kept out of this repo.

## Metadata (observation-form)

- [status] done — live-verified with the restricted account's own API token (45/45 checks)
- [priority] high
- [area] iam / k8s-workloads
- [created] 2026-10-07
- [completed] 2026-10-21
- [branch] main
- [privacy] account, person-tag names, document ids and titles intentionally omitted (public repo)

## Why

- [observation] Every document was unowned; paperless treats an unowned object as visible to every account that holds the global view permission. The external account therefore saw the whole archive.
- [observation] paperless-ngx has no deny permission. Exclusion can only be modeled by ownership: give every object an owner and grant view per object.

## Verified behaviour (paperless-ngx v3.3.3 source)

- [fact] Global view_<model> is the AREA gate (list/detail endpoints are DjangoObjectPermissions → 403 without it); object visibility = owned OR unowned OR explicit user/group grant. Global perms never reveal owned objects. So the restricted group KEEPS global view_document.
- [fact] Notes and custom-field values are serialized inline in the document payload regardless of view_note; view_note only gates the /notes/ endpoint. A note on a shared document is shared content.
- [fact] OIDC group sync (PAPERLESS_SOCIAL_ACCOUNT_SYNC_GROUPS) replaces the Django groups on every SSO login (groups.set(clear=True)), drops unknown claim names, and is skipped for inactive users. Token (mobile-app) access never triggers it — set Django membership directly.
- [fact] Workflows run synchronously; Document Added runs inside the consumer transaction before indexing (no visible unowned window). Document Updated fires on PATCH/PUT and on every bulk_edit (bulk_update_documents).
- [fact] Single-document saves index BEFORE the Document Updated workflows run, so a workflow grant/revoke reaches the search index only on the next reindex; bulk edits reindex after the workflows. Search results are intersected with the DB permission filter (no result leak); autocomplete is index-only.
- [fact] The Scheduled trigger is date-offset based, not a sweep; PAPERLESS_WORKFLOW_SCHEDULED_TASK_CRON is disabled here anyway.
- [fact] Unowned consume-folder tasks are visible to any holder of view_paperlesstask (original filenames + results).
- [fact] The per-user UI "Default View Groups" setting pre-fills the create dialog for tags/correspondents/types; it had granted the old user group view on the whole taxonomy. API-created objects get the requesting user as owner.

## What was implemented

- [observation] Pocket ID: group `paperless_coparents` added to `provision/pocket-id/clients.yaml` and to the paperless client's allowed groups (commit f359f1a14; `just pocket-id audit`: all 25 clients group-restricted). Membership set in the Pocket ID admin UI.
- [observation] Django group `paperless_coparents`, global perms ONLY: view_document, view_tag, view_documenttype, view/add/change/delete savedview + uisettings, view_applicationconfiguration. Explicitly NOT: view_correspondent, view_note, view_customfield, view_sharelink, view_logentry, view_paperlesstask, any change/add/delete on documents, user/group/statistics/mail/workflow perms.
- [observation] Workflow 0 "Close model": Document Added → Assignment owner = the archive owner. Security control — never disable.
- [observation] Workflow 1 "Coparent: grant view": Document Added + Document Updated, Any Tags = person tags, No Tags = Inbox → Assignment view group paperless_coparents (merge).
- [observation] Workflow 2 "Coparent: revoke view": Document Updated with No Tags = person tags, OR Document Updated with Any Tags = Inbox → Removal view group paperless_coparents.
- [observation] Retroactive migration: bulk set_permissions (owner, empty permission map, merge=false) on all 1881 documents — the bulk path fired the Document Updated workflows, which granted the slice (575 documents); 74 unowned correspondents given the owner (no grants); view grants for the group on the 16 tags and 12 document types that occur in the shared slice.
- [observation] Owner's UI Default View Groups cleared.

## Decisions

- [decision] Review gate: the grant fires only once Inbox is removed. The person tags are assigned by paperless-gpt; the owner's existing Inbox review becomes the share approval, so an LLM mis-tag is caught before it shares.
- [decision] No correspondent visibility at all (no global view_correspondent): zero upkeep, no name leak; titles carry the context.
- [decision] No exclusion tag: a document that must not be shared does not carry a person tag.
- [decision] View-only: no add_document (no uploads).
- [decision] Share state is a pure function of the tags: shared iff a person tag AND no Inbox (grant and revoke conditions are mutually exclusive).

## Verification (live, the restricted account's token, 2026-10-21)

- [observation] Document list == expected set (575/575, no missing, no extra); a non-shared document returns 404 on detail and 403 on download/preview/thumb/metadata/notes/history; shared download 200.
- [observation] Full-text search and autocomplete return nothing for terms that only occur outside the slice; a shared document is found (index carries the group grant).
- [observation] Tags/document types list only the granted objects; correspondents, tasks, users, groups, share links, workflows, custom fields, storage paths, mail, logs → 403; no saved views; statistics count == 575; cannot add notes or edit.
- [observation] Global search returns only shared documents and only granted tags.
- [observation] Round trip on one shared document: removing the person tags or adding Inbox hides it; restoring shows it again.
- [observation] Pre-change state backed up by a manual paperless-backup job run (Complete).

## Gotchas

- [gotcha] `echo yes | just pocket-id apply` breaks the follow-up `sync-secrets`: `op item edit` reads the piped stdin as an item JSON template ("invalid JSON provided"). Re-run `just pocket-id sync-secrets < /dev/null`.
- [gotcha] The Pocket ID provisioning API key had expired (HTTP 401 "You are not signed in" on every group read); the replacement key has a 1-day lifetime — the next Terraform run needs a new key.
- [gotcha] pre-commit inside the Bash sandbox cannot write ~/.cache/pre-commit (PermissionError on .lock) — commit outside the sandbox.

## Follow-ups

- [ ] The old `paperless_users` group is empty and still holds broad tag/type grants — delete it (Pocket ID + client list + Django) or keep it empty.
- [ ] After the account's first SSO login, re-check its Django groups == [paperless_coparents].
- [ ] A new tag or document type used on shared documents needs a manual view grant for the group to render for the account.
- [ ] Deleting a person-tag object fires no document save, so no automatic revoke — revoke by hand.
- [ ] Purpose of the inert `consumer` user (no groups, perms or token).

## Relations

- relates_to [[iam]]
- relates_to [[k8s-workloads]]
- relates_to [[app-auth-coverage]]
- relates_to [[paperless-ngx-v3-migration]]
