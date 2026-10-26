# Be sure to restart your server when you modify this file.

# Content Security Policy tuned for Upright. Every source the engine actually
# uses is listed explicitly:
#
#   * JavaScript dependencies (Turbo, Stimulus, Leaflet, Frappe Charts) are
#     pinned to https://cdn.jsdelivr.net in the engine's config/importmap.rb.
#   * Stylesheets are same-origin, or the Leaflet CSS on https://unpkg.com.
#     Turbo 8 copies the csp-nonce meta tag onto its progress-bar <style>.
#     Frappe Charts 1.6.2 appends a <style> element and then fills it. The
#     empty element and the finished stylesheet each have a hash below.
#     style-src carries the nonce and those hashes.
#   * style-src-attr keeps 'unsafe-inline'. A nonce does not cover a style
#     attribute. The probe-status matrix sets --cols that way, and Leaflet
#     writes style attributes for map panes, markers, and popups. That is an
#     accepted CSS-injection tradeoff, and it is limited to attributes.
#   * Map tiles come from OpenStreetMap. Leaflet's default marker icons load
#     from unpkg alongside its stylesheet.
#   * form-action is 'self'. It does not fall back to default-src, so the
#     sign-in form cannot be posted to another origin.
#   * The inline <script type="importmap"> tag is authorized by a per-request
#     nonce via csp_meta_tag, which the engine layouts already render.

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src     :self
    policy.font_src        :self, :data
    policy.img_src         :self, :data, "https://unpkg.com",
                           "https://*.tile.openstreetmap.org"
    policy.object_src      :none
    policy.script_src      :self, "https://cdn.jsdelivr.net"
    policy.style_src       :self, "https://unpkg.com",
                           "sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=",
                           "sha256-CssDN67+wdcVeOo1+UBDlTtUvWjUmBJyiyqqRJHhrTQ="
    policy.style_src_attr  :unsafe_inline
    # Source maps for the jsDelivr modules are fetched as connections when DevTools is open.
    policy.connect_src     :self, "https://cdn.jsdelivr.net"
    policy.form_action     :self
    policy.frame_ancestors :self
    policy.base_uri        :self
    # Specify URI for violation reports
    # policy.report_uri "/csp-violation-report-endpoint"
  end

  # A per-request nonce. request.session.id is blank on the first response,
  # which is the sign-in page, so the importmap script would not match.
  # style-src uses the same nonce for Turbo's progress-bar <style>.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end
