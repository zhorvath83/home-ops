# Checklists

Use only the sections relevant to the current task.

## Workload Hardening

- does the workload run as non-root unless there is a documented exception
- is `allowPrivilegeEscalation: false` set where supported
- is `readOnlyRootFilesystem: true` preserved where practical
- are capabilities dropped except for explicitly justified cases
- are privileged, hostNetwork, hostPID, or similar exceptions narrowly scoped and explained
- do mounted config or secret changes trigger restarts when expected

## Secret Handling

- does the secret belong in SOPS or External Secrets under the current repo model
- do generated Secret names match every consuming ref
- are shared store names and bootstrap secret names kept stable
- does the change accidentally widen secret distribution or duplicate sensitive data
- if a token or webhook secret is internet-adjacent, is the surrounding exposure chain also reviewed

## Flux And Webhooks

- does the change widen who can trigger reconciliation or notifications
- do receiver, provider, and route resources still point at the intended secret names and namespaces
- if a webhook is public, are the compensating controls still present
- does the change increase cluster-wide blast radius beyond the stated purpose

## Networking And Exposure

- is the service internal-only, externally exposed, or both, and is that intentional
- if external, does the full chain still make sense: route, gateway, tunnel, DNS, and any Cloudflare policy
- do network policies still enforce the intended trust boundaries
- does the change create a broader hostname, listener, or wildcard surface than needed

## Cloudflare And Edge

- does the Terraform change alter public reachability, Access policy, or tunnel trust unexpectedly
- are provider auth and credential flows unchanged unless explicitly intended
- do firewall and access resources still match the intended webhook or public endpoints

## Detection Gap

- if this path were abused, would the repo's current logs, metrics, alerts, or audit surfaces make it visible
- if not, call out the gap explicitly instead of only naming the underlying risk
