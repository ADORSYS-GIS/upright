require "json"

class Probes::Playwright::VerifierPosIssuanceProbe < Upright::Probes::Playwright::Base
  REGISTRY_URL = "https://registry.eudi-adorsys.com/".freeze
  KEYCLOAK_URL = "https://keycloak-pos.eudi-adorsys.com".freeze
  KEYCLOAK_REALM = "oid4vc-pos".freeze
  CREDENTIAL_OFFER_PATH = "/realms/#{KEYCLOAK_REALM}/protocol/oid4vc/credential-offer-uri".freeze
  CREDENTIAL_OFFER_URL = "#{KEYCLOAK_URL}#{CREDENTIAL_OFFER_PATH}".freeze

  def check
    keycloak_requests = []
    page.add_init_script(script: runtime_config_override)
    page.on("request") { |request| keycloak_requests << request.url }
    page.goto(REGISTRY_URL, timeout: 30.seconds.in_ms)
    page.get_by_role("button", name: "Open issuance flow").click
    page.get_by_role("heading", name: "Issuance Flow").wait_for(timeout: 30.seconds.in_ms)
    page.get_by_role("img", name: /credential offer QR/i).wait_for(timeout: 60.seconds.in_ms)
    verify_credential_offer_realm!(keycloak_requests)
  end

  def probe_target = REGISTRY_URL
  def probe_service = "oid4vc_keycloak_pos"

  private
    def runtime_config_override
      overrides = {
        "VITE_KEYCLOAK_URL" => KEYCLOAK_URL,
        "VITE_KEYCLOAK_REALM" => KEYCLOAK_REALM,
        "VITE_KEYCLOAK_USERNAME" => ENV.fetch("KEYCLOAK_POS_USERNAME"),
        "VITE_KEYCLOAK_PASSWORD" => ENV.fetch("KEYCLOAK_POS_PASSWORD")
      }

      <<~JAVASCRIPT
        (() => {
          Object.defineProperty(window, "runtimeConfig", {
            configurable: true,
            set(config) {
              Object.defineProperty(window, "runtimeConfig", {
                configurable: true,
                writable: true,
                value: { ...config, ...#{overrides.to_json} }
              });
            }
          });
        })();
      JAVASCRIPT
    end

    def verify_credential_offer_realm!(request_urls)
      return true if request_urls.any? { |url| url.include?(CREDENTIAL_OFFER_URL) }

      raise "POS issuance did not request a credential offer from Keycloak realm #{KEYCLOAK_REALM}"
    end
end
