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

  test "token route fulfills only the HTTPS POS Keycloak oid4vc-pos token endpoint" do
    assert probe.send(:pos_token_endpoint?,
      "https://keycloak-pos.eudi-adorsys.com/realms/oid4vc-pos/protocol/openid-connect/token")
    assert probe.send(:pos_token_endpoint?,
      "https://keycloak-pos.eudi-adorsys.com:443/realms/oid4vc-pos/protocol/openid-connect/token")
    assert probe.send(:pos_token_endpoint?,
      "https://keycloak-pos.eudi-adorsys.com/realms/oid4vc-pos/protocol/openid-connect/token?grant_type=password")
  end

  test "token route does not fulfill an unrelated host or realm path" do
    assert_not probe.send(:pos_token_endpoint?,
      "https://evil.example/realms/oid4vc-pos/protocol/openid-connect/token")
    assert_not probe.send(:pos_token_endpoint?,
      "https://example.com/proxy?url=https://keycloak-pos.eudi-adorsys.com/realms/oid4vc-pos/protocol/openid-connect/token")
    assert_not probe.send(:pos_token_endpoint?,
      "https://registry.eudi-adorsys.com/callback?next=/protocol/openid-connect/token")
    assert_not probe.send(:pos_token_endpoint?,
      "https://evil.example/foo%2Fprotocol%2Fopenid-connect%2Ftoken")
    assert_not probe.send(:pos_token_endpoint?,
      "https://keycloak-pos.eudi-adorsys.com.evil.example/realms/oid4vc-pos/protocol/openid-connect/token")
    assert_not probe.send(:pos_token_endpoint?,
      "https://keycloak-pos.eudi-adorsys.com@evil.example/realms/oid4vc-pos/protocol/openid-connect/token")
    assert_not probe.send(:pos_token_endpoint?,
      "https://keycloak-pos.eudi-adorsys.com/realms/other/protocol/openid-connect/token")
    assert_not probe.send(:pos_token_endpoint?,
      "https://keycloak-pos.eudi-adorsys.com/realms/oid4vc-pos/protocol/openid-connect/token/extra")
    assert_not probe.send(:pos_token_endpoint?,
      "https://keycloak-pos.eudi-adorsys.com/realms/oid4vc-pos/protocol/openid-connect/tokenized")
    assert_not probe.send(:pos_token_endpoint?,
      "http://keycloak-pos.eudi-adorsys.com/realms/oid4vc-pos/protocol/openid-connect/token")
    assert_not probe.send(:pos_token_endpoint?,
      "https://keycloak-pos.eudi-adorsys.com:8443/realms/oid4vc-pos/protocol/openid-connect/token")
    assert_not probe.send(:pos_token_endpoint?,
      "https://keycloak-pos.eudi-adorsys.com/realms/oid4vc-pos/protocol/openid-connect/auth")
  end

  private
    def probe
      Probes::Playwright::VerifierPosIssuanceProbe.new
    end
end
