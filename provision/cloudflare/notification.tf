###########################################################################
# Cloudflare Notification Policies
# Notifications are sent to Pushover via email gateway

# Tunnel Health Event - alerts when tunnel status changes (includes future tunnels)
resource "cloudflare_notification_policy" "tunnel_health" {
  account_id  = var.CF_ACCOUNT_ID
  name        = "Tunnel Health Alert"
  description = "Alert when tunnel health status changes"
  enabled     = true
  alert_type  = "tunnel_health_event"

  mechanisms = {
    email = [{
      id = var.PUSHOVER_CLOUDFLARE_EMAIL
    }]
  }
}

# Tunnel Creation or Deletion Event
resource "cloudflare_notification_policy" "tunnel_creation_deletion" {
  account_id  = var.CF_ACCOUNT_ID
  name        = "Tunnel Creation or Deletion Alert"
  description = "Alert when a tunnel is created or deleted"
  enabled     = true
  alert_type  = "tunnel_update_event"

  mechanisms = {
    email = [{
      id = var.PUSHOVER_CLOUDFLARE_EMAIL
    }]
  }
}

# Incident Alert - Cloudflare platform incidents (critical only)
resource "cloudflare_notification_policy" "incident_alert" {
  account_id  = var.CF_ACCOUNT_ID
  name        = "Cloudflare Incident Alert"
  description = "Alert for Cloudflare platform incidents"
  enabled     = true
  alert_type  = "incident_alert"

  mechanisms = {
    email = [{
      id = var.PUSHOVER_CLOUDFLARE_EMAIL
    }]
  }

  filters = {
    incident_impact = ["INCIDENT_IMPACT_CRITICAL"]
  }
}

# HTTP DDoS Attack Alert
resource "cloudflare_notification_policy" "http_ddos_attack" {
  account_id  = var.CF_ACCOUNT_ID
  name        = "HTTP DDoS Attack Alert"
  description = "Alert when HTTP DDoS attack is detected"
  enabled     = true
  alert_type  = "dos_attack_l7"

  mechanisms = {
    email = [{
      id = var.PUSHOVER_CLOUDFLARE_EMAIL
    }]
  }
}

# Trust and Safety - Abuse Report Alert
resource "cloudflare_notification_policy" "abuse_report" {
  account_id  = var.CF_ACCOUNT_ID
  name        = "Cloudflare Abuse Report Alert"
  description = "Alert when an abuse report is filed against your website"
  enabled     = true
  alert_type  = "abuse_report_alert"

  mechanisms = {
    email = [{
      id = var.PUSHOVER_CLOUDFLARE_EMAIL
    }]
  }
}
