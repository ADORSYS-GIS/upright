require "net/http"
require "uri"

class Probes::Playwright::VerifierPosIssuanceProbe < Upright::Probes::Playwright::Base
  REGISTRY_URL = "https://registry.eudi-adorsys.com/".freeze
  KEYCLOAK_URL = "https://keycloak-pos.eudi-adorsys.com".freeze
  KEYCLOAK_REALM = "oid4vc-pos".freeze
  KEYCLOAK_HOST = URI.parse(KEYCLOAK_URL).host.freeze
  CLIENT_ID = "openid4vc-rest-api".freeze

  ALLOWED_OFFER_PATHS = [
    "/realms/#{KEYCLOAK_REALM}/protocol/oid4vc/create-credential-offer",
    "/realms/#{KEYCLOAK_REALM}/protocol/oid4vc/credential-offer-uri"
  ].freeze

  def check
    keycloak_requests = []
    token_response = fetch_issuance_token
    page.route(%r{(/|%2F)protocol(/|%2F)openid-connect(/|%2F)token}) do |route|
      route.fulfill(
        status: 200,
        content_type: "application/json",
        body: token_response
      )
    end

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
    def fetch_issuance_token
      uri = URI("#{KEYCLOAK_URL}/realms/#{KEYCLOAK_REALM}/protocol/openid-connect/token")
      response = Net::HTTP.post_form(uri, {
        "client_id" => CLIENT_ID,
        "client_secret" => ENV.fetch("KEYCLOAK_POS_CLIENT_SECRET"),
        "username" => ENV.fetch("KEYCLOAK_POS_USERNAME"),
        "password" => ENV.fetch("KEYCLOAK_POS_PASSWORD"),
        "grant_type" => "password",
        "scope" => "openid"
      })
      raise "Failed to fetch POS issuance token: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      response.body
    end

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
