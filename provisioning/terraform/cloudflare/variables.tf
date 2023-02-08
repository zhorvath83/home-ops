# https://developer.hashicorp.com/terraform/language/values/variables
# https://dev.to/pwd9000/terraform-complex-variable-types-173e
# https://github.com/robbyoconnor/terraform-cloudflare-fastmail-mx/blob/main/main.tf
# https://blog.wimwauters.com/devops/2022-03-01_terraformusecases/

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
    name = string
    value_prefix = string
    value_suffix = string
    type = string
  }))
  description = "Params of DKIM DNS record."
}

variable "dns_srv_records" {
  type = map(object({
    service   = string
    proto     = string
    priority  = number
    weight    = number
    port      = number
    target    = string
  }))
  description = "Params of SRV DNS record."
}

variable "dns_dmarc_record_value" {
  description = "Value of DMARC DNS record."
  type        = string
}

variable "mail_mta_sts_params" {
  type = object({
    mode = string
    max_age = number
    rua_mail = string
  })

  description = "MTA-STS mail params"
}

variable "private_website_target_url" {
  description = "CNAME target URL of my private website."
  type        = string
}
