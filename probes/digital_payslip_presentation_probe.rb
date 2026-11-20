class Probes::Playwright::DigitalPayslipPresentationProbe < Upright::Probes::Playwright::Base
  authenticate_with_form :digital_payslip

  APP_URL = "https://digitaler-gehaltsnachweis.eudi-adorsys.com/".freeze

  def check
    page.goto(APP_URL, timeout: 30.seconds.in_ms)
    page.get_by_role("button", name: "Kreditantrag").click
    page.get_by_role("heading", name: "QR-Code mit Ihrer EUDI-Wallet scannen").wait_for(timeout: 60.seconds.in_ms)
    page.locator("main.loan-content svg[width='200'][height='200']").wait_for(timeout: 60.seconds.in_ms)
    true
  end

  def probe_target = APP_URL
end
