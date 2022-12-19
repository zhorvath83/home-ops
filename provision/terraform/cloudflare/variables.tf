# https://developer.hashicorp.com/terraform/language/values/variables
# https://dev.to/pwd9000/terraform-complex-variable-types-173e
# https://github.com/robbyoconnor/terraform-cloudflare-fastmail-mx/blob/main/main.tf
# https://blog.wimwauters.com/devops/2022-03-01_terraformusecases/

variable "dns_mx_records" {
  type = map(object({
    server = string
    priority = number
  }))

  description = "List of permitted MX hosts"
}
