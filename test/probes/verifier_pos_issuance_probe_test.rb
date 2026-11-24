require "test_helper"
require_relative "../../probes/verifier_pos_issuance_probe"

class VerifierPosIssuanceProbeTest < ActiveSupport::TestCase
  test "check returns true when Open issuance flow shows a POS Keycloak credential-offer QR" do
    offer_url = "https://keycloak-pos.eudi-adorsys.com/realms/oid4vc-pos/protocol/oid4vc/credential-offer-uri?type=qr-code"
    fake_page = FakePage.new(click_request_urls: [ offer_url ])
    probe = Probes::Playwright::VerifierPosIssuanceProbe.new
    probe.instance_variable_set(:@page, fake_page)

    assert_equal true, probe.check
    assert_equal Probes::Playwright::VerifierPosIssuanceProbe::REGISTRY_URL, fake_page.visited_url
    assert fake_page.button_clicked
    assert_includes fake_page.emitted_request_urls, offer_url
    assert fake_page.request_emitted_after_click
    assert fake_page.heading_waited
    assert fake_page.qr_waited
    assert fake_page.qr_waited_after_request
  end

  test "check raises when the page never requests a POS Keycloak credential offer" do
    fake_page = FakePage.new(click_request_urls: [ "https://example.com/unrelated" ])
    probe = Probes::Playwright::VerifierPosIssuanceProbe.new
    probe.instance_variable_set(:@page, fake_page)

    error = assert_raises(RuntimeError) { probe.check }
    assert_includes error.message, "oid4vc-pos"
  end

  test "accepts credential-offer requests using credential-offer-uri for the POS Keycloak realm" do
    assert probe.send(:verify_credential_offer_realm!, [
      "https://keycloak-pos.eudi-adorsys.com/realms/oid4vc-pos/protocol/oid4vc/credential-offer-uri?type=qr-code"
    ])
  end

  test "accepts credential-offer requests using create-credential-offer for the POS Keycloak realm" do
    assert probe.send(:verify_credential_offer_realm!, [
      "https://keycloak-pos.eudi-adorsys.com/realms/oid4vc-pos/protocol/oid4vc/create-credential-offer"
    ])
  end

  test "rejects credential-offer requests from a different Keycloak realm" do
    error = assert_raises(RuntimeError) do
      probe.send(:verify_credential_offer_realm!, [
        "https://keycloak-pos.eudi-adorsys.com/realms/other/protocol/oid4vc/credential-offer-uri"
      ])
    end

    assert_includes error.message, "oid4vc-pos"
  end

  test "rejects credential-offer requests from an unrelated origin whose query contains the offer URL" do
    error = assert_raises(RuntimeError) do
      probe.send(:verify_credential_offer_realm!, [
        "https://example.com/proxy?url=https://keycloak-pos.eudi-adorsys.com/realms/oid4vc-pos/protocol/oid4vc/credential-offer-uri"
      ])
    end

    assert_includes error.message, "oid4vc-pos"
  end

  private
    def probe
      Probes::Playwright::VerifierPosIssuanceProbe.new
    end

    class FakePage
      attr_reader :visited_url, :button_clicked, :heading_waited, :qr_waited,
        :emitted_request_urls, :request_emitted_after_click, :qr_waited_after_request

      def initialize(click_request_urls:)
        @click_request_urls = click_request_urls
        @emitted_request_urls = []
        @request_handler = nil
      end

      def on(event, &block)
        raise "unexpected event: #{event}" unless event == "request"

        @request_handler = block
      end

      def goto(url, timeout:)
        @visited_url = url
      end

      def get_by_role(role, name:)
        if role == "button" && name == "Open issuance flow"
          FakeButton.new(method(:emit_click_requests!))
        elsif role == "heading" && name == "Issuance Flow"
          FakeElement.new(-> { @heading_waited = true })
        elsif role == "img" && name == /credential offer QR/i
          FakeElement.new(method(:mark_qr_waited!))
        else
          raise "unexpected get_by_role: #{role}, #{name.inspect}"
        end
      end

      private
        def emit_click_requests!
          @button_clicked = true
          @click_request_urls.each do |request_url|
            @emitted_request_urls << request_url
            @request_handler&.call(FakeRequest.new(request_url))
          end
          @request_emitted_after_click = @button_clicked && @emitted_request_urls.any?
        end

        def mark_qr_waited!
          @qr_waited = true
          @qr_waited_after_request = @emitted_request_urls.any?
        end
    end

    FakeRequest = Struct.new(:url)

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
