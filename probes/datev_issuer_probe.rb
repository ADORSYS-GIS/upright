class Probes::Playwright::DatevIssuerProbe < Upright::Probes::Playwright::Base
  authenticate_with_form :datev_issuer

  ISSUER_URL = "https://adorsys-gis.github.io/keycloak-oid4vc-mock-fe-datev/".freeze

  def check
    page.get_by_role("heading", name: "You are logged in").wait_for(timeout: 30.seconds.in_ms)
    page.locator("svg").first.wait_for(timeout: 60.seconds.in_ms)
  end

  def probe_target = ISSUER_URL
end
