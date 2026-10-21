# Prometheus and Alertmanager UIs are SPAs loaded in an iframe. Rails treats
# their proxied .js assets as a cross-origin script embed and returns 422,
# so the iframes render blank. Skip that check on the proxy controllers only.
Rails.application.config.to_prepare do
  [ Upright::PrometheusProxyController, Upright::AlertmanagerProxyController ].each do |controller|
    controller.skip_after_action :verify_same_origin_request, raise: false
  end
end
