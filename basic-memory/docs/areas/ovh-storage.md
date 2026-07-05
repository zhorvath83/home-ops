---
title: ovh-storage
type: area_reference
permalink: home-ops/docs/areas/ovh-storage
area: ovh-storage
status: current
confidence: high
verified_at: '2026-06-20'
summary: Terraform in `provision/ovh/` provisions a set of OVH Cloud Project Object
  Storage buckets and one dedicated cloud-project user (`objectstore_operator` role)
  with an S3 credential and an inline bucket-scoped S3 policy. Buckets live in region
  `DE` and share the endpoint `s3.de.io.cloud.ovh.net`. State is in Terraform Cloud
  workspace `ovh`. The `just ovh apply` recipe also pushes freshly issued S3 credentials
  and metadata back into the `HomeOps/ovh` 1Password item via `op item edit` — that
  item is the single source from which the in-cluster VolSync/Kopia and resticprofile
  consumers read.
verified_against:
- provision/ovh/main.tf
- provision/ovh/variables.tf
- provision/ovh/terraform.tfvars
- provision/ovh/buckets.tf
- provision/ovh/user.tf
- provision/ovh/mod.just
- provision/ovh/CLAUDE.md
- provision/CLAUDE.md
drift_risk: The Terraform-managed bucket name list (`S3_BUCKET_NAMES`) and the inline
  S3 policy ARNs are the cluster backup contract — renaming or removing a bucket silently
  breaks live VolSync/Kopia and resticprofile consumers whose ExternalSecret + repository
  URLs reference those names. Credentials are issued at apply time and only persist
  in 1Password via the `just ovh apply` post-step; running `terraform apply` outside
  the just recipe skips that sync. The OVH provider uses long-lived application/consumer
  keys, not a token — rotation has wide blast radius. The S3 policy is intentionally
  full-access (`s3:*`) on each bucket, with separation only at the bucket boundary.
tags:
- area-reference
- ovh-storage
- provision
- terraform
- backup
---

# ovh-storage — current state

## Metadata (observation-form, schema validation)

- [area] ovh-storage
- [status] current
- [confidence] high
- [verified_at] 2026-06-20

## Summary

`provision/ovh/` is the Terraform source of truth for the OVH Cloud Project Object Storage assets that back the cluster's two backup planes. It declares:

- a set of buckets generated from the `S3_BUCKET_NAMES` variable (comma-and-space-separated list), all in OVH region `DE`, exposed via the endpoint `s3.de.io.cloud.ovh.net`
- one dedicated OVH Cloud Project user (`objectstore_operator` role, description from `OVH_S3_USER`)
- an S3 credential bound to that user
- an inline S3 policy granting `s3:*` on each bucket (and its objects), scoping the credential to exactly the bucket set

Terraform state lives in Terraform Cloud (org `zhorvath83`, workspace `ovh`). All OVH credentials and the bucket list come in as `TF_VAR_*` env vars rendered from 1Password through `op run --no-masking --env-file=./.env -- terraform ...`.

The `just ovh apply` recipe is the single supported apply path: after `terraform apply` it reads six outputs (`s3_user_id`, `s3_username`, `s3_user_description`, `s3_access_key`, `s3_secret_key`, `s3_endpoint`) as JSON and pushes them back into the 1Password item `HomeOps/ovh` via `op item edit`. That item is the contract surface for the in-cluster consumers — VolSync/Kopia (`kubernetes/components/volsync/` + `kubernetes/apps/volsync-system/`) and the file-level resticprofile workload (`kubernetes/apps/selfhosted/resticprofile/`) — which fetch the values via External Secrets.

## Components

- [component] Terraform Cloud workspace — org `zhorvath83`, workspace `ovh`, `required_version = "~> 1.0"` (provision/ovh/main.tf:1-23)
- [component] OVH provider — `ovh/ovh` pinned (provision/ovh/main.tf:12-16)
- [component] null provider — `hashicorp/null` (provision/ovh/main.tf:18-21)
- [component] OVH provider auth — `endpoint` from `OVH_ENDPOINT` (default `ovh-eu` per terraform.tfvars), plus the long-lived `application_key` / `application_secret` / `consumer_key` triple (provision/ovh/main.tf:25-30 + terraform.tfvars:1)
- [component] Buckets — `ovh_cloud_project_storage.backup` `for_each` over `local.bucket_names` (parsed from comma-and-space-separated `S3_BUCKET_NAMES`), region pinned to `DE` (provision/ovh/buckets.tf:1-11)
- [component] Endpoint output — `s3_endpoint` = `s3.de.io.cloud.ovh.net` (derived from `local.region`) (provision/ovh/buckets.tf:13-15)
- [component] Object-store user — `ovh_cloud_project_user.object_store_user` with role `objectstore_operator` and `description` from `OVH_S3_USER` (provision/ovh/user.tf:1-5)
- [component] S3 credential — `ovh_cloud_project_user_s3_credential.object_store_user` issued for the user (provision/ovh/user.tf:7-10)
- [component] S3 policy — `ovh_cloud_project_user_s3_policy.object_store_user`, single statement `FullAccess`, `Effect=Allow`, `Action=["s3:*"]`, `Resource=[arn:aws:s3:::<bucket>, arn:aws:s3:::<bucket>/*]` for each bucket in `local.bucket_names` (provision/ovh/user.tf:12-29)
- [component] Outputs — `s3_user_id`, `s3_username` (sensitive), `s3_user_description`, `s3_access_key` (sensitive), `s3_secret_key` (sensitive), `s3_endpoint` (provision/ovh/buckets.tf:13-15 + user.tf:31-54)
- [component] Just recipes — `init`, `plan`, `apply` (with 1P sync), `unlock` — all wrap `op run --no-masking --env-file=./.env -- terraform ...` (provision/ovh/mod.just)
- [component] Post-apply 1Password sync — `just ovh apply` reads `terraform output -json` and runs a single `op item edit ovh --vault HomeOps` updating six fields (`ovh_s3_user_id`, `ovh_s3_username`, `ovh_s3_user_description`, `ovh_s3_access_key`, `ovh_s3_secret_key`, `ovh_s3_endpoint`) (provision/ovh/mod.just:26-50)

## Claims (verified against repo)

- [claim] "Terraform state lives in Terraform Cloud, org `zhorvath83`, workspace `ovh`" (evidence: repo, ref: provision/ovh/main.tf:5-10, verified: 2026-06-20)
- [claim] "OVH provider `ovh/ovh` is pinned (no Renovate disable annotation observed)" (evidence: repo, ref: provision/ovh/main.tf:12-16, verified: 2026-06-20)
- [claim] "OVH provider authenticates with the long-lived application_key + application_secret + consumer_key triple plus an endpoint (`ovh-eu` per the in-repo tfvars) — no API token model" (evidence: repo, ref: provision/ovh/main.tf:25-30 + terraform.tfvars:1, verified: 2026-06-20)
- [claim] "All buckets are created in region `DE` and the derived public endpoint is `s3.de.io.cloud.ovh.net`" (evidence: repo, ref: provision/ovh/buckets.tf:1-15, verified: 2026-06-20)
- [claim] "Bucket set is driven by `var.S3_BUCKET_NAMES` — a comma-and-space-separated string parsed into a set; adding or removing a bucket requires editing that var and re-applying, not editing buckets.tf" (evidence: repo, ref: provision/ovh/variables.tf:29-32 + buckets.tf:1-11, verified: 2026-06-20)
- [claim] "Exactly one OVH Cloud Project user is created (`role_names = ["objectstore_operator"]`), with a single S3 credential and a single S3 policy attached" (evidence: repo, ref: provision/ovh/user.tf:1-29, verified: 2026-06-20)
- [claim] "The S3 policy is a single Allow statement `s3:*` scoped to the same bucket set as `local.bucket_names` — both the bucket ARN and the object ARN are granted" (evidence: repo, ref: provision/ovh/user.tf:12-29, verified: 2026-06-20)
- [claim] "`just ovh apply` does two things in sequence: (1) `terraform apply` via `op run`, (2) a single `op item edit ovh --vault HomeOps` that writes six fields (`ovh_s3_user_id`, `ovh_s3_username`, `ovh_s3_user_description`, `ovh_s3_access_key`, `ovh_s3_secret_key`, `ovh_s3_endpoint`) using outputs parsed from a single `terraform output -json` call" (evidence: repo, ref: provision/ovh/mod.just:26-50, verified: 2026-06-20)
- [claim] "The post-apply 1Password sync uses `jq -er` so a missing or null output aborts the recipe rather than silently writing empty fields" (evidence: repo, ref: provision/ovh/mod.just:33-43, verified: 2026-06-20)
- [claim] "The 1Password `HomeOps/ovh` item is the contract surface for the in-cluster consumers — VolSync/Kopia and resticprofile both read `ovh_s3_*` from this item via External Secrets; Terraform itself never reaches the cluster" (evidence: repo, ref: provision/ovh/CLAUDE.md:7-10,15-15, verified: 2026-06-20)
- [claim] "Four operational entry points exist: `just ovh init|plan|apply|unlock`; `unlock` wraps `terraform force-unlock` for state recovery" (evidence: repo, ref: provision/ovh/mod.just:16-55, verified: 2026-06-20)

## Drift Risk

- [drift] The bucket name set (`S3_BUCKET_NAMES`) and the policy ARNs are the cluster backup contract. Renaming or removing a bucket silently breaks live VolSync/Kopia ReplicationSources and the resticprofile repo whose URLs and ExternalSecret keys reference those names. There is no automated rename or migration helper.
- [drift] The post-apply 1Password sync is a Just-recipe-side concern, not a Terraform output sink — running `terraform apply` outside `just ovh apply` skips the sync and leaves the in-cluster consumers stale with the old credentials. Worse, on credential rotation the old credential is revoked at OVH side, so the cluster breaks until 1Password is re-synced. The recipe-only contract is documented in `provision/ovh/CLAUDE.md` but not enforced.
- [drift] The OVH provider uses long-lived `application_key` / `application_secret` / `consumer_key` credentials. There is no equivalent of the Cloudflare API Token model — rotation has wide blast radius.
- [drift] The S3 policy grants full S3 access (`s3:*`) on each bucket. Separation between backup planes (VolSync/Kopia vs resticprofile) relies on bucket boundaries only — a compromised credential can read or destroy snapshots in any bucket in the set, including its own.
- [drift] No bucket-level versioning, object-lock, or lifecycle rules are declared in Terraform; if any are set on the OVH side via Console or CLI they will not be tracked here. Renovate or upstream provider bumps that add new fields could silently propose drift.

## Open Questions / Gaps

- [gap] No verification was run against the live OVH API or Terraform Cloud workspace in this pass — claims are repo-evidence only. `just ovh plan` from a credentialed shell is the live-state validation path.
- [gap] The actual bucket name list is supplied through `TF_VAR_S3_BUCKET_NAMES` (1Password-backed `.env`) and is not visible in the repo. Cross-checking that the in-cluster ReplicationSources, repository templates, and resticprofile config all reference exactly the same bucket names is left to a downstream contract review under volsync-backup and resticprofile-backup.
- [gap] No formal disaster-recovery procedure is captured for the case where Terraform Cloud state is lost. Re-importing the buckets and user would require manual coordination with the live OVH account.
- [gap] No backup of the 1Password `HomeOps/ovh` item itself is captured here — if that item is lost, the only way to restore the in-cluster credentials is to re-run `just ovh apply` (which rotates the S3 credential) and re-sync.

## Relations

- relates_to [[volsync-backup]]
- relates_to [[resticprofile-backup]]
- relates_to [[external-secrets]]
- part_of [[home-ops-platform]]
