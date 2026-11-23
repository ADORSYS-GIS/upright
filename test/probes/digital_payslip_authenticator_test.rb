require "test_helper"
require_relative "../../probes/authenticators/digital_payslip"

class DigitalPayslipAuthenticatorTest < ActiveSupport::TestCase
  test "anonymous payslip landing page is not an authenticated session" do
    page = FakePage.new(authenticated: false)

    assert_not authenticator.session_valid_on?(page)
    assert_equal 1, page.network_idle_checks
  end

  test "logged-in payslip page is a valid authenticated session" do
    page = FakePage.new(authenticated: true)

    assert authenticator.session_valid_on?(page)
    assert_equal 1, page.network_idle_checks
  end

  private
    def authenticator
      Playwright::Authenticator::DigitalPayslip.new
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
        raise "unexpected locator: #{role} #{name}" unless role == "button" && name == "Mein Gehaltsnachweis"

        FakeLocator.new(@authenticated ? 1 : 0)
      end
    end

    FakeLocator = Struct.new(:count)
end
