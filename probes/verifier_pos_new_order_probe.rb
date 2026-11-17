class Probes::Playwright::VerifierPosNewOrderProbe < Upright::Probes::Playwright::Base
  REGISTRY_URL = "https://registry.eudi-adorsys.com/".freeze

  def check
    page.goto(REGISTRY_URL, timeout: 30.seconds.in_ms)
    page.get_by_role("button", name: "New Order").click
    page.get_by_role("img", name: "Order request QR").wait_for(timeout: 60.seconds.in_ms)
    page.get_by_text(/openid4vp:\/\/authorize/).wait_for(timeout: 30.seconds.in_ms)
  end

  def probe_target = REGISTRY_URL
  def probe_service = "verifier_pos"
end
