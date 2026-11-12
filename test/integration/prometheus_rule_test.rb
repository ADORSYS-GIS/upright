require "test_helper"
require "open3"
require "yaml"

class PrometheusRuleTest < ActionDispatch::IntegrationTest
  test "missing alerts only fire after configured targets exist" do
    stdout, status = Open3.capture2e(
      "helm",
      "template",
      "upright",
      "./charts/upright",
      "--namespace",
      "monitoring",
      "--values",
      "./charts/upright/values-probes.yaml"
    )

    assert status.success?, stdout

    documents = YAML.load_stream(stdout)
    rule = documents.find { |doc| doc.is_a?(Hash) && doc["kind"] == "PrometheusRule" }
    assert rule, "PrometheusRule manifest was not rendered"

    rules = rule.dig("spec", "groups").flat_map { |group| group["rules"] }

    http_missing_rule = rules.find { |entry| entry["alert"] == "UprightHTTPProbesMissing" }
    playwright_missing_rule = rules.find { |entry| entry["alert"] == "UprightPlaywrightProbesMissing" }

    assert http_missing_rule, "UprightHTTPProbesMissing rule was not rendered"
    assert playwright_missing_rule, "UprightPlaywrightProbesMissing rule was not rendered"

    assert_includes http_missing_rule["expr"], "count by () (max_over_time(upright_probe_up{type=\"http\"}[1h])) > 0"
    assert_includes http_missing_rule["expr"], "count by () (max_over_time(upright_probe_up{type=\"http\"}[5m])) == 0"

    assert_includes playwright_missing_rule["expr"], "count by () (max_over_time(upright_probe_up{type=\"playwright\"}[1h])) > 0"
    assert_includes playwright_missing_rule["expr"], "count by () (max_over_time(upright_probe_up{type=\"playwright\"}[5m])) == 0"
  end
end
