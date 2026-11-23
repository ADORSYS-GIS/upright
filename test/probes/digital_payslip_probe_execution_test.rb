require "test_helper"
require "tmpdir"
require_relative "../../probes/authenticators/digital_payslip"
require_relative "../../probes/digital_payslip_issuance_probe"
require_relative "../../probes/digital_payslip_presentation_probe"

class DigitalPayslipProbeExecutionTest < ActiveJob::TestCase
  test "queued Digital Payslip issuance probe authenticates and records a successful Prometheus metric" do
    with_payslip_env do
      fake_page = FakePage.new
      fake_context = FakeContext.new(fake_page)
      fake_browser = FakeBrowser.new(fake_context)
      original_storage_state_dir = Upright.configuration.storage_state_dir
      Thread.current[:payslip_probe_fake_browser] = fake_browser
      Probes::Playwright::DigitalPayslipIssuanceProbe.prepend(BrowserLauncherOverride)

      Dir.mktmpdir("payslip-probe-storage") do |directory|
        Upright.configuration.storage_state_dir = Pathname.new(directory)
        perform_enqueued_jobs do
          Probes::Playwright::DigitalPayslipIssuanceProbe.check_and_record_later
        end
      end

      result = Upright::ProbeResult.where(probe_name: "digital_payslip_issuance").order(:id).last
      assert result, "queued Digital Payslip issuance probe did not record a result"
      assert result.ok?, "exception=#{result.exception_report.inspect}; artifacts=#{result.artifacts.map { |a| a.filename.to_s }}"
      assert_equal "playwright", result.probe_type
      assert_equal Probes::Playwright::DigitalPayslipIssuanceProbe::APP_URL, result.probe_target
      assert_equal 1, Yabeda.upright_probe_up.get(
        type: "playwright",
        name: "digital_payslip_issuance",
        probe_target: Probes::Playwright::DigitalPayslipIssuanceProbe::APP_URL,
        probe_service: "digital_payslip",
        alert_severity: :high
      )
      assert fake_page.authenticated, "Digital Payslip authenticator did not complete the login"
      assert_equal "payslip-user", fake_page.fills.fetch("#username")
      assert_equal "payslip-password", fake_page.fills.fetch("#password")
      assert_equal 1, fake_page.locator_waits.fetch(".qr-code-wrapper svg")
    ensure
      Thread.current[:payslip_probe_fake_browser] = nil
      Upright.configuration.storage_state_dir = original_storage_state_dir
    end
  end

  test "queued Digital Payslip presentation probe authenticates and records a successful Prometheus metric" do
    with_payslip_env do
      fake_page = FakePage.new
      fake_context = FakeContext.new(fake_page)
      fake_browser = FakeBrowser.new(fake_context)
      original_storage_state_dir = Upright.configuration.storage_state_dir
      Thread.current[:payslip_probe_fake_browser] = fake_browser
      Probes::Playwright::DigitalPayslipPresentationProbe.prepend(BrowserLauncherOverride)

      Dir.mktmpdir("payslip-probe-storage") do |directory|
        Upright.configuration.storage_state_dir = Pathname.new(directory)
        perform_enqueued_jobs do
          Probes::Playwright::DigitalPayslipPresentationProbe.check_and_record_later
        end
      end

      result = Upright::ProbeResult.where(probe_name: "digital_payslip_presentation").order(:id).last
      assert result, "queued Digital Payslip presentation probe did not record a result"
      assert result.ok?, "exception=#{result.exception_report.inspect}; artifacts=#{result.artifacts.map { |a| a.filename.to_s }}"
      assert_equal "playwright", result.probe_type
      assert_equal Probes::Playwright::DigitalPayslipPresentationProbe::APP_URL, result.probe_target
      assert_equal 1, Yabeda.upright_probe_up.get(
        type: "playwright",
        name: "digital_payslip_presentation",
        probe_target: Probes::Playwright::DigitalPayslipPresentationProbe::APP_URL,
        probe_service: "digital_payslip",
        alert_severity: :high
      )
      assert fake_page.authenticated, "Digital Payslip authenticator did not complete the login"
      assert_equal 1, fake_page.locator_waits.fetch("main.loan-content svg[width='200'][height='200']")
    ensure
      Thread.current[:payslip_probe_fake_browser] = nil
      Upright.configuration.storage_state_dir = original_storage_state_dir
    end
  end

  private
    def with_payslip_env
      username_key = "KEYCLOAK_OID4VC_PAYSLIP_USERNAME"
      password_key = "KEYCLOAK_OID4VC_PAYSLIP_PASSWORD"
      prev_user = ENV[username_key]
      prev_pass = ENV[password_key]
      ENV[username_key] = "payslip-user"
      ENV[password_key] = "payslip-password"
      yield
    ensure
      ENV[username_key] = prev_user
      ENV[password_key] = prev_pass
    end

    BrowserLauncherOverride = Module.new do
      def with_browser(&block)
        fake_browser = Thread.current[:payslip_probe_fake_browser]
        return super unless fake_browser

        block.call(fake_browser)
      end
    end

    class FakeBrowser
      def initialize(context)
        @context = context
      end

      def new_context(**)
        @context
      end
    end

    class FakeContext
      def initialize(page)
        @page = page
      end

      def new_page
        @page
      end

      def storage_state
        { "cookies" => [] }
      end

      def close
      end
    end

    class FakePage
      attr_reader :authenticated, :locator_waits, :fills

      def initialize
        @authenticated = false
        @locator_waits = Hash.new(0)
        @fills = {}
        @url = Probes::Playwright::DigitalPayslipIssuanceProbe::APP_URL
      end

      def url
        @url
      end

      def goto(url, **)
        @url = url
        true
      end

      def wait_for_load_state(state:)
        raise "expected networkidle" unless state == "networkidle"
      end

      def evaluate(_script)
        0
      end

      def close
      end

      def get_by_role(role, name:)
        if role == "button" && name == "Mein Gehaltsnachweis"
          FakeLocator.new(self, "button-mein-gehaltsnachweis")
        elsif role == "button" && name == "Kreditantrag"
          FakeLocator.new(self, "button-kreditantrag")
        elsif role == "heading" && name == "Digitaler Gehaltsnachweis"
          FakeLocator.new(self, "heading-digitaler-gehaltsnachweis")
        elsif role == "heading" && name == "QR-Code mit Ihrer EUDI-Wallet scannen"
          FakeLocator.new(self, "heading-qr-scannen")
        else
          raise "unexpected role locator: #{role} #{name}"
        end
      end

      def locator(selector)
        FakeLocator.new(self, selector)
      end

      def on(_event, _callback)
      end
    end

    class FakeLocator
      def initialize(page, selector)
        @page = page
        @selector = selector
      end

      def count
        @selector == "button-mein-gehaltsnachweis" && @page.authenticated ? 1 : 0
      end

      def wait_for(**)
        @page.locator_waits[@selector] += 1
        raise "expected an authenticated session" if @selector == "button-mein-gehaltsnachweis" && !@page.authenticated
        nil
      end

      def fill(value)
        @page.fills[@selector] = value
      end

      def click
        @page.instance_variable_set(:@authenticated, true) if @selector == "#kc-login"
      end
    end
end
