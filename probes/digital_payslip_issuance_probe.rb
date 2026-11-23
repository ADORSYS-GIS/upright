class Probes::Playwright::DigitalPayslipIssuanceProbe < Upright::Probes::Playwright::Base
  authenticate_with_form :digital_payslip

  APP_URL = "https://digitaler-gehaltsnachweis.eudi-adorsys.com/".freeze

  def check
    page.goto(APP_URL, timeout: 30.seconds.in_ms)
    page.get_by_role("button", name: "Mein Gehaltsnachweis").click
    page.get_by_role("heading", name: "Digitaler Gehaltsnachweis").wait_for(timeout: 60.seconds.in_ms)
    page.locator(".qr-code-wrapper svg").wait_for(timeout: 60.seconds.in_ms)
    true
  end

  def probe_target = APP_URL
end
