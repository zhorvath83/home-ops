output "client_secrets" {
  description = "Per-client secrets of confidential clients. The API returns these on creation only, so state is the sole copy besides 1Password."
  value       = { for k, c in pocketid_client.this : k => c.client_secret if !local.clients[k].is_public }
  sensitive   = true
}
