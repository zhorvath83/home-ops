# https://developer.hashicorp.com/terraform/language/values/variables
# https://dev.to/pwd9000/terraform-complex-variable-types-173e
# https://github.com/robbyoconnor/terraform-cloudflare-fastmail-mx/blob/main/main.tf
# https://blog.wimwauters.com/devops/2022-03-01_terraformusecases/

# https://github.com/jpawlowski/mta-sts.template

variable "dns_mx_records" {
  type = map(object({
    host = string
    priority = number
  }))
  description = "Permitted MX hosts"
}

variable "dns_spf_record_value" {
  description = "Value of SPF DNS record."
  type        = string
}


variable "dns_dkim_records" {
  type = map(object({
    name  = string
    value = string
    type  = string
  }))
  description = "Params of DKIM DNS record."
}


variable "mail_dmarc_rua_dest" {
  type        = list(string)
  description = "Locations to which aggregate reports about policy violations should be sent, either `mailto:` or `https:` schema."

  validation {
    condition     = length(var.mail_dmarc_rua_dest) != 0
    error_message = "At least one `mailto:` or `https:` endpoint provided."
  }

  validation {
    condition     = can([for loc in var.mail_dmarc_rua_dest : regex("^(mailto|https):", loc)])
    error_message = "Locations must start with either the `mailto: or `https` schema."
  }
}

variable "mail_dmarc_ruf_dest" {
  type        = list(string)
  description = "Locations to which aggregate reports about policy violations should be sent, either `mailto:` or `https:` schema."

  validation {
    condition     = length(var.mail_dmarc_ruf_dest) != 0
    error_message = "At least one `mailto:` or `https:` endpoint provided."
  }

  validation {
    condition     = can([for loc in var.mail_dmarc_ruf_dest : regex("^(mailto|https):", loc)])
    error_message = "Locations must start with either the `mailto: or `https` schema."
  }
}

variable "mail_tls_rua_dest" {
  type        = list(string)
  description = "Locations to which aggregate reports about policy violations should be sent, either `mailto:` or `https:` schema."

  validation {
    condition     = length(var.mail_tls_rua_dest) != 0
    error_message = "At least one `mailto:` or `https:` endpoint provided."
  }

  validation {
    condition     = can([for loc in var.mail_tls_rua_dest : regex("^(mailto|https):", loc)])
    error_message = "Locations must start with either the `mailto: or `https` schema."
  }
}

variable "mail_mta_sts_params" {
  type = object({
    mode = string
    max_age = number
  })

  description = <<EOT
    mail_mta_sts_params = {
      mode : "Sending MTA policy application, https://tools.ietf.org/html/rfc8461#section-5"
      max_age : "Maximum lifetime of the policy in seconds, up to 31557600, defaults to 604800 (1 week)"
    }
  EOT

  validation {
    condition     = contains(["enforce", "testing", "none"], var.mail_mta_sts_params.mode)
    error_message = "Only `enforce` `testing` or `none` is valid."
  }

  validation {
    condition     = var.mail_mta_sts_params.max_age >= 0
    error_message = "Policy validity time must be positive."
  }
}

variable "CF_ACCOUNT_ID" {
  description = "Cloudflare account ID."
  type        = string
}

variable "CF_ACCESS_UNRESTRICTED_USERS" {
  description = "List of unrestricted user's email addresses at Cloudflare Access."
  type        = string
}

variable "CF_ACCESS_RESTRICTED_USERS" {
  description = "List of restricted user's email addresses at Cloudflare Access."
  type        = string
}

variable "CF_ACCESS_GOOGLE_CL_ID" {
  description = "Google CL ID for Cloudflare Access."
  type        = string
}

variable "CF_ACCESS_GOOGLE_CL_SECRET" {
  description = "Google CL secret for Cloudflare Access."
  type        = string
}

variable "CF_DOMAIN_NAME" {
  description = "Domain name @ Cloudflare."
  type        = string
}

variable "CF_USERNAME" {
  description = "Username (mail) @ Cloudflare."
  type        = string
}

variable "CF_GLOBAL_APIKEY" {
  description = "Cloudflare API key."
  type        = string
}

# variable "CF_API_TOKEN" {
#   description = "Cloudflare API Token for tunnel management"
#   type        = string
# }

variable "CF_TUNNEL_SECRET" {
  description = "Cloudflare Tunnel Secret"
  type        = string
}

variable "CF_TUNNEL_NAME" {
  description = "Cloudflare Tunnel Name"
  type        = string
}

# variable "CUSTOM_DOMAIN_EMAIL" {
#   description = "Private custom domain email address."
#   type        = string
# }

variable "GITHUB_USER_FOR_PAGES" {
  description = "Github user name for CF Pages deploy."
  type        = string
}
