require "test_helper"
require_relative "../../probes/verifier_pos_issuance_probe"

class VerifierPosIssuanceProbeTest < ActiveSupport::TestCase
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
end
