# Be sure to restart your server when you modify this file.

# Content Security Policy tuned for Upright. Every source the engine actually
# uses is listed explicitly:
#
#   * JavaScript dependencies (Turbo, Stimulus, Leaflet, Frappe Charts) are
#     pinned to https://cdn.jsdelivr.net in the engine's config/importmap.rb.
#   * The Leaflet stylesheet is loaded from https://unpkg.com in the engine
#     layout; Turbo injects an inline <style> for its progress bar, which is
#     why style-src keeps :unsafe_inline (styles only — scripts stay strict).
#   * Map tiles come from OpenStreetMap. Leaflet's default marker icons load
#     from unpkg alongside its stylesheet.
#   * The inline <script type="importmap"> tag is authorized by a per-session
#     nonce via csp_meta_tag, which the engine layouts already render.

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src     :self
    policy.font_src        :self, :data
    policy.img_src         :self, :data, "https://unpkg.com",
                           "https://*.tile.openstreetmap.org"
    policy.object_src      :none
    policy.script_src      :self, "https://cdn.jsdelivr.net"
    policy.style_src       :self, :unsafe_inline, "https://unpkg.com"
    # Source maps for the jsDelivr modules are fetched as connections when DevTools is open.
    policy.connect_src     :self, "https://cdn.jsdelivr.net"
    policy.frame_ancestors :self
    policy.base_uri        :self
    # Specify URI for violation reports
    # policy.report_uri "/csp-violation-report-endpoint"
  end

  # A per-request nonce. request.session.id is blank on the first response,
  # which is the sign-in page, so the importmap script would not match.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w(script-src)
end
