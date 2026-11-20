class Playwright::Authenticator::DigitalPayslip < Upright::Playwright::Authenticator::Base
  APP_URL = "https://digitaler-gehaltsnachweis.eudi-adorsys.com/".freeze
  KEYCLOAK_REALM_PATH = "/realms/oid4vc-payslip".freeze

  def signin_redirect_url = APP_URL
  def signin_path = KEYCLOAK_REALM_PATH
  def service_name = :digital_payslip

  def session_valid_on?(page)
    wait_for_network_idle(page)
    page.get_by_role("button", name: "Mein Gehaltsnachweis").count.positive?
  end

  def authenticate
    page.goto(APP_URL, timeout: 30.seconds.in_ms)
    page.locator("#username").fill(username)
    page.locator("#password").fill(password)
    page.locator("#kc-login").click
    page.get_by_role("button", name: "Mein Gehaltsnachweis").wait_for(timeout: 60.seconds.in_ms)
  end

  private
    def username
      ENV.fetch("KEYCLOAK_OID4VC_PAYSLIP_USERNAME")
    end

    def password
      ENV.fetch("KEYCLOAK_OID4VC_PAYSLIP_PASSWORD")
    end
end
