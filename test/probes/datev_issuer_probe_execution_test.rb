require "test_helper"
require "tmpdir"
require_relative "../../probes/authenticators/datev_issuer"
require_relative "../../probes/datev_issuer_probe"

class DatevIssuerProbeExecutionTest < ActiveJob::TestCase
  test "queued DATEV probe authenticates and records a successful Prometheus metric" do
    username_key = "KEYCLOAK_OID4VC_USERNAME"
    password_key = "KEYCLOAK_OID4VC_PASSWORD"
    previous_username = ENV[username_key]
    previous_password = ENV[password_key]
    ENV[username_key] = "probe-user"
    ENV[password_key] = "probe-password"

    fake_page = FakePage.new
    fake_context = FakeContext.new(fake_page)
    fake_browser = FakeBrowser.new(fake_context)
    original_storage_state_dir = Upright.configuration.storage_state_dir
    Thread.current[:datev_probe_fake_browser] = fake_browser
    Probes::Playwright::DatevIssuerProbe.prepend(BrowserLauncherOverride)

    Dir.mktmpdir("datev-probe-storage") do |directory|
      Upright.configuration.storage_state_dir = Pathname.new(directory)
      perform_enqueued_jobs do
        Probes::Playwright::DatevIssuerProbe.check_and_record_later
      end
    end

    result = Upright::ProbeResult.where(probe_name: "datev_issuer").order(:id).last
    assert result, "queued DATEV probe did not record a result"
    assert result.ok?, "exception=#{result.exception_report.inspect}; artifacts=#{result.artifacts.map { |artifact| artifact.filename.to_s }}"
    assert_equal "playwright", result.probe_type
    assert_equal Probes::Playwright::DatevIssuerProbe::ISSUER_URL, result.probe_target
    assert_equal "datev_issuer", result.probe_service
    assert_equal 1, Yabeda.upright_probe_up.get(
      type: "playwright",
      name: "datev_issuer",
      probe_target: Probes::Playwright::DatevIssuerProbe::ISSUER_URL,
      probe_service: "datev_issuer",
      alert_severity: :high
    )
    assert fake_page.authenticated, "DATEV authenticator did not complete the login"
    assert_equal "probe-user", fake_page.fills.fetch("#username")
    assert_equal "probe-password", fake_page.fills.fetch("#password")
    assert_equal 1, fake_page.locator_waits.fetch("svg")
  ensure
    Thread.current[:datev_probe_fake_browser] = nil
    Upright.configuration.storage_state_dir = original_storage_state_dir
    ENV[username_key] = previous_username
    ENV[password_key] = previous_password
  end

  private
    BrowserLauncherOverride = Module.new do
      def with_browser(&block)
        fake_browser = Thread.current[:datev_probe_fake_browser]
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
        if role == "heading" && name == "You are logged in"
          FakeLocator.new(self, "authenticated-heading")
        elsif role == "button" && name == "Login with Keycloak"
          FakeLocator.new(self, "login-button")
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
        @selector == "authenticated-heading" && @page.authenticated ? 1 : 0
      end

      def wait_for(**)
        @page.locator_waits[@selector] += 1
        raise "expected an authenticated session" if @selector == "authenticated-heading" && !@page.authenticated
      end

      def first
        self
      end

      def fill(value)
        @page.fills[@selector] = value
      end

      def click
        @page.instance_variable_set(:@authenticated, true) if @selector == "#kc-login"
      end
    end

end
