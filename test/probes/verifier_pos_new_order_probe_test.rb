require "test_helper"
require_relative "../../probes/verifier_pos_new_order_probe"

class VerifierPosNewOrderProbeTest < ActiveSupport::TestCase
  test "check returns true when New Order displays the QR and OpenID4VP URL" do
    fake_page = FakePage.new
    probe = Probes::Playwright::VerifierPosNewOrderProbe.new
    probe.instance_variable_set(:@page, fake_page)

    assert_equal true, probe.check
    assert_equal Probes::Playwright::VerifierPosNewOrderProbe::REGISTRY_URL, fake_page.visited_url
    assert fake_page.button_clicked
    assert fake_page.qr_waited
    assert fake_page.text_waited
  end

  private
    class FakePage
      attr_reader :visited_url, :button_clicked, :qr_waited, :text_waited

      def goto(url, timeout:)
        @visited_url = url
      end

      def get_by_role(role, name:)
        if role == "button" && name == "New Order"
          FakeButton.new(-> { @button_clicked = true })
        elsif role == "img" && name == "Order request QR"
          FakeElement.new(-> { @qr_waited = true })
        else
          raise "unexpected get_by_role: #{role}, #{name}"
        end
      end

      def get_by_text(pattern)
        FakeElement.new(-> { @text_waited = true })
      end
    end

    FakeButton = Struct.new(:on_click) do
      def click
        on_click.call
      end
    end

    FakeElement = Struct.new(:on_wait) do
      def wait_for(timeout:)
        on_wait.call
        nil
      end
    end
end
