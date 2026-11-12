class Playwright::Authenticator::DatevIssuer < Upright::Playwright::Authenticator::Base
  ISSUER_URL = "https://adorsys-gis.github.io/keycloak-oid4vc-mock-fe-datev/".freeze
  KEYCLOAK_REALM_PATH = "/realms/oid4vc-vci".freeze

  def signin_redirect_url = ISSUER_URL
  def signin_path = KEYCLOAK_REALM_PATH
  def service_name = :datev_issuer

  def authenticate
    page.goto(ISSUER_URL, timeout: 30.seconds.in_ms)
    page.get_by_role("button", name: "Login with Keycloak").click
    page.locator("#username").fill(username)
    page.locator("#password").fill(password)
    page.locator("#kc-login").click
    page.get_by_role("heading", name: "You are logged in").wait_for(timeout: 60.seconds.in_ms)
  end

  private
    def username
      ENV.fetch("KEYCLOAK_OID4VC_USERNAME")
    end

    def password
      ENV.fetch("KEYCLOAK_OID4VC_PASSWORD")
    end
end
