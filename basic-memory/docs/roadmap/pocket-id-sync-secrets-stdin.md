---
title: pocket-id-sync-secrets-stdin
type: roadmap
permalink: home-ops/docs/roadmap/pocket-id-sync-secrets-stdin
topic: just pocket-id apply/rotate can leave 1Password stale — op item edit reads
  a piped stdin as an item template
status: done
priority: medium
scope: Make the sync-secrets step of provision/pocket-id/mod.just immune to a non-TTY
  stdin, make the failure impossible to miss, and add a post-condition that every
  client in Terraform state has its field in 1Password. Covers apply, rotate and sync-secrets.
rationale: 'Reproduced 2026-11-16: with a piped stdin, sync-secrets fails with "unable
  to process line 1: invalid JSON provided" after Terraform has already applied. The
  IdP then holds a client secret that 1Password and the ExternalSecrets do not have,
  which breaks the affected app''s login (a new gateway-oidc client cannot get its
  secret; a rotated client keeps the old one).'
options:
- Redirect op item stdin from /dev/null + post-condition check — RECOMMENDED
- Pass secrets via a JSON template file instead of field assignments
related_areas:
- iam
---

# Pocket ID sync-secrets fails on a piped stdin

## Metadata (observation-form, schema validation)

- [topic] `just pocket-id apply/rotate` can leave 1Password stale — `op item edit` reads a piped stdin as an item template
- [status] done
- [priority] medium
- [researched_at] 2026-11-16
- [effort] S

## What is wrong

`just pocket-id apply` runs two steps: `terraform apply`, then `just pocket-id sync-secrets`. The second step copies every client secret from Terraform state into the 1Password item `HomeOps/pocket-id-clients`. Every consuming ExternalSecret reads its client secret from there. `rotate` runs the same sync.

When the recipe's stdin is not a terminal but a pipe, the sync fails *after* Terraform has already changed the IdP:

```
[ERROR] … unable to process line 1: invalid JSON provided
error: recipe `sync-secrets` failed with exit code 1
```

- [verified] Reproduced 2026-11-16: `echo yes | just pocket-id sync-secrets` → exit 1 with the error above. `just pocket-id sync-secrets < /dev/null` → exit 0, "Synced 26 client secrets". A terminal stdin (a human typing `yes`) also works, which is why the bug went unnoticed.
- [verified] `op item get` with the same piped stdin succeeds. The reader is `op item edit`: when stdin is not a TTY it takes stdin as a JSON item template (its `--help` documents template input), and `yes` or an empty pipe is not valid JSON. `op item create` (first run only) has the same template input.
- [observed] It happened on both applies of 2026-11-16 (home-gallery client, paperless public-client change). The first time the error line was missed because the recipe output scrolls past it and `Apply complete!` looks like success.

## Why it matters

- **New gateway-oidc client** (e.g. home-gallery): the IdP has the client, 1Password does not have `<app>_client_secret`, so the ExternalSecret cannot resolve its property, no Secret is created, and the SecurityPolicy stays invalid. The app is unreachable (fails closed) until someone notices.
- **Rotation**: the IdP has the new secret, 1Password and the app keep the old one, and every login fails with `invalid_client`.
- **Who triggers it**: anything that runs the recipe without a terminal: an agent session (as on 2026-11-16), a script, or a future CI/automation path. `terraform apply` needs `yes` on stdin there, which is exactly the pipe that breaks the sync.

## What to do

1. In `sync-secrets`, give every `op item …` call a closed stdin (`< /dev/null`), so `op` can never mistake the caller's stdin for a template. Same for `op item create`.
2. Add a post-condition at the end of `sync-secrets`: list the field labels of `HomeOps/pocket-id-clients` (`op item get … --format json | jq '.fields[].label'`) and fail unless every key of `terraform output client_secrets` has its `<key>_client_secret` label. Print only labels, never values.
3. Make the failure loud in `apply` and `rotate`: if the sync fails, log an explicit error saying "IdP changed but 1Password is stale — run `just pocket-id sync-secrets` now" and exit non-zero (today it exits non-zero, but with no hint).
4. Optional: an `apply-auto` variant (`terraform apply -auto-approve` after a fresh `plan` review) so non-interactive callers do not pipe `yes` at all.

## Verification

- `echo yes | just pocket-id sync-secrets` → exit 0 and the "Synced N" line.
- `echo yes | just pocket-id apply` with no pending change → apply no-op, sync exit 0.
- Delete one field in a scratch copy, or point the post-condition at a fixture item → the post-condition fails and names the missing client.
- shellcheck and just-fmt pass (pre-commit).

## Acceptance criteria

1. The piped-stdin reproduction passes.
2. The post-condition catches a missing field and names it, without printing any secret.
3. A failed sync after a successful apply prints the recovery command.

## Implementation (2026-11-16, commit 216f33be2 on main)

- [implemented] Every `op item` call in `sync-secrets` has `</dev/null` stdin.
- [implemented] Post-condition after the edit: every key of `terraform output client_secrets` must have its `<key>_client_secret` label in the item; on a miss it logs `missing=<keys>` (labels only) and exits 1.
- [implemented] `apply` and `rotate` log "IdP changed but 1Password is stale - run 'just pocket-id sync-secrets' now" and exit 1 when the sync fails.
- [implemented] Found during verification: `op item get … || op item create` minted a duplicate `pocket-id-clients` item on a transient `op` error (desktop-app authorization), after which every by-name call failed with "More than one item matches". The item is now created only when `op item list` confirms it is absent; a failing list aborts. The duplicate (empty) was deleted by hand.
- [not_done] Option 4 (`apply-auto`) was skipped as not needed.
- [verified] AC1: `echo yes | just pocket-id sync-secrets` → exit 0, "Synced 25 client secrets".
- [verified] AC2: post-condition with an injected fake client → exit 1, `missing=no-such-app`, no values printed.
- [open] AC3 / no-op `echo yes | just pocket-id apply` was not run by the agent (blocked by its permission classifier); `just pocket-id plan` showed no changes. Verified by inspection only.
- [follow_up] The `paperless_client_secret` field is now orphaned in the item (paperless became a public client); `sync-secrets` only adds or updates fields, it never prunes.

## Related

- relates_to [[iam]]
- relates_to [[route-auth-coverage-guard]]
