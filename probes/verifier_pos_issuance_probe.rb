require "uri"

class Probes::Playwright::VerifierPosIssuanceProbe < Upright::Probes::Playwright::Base
  REGISTRY_URL = "https://registry.eudi-adorsys.com/".freeze
  KEYCLOAK_HOST = "keycloak-pos.eudi-adorsys.com".freeze
  KEYCLOAK_REALM = "oid4vc-pos".freeze

  ALLOWED_OFFER_PATHS = [
    "/realms/#{KEYCLOAK_REALM}/protocol/oid4vc/create-credential-offer",
    "/realms/#{KEYCLOAK_REALM}/protocol/oid4vc/credential-offer-uri"
  ].freeze

  def check
    keycloak_requests = []
    page.on("request") { |request| keycloak_requests << request.url }
    page.goto(REGISTRY_URL, timeout: 30.seconds.in_ms)
    page.get_by_role("button", name: "Open issuance flow").click
    page.get_by_role("heading", name: "Issuance Flow").wait_for(timeout: 30.seconds.in_ms)
    page.get_by_role("img", name: /credential offer QR/i).wait_for(timeout: 60.seconds.in_ms)
    verify_credential_offer_realm!(keycloak_requests)
    true
  end

  def probe_target = REGISTRY_URL
  def probe_service = "oid4vc_keycloak_pos"

  private
    def verify_credential_offer_realm!(request_urls)
      valid = request_urls.any? do |url|
        uri = URI.parse(url)
        uri.host == KEYCLOAK_HOST && ALLOWED_OFFER_PATHS.include?(uri.path)
      rescue URI::InvalidURIError
        false
      end

      return true if valid

      raise "POS issuance did not request a credential offer from Keycloak realm #{KEYCLOAK_REALM}"
    end
end
