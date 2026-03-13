# Security And Auth Guide

This guide applies to `kubernetes/apps/security/`.

## What Is Special Here

This subtree is the cluster authentication layer. Changes here affect multiple applications, so treat it as platform work, not isolated app work.

Current live stack:

- Pocket ID is the OIDC identity provider
- TinyAuth is the forward-auth layer for apps without native OIDC

## Core Conventions

- public auth endpoints are exposed through `envoy-external`
- auth-related secrets come from External Secrets and 1Password
- auth services still follow the repo's hardening defaults unless the live image forces exceptions
- persistent auth state uses PVC-backed storage and is covered by VolSync

## Pocket ID Rules

Pocket ID is the source of truth for OIDC in the cluster.

Observed live behavior:

- SQLite backend
- app URL served from `id.${PUBLIC_DOMAIN}`
- secret material assembled through `template.data` in the ExternalSecret
- persistent data at `/app/data`

When editing Pocket ID:

- verify Secret key names match the app's expected env vars
- verify route hostname and `APP_URL` stay aligned
- treat data persistence and backup settings as part of the deployment, not optional extras

## TinyAuth Rules

TinyAuth is the fallback auth layer for apps without native OIDC.

Observed live behavior:

- public route served from `auth.${PUBLIC_DOMAIN}`
- provider settings point to Pocket ID endpoints
- persistent data is stored on a PVC

When editing TinyAuth:

- keep Pocket ID endpoint references synchronized with the live Pocket ID route
- verify scopes and provider env vars match the current Pocket ID OIDC surface
- if using TinyAuth as a pattern for another app, still verify whether native OIDC would be preferable first

## Cross-App Auth Guidance

Before wiring auth into a user-facing application:

1. check whether the target app already supports native OIDC well
2. prefer native OIDC with Pocket ID when the app supports it cleanly
3. use TinyAuth only when native OIDC is weak, missing, or operationally worse
4. inspect sibling apps for secret naming, route patterns, and public hostname style

## Validation

For security subtree changes, verify:

1. hostname, route, and app URL values still align
2. ExternalSecret target names still match mounted Secret refs
3. Pocket ID and TinyAuth endpoint relationships remain consistent
4. PVC-backed state and VolSync assumptions are still intact
