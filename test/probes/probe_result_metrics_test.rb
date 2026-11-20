require "test_helper"

class ProbeResultMetricsTest < ActiveSupport::TestCase
  test "recording a Playwright probe result writes its Prometheus gauges" do
    result = Upright::ProbeResult.create!(
      probe_name: "metric-smoke",
      probe_type: "playwright",
      probe_target: "https://example.invalid/",
      probe_service: "datev_issuer",
      status: :ok,
      duration: 0.125
    )

    labels = {
      type: "playwright",
      name: "metric-smoke",
      probe_target: "https://example.invalid/",
      probe_service: "datev_issuer",
      alert_severity: :high
    }

    assert_equal 1, Yabeda.upright_probe_up.get(labels)
    assert_equal 0.125, Yabeda.upright_probe_duration_seconds.get(labels.merge(status: "ok"))
    assert_in_delta result.created_at.to_f, Yabeda.upright_probe_last_run_timestamp_seconds.get(labels), 1
  end

  test "recording a failed Playwright probe result sets upright_probe_up to 0" do
    result = Upright::ProbeResult.create!(
      probe_name: "metric-smoke-fail",
      probe_type: "playwright",
      probe_target: "https://example.invalid/fail",
      probe_service: "datev_issuer",
      status: :fail,
      duration: 0.25
    )

    labels = {
      type: "playwright",
      name: "metric-smoke-fail",
      probe_target: "https://example.invalid/fail",
      probe_service: "datev_issuer",
      alert_severity: :high
    }

    assert_equal 0, Yabeda.upright_probe_up.get(labels)
    assert_equal 0.25, Yabeda.upright_probe_duration_seconds.get(labels.merge(status: "fail"))
    assert_in_delta result.created_at.to_f, Yabeda.upright_probe_last_run_timestamp_seconds.get(labels), 1
  end
end
