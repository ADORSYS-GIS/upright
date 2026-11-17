require "test_helper"

class ProbeResultMetricsTest < ActiveSupport::TestCase
  test "recording a Playwright probe result writes its Prometheus gauges" do
    Upright::ProbeResult.create!(
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
  end
end
