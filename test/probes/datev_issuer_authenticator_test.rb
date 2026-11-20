require "test_helper"
require_relative "../../probes/authenticators/datev_issuer"

class DatevIssuerAuthenticatorTest < ActiveSupport::TestCase
  test "anonymous issuer landing page is not an authenticated session" do
    page = FakePage.new(authenticated: false)

    assert_not authenticator.session_valid_on?(page)
    assert_equal 1, page.network_idle_checks
  end

  test "logged-in issuer page is a valid authenticated session" do
    page = FakePage.new(authenticated: true)

    assert authenticator.session_valid_on?(page)
    assert_equal 1, page.network_idle_checks
  end

  private
    def authenticator
      Playwright::Authenticator::DatevIssuer.new
    end

    class FakePage
      attr_reader :network_idle_checks

      def initialize(authenticated:)
        @authenticated = authenticated
        @network_idle_checks = 0
      end

      def wait_for_load_state(state:)
        raise "expected networkidle" unless state == "networkidle"

        @network_idle_checks += 1
      end

      def get_by_role(role, name:)
        raise "unexpected locator" unless role == "heading" && name == "You are logged in"

        FakeLocator.new(@authenticated ? 1 : 0)
      end
    end

    FakeLocator = Struct.new(:count)
end
