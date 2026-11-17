require "test_helper"
require_relative "../../probes/verifier_pos_issuance_probe"

class VerifierPosIssuanceProbeTest < ActiveSupport::TestCase
  test "accepts credential-offer requests for the POS Keycloak realm" do
    assert probe.send(:verify_credential_offer_realm!, [
      "#{Probes::Playwright::VerifierPosIssuanceProbe::CREDENTIAL_OFFER_URL}?type=qr-code"
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

  private
    def probe
      Probes::Playwright::VerifierPosIssuanceProbe.new
    end
end
