output "client_secrets" {
  description = "Per-client secrets. The API returns these on creation only, so state is the sole copy besides 1Password."
  value       = { for k, c in pocketid_client.this : k => c.client_secret }
  sensitive   = true
}
