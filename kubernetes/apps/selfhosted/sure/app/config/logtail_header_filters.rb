# Sure pins logtail-rack 0.2.6, whose request event logs raw headers, so the permanent
# session_token cookie lands in stdout -> VictoriaLogs. 0.2.7+ filters these by default.
# debt: local workaround, drop once the Sure image ships logtail-rack >= 0.2.7
Logtail::Integrations::Rack::HTTPEvents.http_header_filters = %w[Authorization Proxy-Authorization Cookie Set-Cookie]
