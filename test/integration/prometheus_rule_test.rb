require "test_helper"
require "open3"
require "tmpdir"
require "yaml"

class PrometheusRuleTest < ActionDispatch::IntegrationTest
  test "missing alerts are configured with targets and detect stopped metrics" do
    unconfigured_stdout, unconfigured_status = Open3.capture2e(
      "helm",
      "template",
      "upright",
      "./charts/upright",
      "--namespace",
      "monitoring"
    )

    assert unconfigured_status.success?, unconfigured_stdout

    unconfigured_documents = YAML.load_stream(unconfigured_stdout)
    unconfigured_rule = unconfigured_documents.find do |doc|
      doc.is_a?(Hash) && doc["kind"] == "PrometheusRule"
    end
    assert unconfigured_rule, "PrometheusRule manifest was not rendered for the empty install"

    unconfigured_alert_names = unconfigured_rule.dig("spec", "groups").flat_map { |group| group["rules"] }
      .filter_map { |entry| entry["alert"] }
    assert_not_includes unconfigured_alert_names, "UprightHTTPProbesMissing"
    assert_not_includes unconfigured_alert_names, "UprightPlaywrightProbesMissing"

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

    probe_values = YAML.safe_load_file("./charts/upright/values-probes.yaml")
    configured_targets = probe_values.dig("prometheusRule", "configuredProbeTargets")
    http_targets = configured_targets.select { |target| target["type"] == "http" }
    playwright_targets = configured_targets.select { |target| target["type"] == "playwright" }

    chart_http_probes = YAML.safe_load(
      probe_values.dig("app-template", "configMaps", "http-probes", "data", "http_probes.yml")
    )
    chart_http_names = chart_http_probes.map { |probe| probe.fetch("name") }.sort
    assert_equal chart_http_names, http_targets.map { |target| target.fetch("name") }.sort
    assert_equal chart_http_names, YAML.safe_load_file("./probes/http_probes.yml").map { |probe| probe.fetch("name") }.sort

    scheduled_playwright_names = YAML.safe_load_file("./config/recurring.yml").fetch("production").values.filter_map do |job|
      class_name = job["command"]&.match(/Probes::Playwright::([A-Za-z]+Probe)/)&.captures&.first
      class_name&.delete_suffix("Probe")&.underscore
    end.uniq.sort
    assert_equal scheduled_playwright_names, playwright_targets.map { |target| target.fetch("name") }.sort

    http_missing_rules = rules.select { |entry| entry["alert"] == "UprightHTTPProbesMissing" }
    playwright_missing_rules = rules.select { |entry| entry["alert"] == "UprightPlaywrightProbesMissing" }

    assert_equal http_targets.size, http_missing_rules.size
    assert_equal playwright_targets.size, playwright_missing_rules.size

    http_targets.each do |target|
      target_rule = http_missing_rules.find { |entry| entry["expr"].include?(%Q(name=#{target.fetch("name").to_json})) }
      assert target_rule, "HTTP missing rule was not rendered for #{target.fetch("name") }"
      assert_includes target_rule["expr"], "absent_over_time(upright_probe_up{type=\"http\", name=#{target.fetch("name").to_json}}[5m])"
      assert_nil target_rule["for"], "HTTP missing alert must not add another pending period"
    end

    playwright_targets.each do |target|
      target_rule = playwright_missing_rules.find { |entry| entry["expr"].include?(%Q(name=#{target.fetch("name").to_json})) }
      assert target_rule, "Playwright missing rule was not rendered for #{target.fetch("name") }"
      assert_includes target_rule["expr"], "absent(upright_probe_up{type=\"playwright\", name=#{target.fetch("name").to_json}})"
    end

    promtool = "promtool"
    skip "promtool is required to evaluate Prometheus alert rules" unless system(promtool, "--version", out: File::NULL, err: File::NULL)

    rules = [ http_missing_rules.first, playwright_missing_rules.first ].map do |entry|
      entry.slice("alert", "expr", "for", "labels")
    end

    Dir.mktmpdir("upright-prometheus-rules") do |directory|
      rules_path = File.join(directory, "rules.yml")
      tests_path = File.join(directory, "tests.yml")

      File.write(rules_path, YAML.dump("groups" => [ { "name" => "missing_probe_tests", "rules" => rules } ]))
      File.write(tests_path, YAML.dump(promtool_test_cases(rules_path, http_targets.first, playwright_targets.first)))

      output, status = Open3.capture2e(promtool, "test", "rules", tests_path)
      assert status.success?, output
    end
  end

  private
    def promtool_test_cases(rules_path, http_target, playwright_target)
      alert_names = {
        "http" => [ "UprightHTTPProbesMissing", http_target.fetch("name") ],
        "playwright" => [ "UprightPlaywrightProbesMissing", playwright_target.fetch("name") ]
      }

      expected_alerts = alert_names.map do |type, (alertname, target_name)|
        fired_alert = {
          "exp_labels" => {
            "alertname" => alertname,
            "type" => type,
            "name" => target_name,
            "severity" => "critical",
            "group" => "upright"
          }
        }

        if type == "http"
          [
            { "eval_time" => "0s", "alertname" => alertname, "exp_alerts" => [ fired_alert ] },
            { "eval_time" => "4m30s", "alertname" => alertname, "exp_alerts" => [ fired_alert ] }
          ]
        else
          [
            { "eval_time" => "29m30s", "alertname" => alertname, "exp_alerts" => [] },
            { "eval_time" => "30m", "alertname" => alertname, "exp_alerts" => [ fired_alert ] }
          ]
        end
      end
      expected_alerts = expected_alerts.flatten

      expected_stopped_alerts = alert_names.map do |type, (alertname, target_name)|
        fired_alert = {
          "exp_labels" => {
            "alertname" => alertname,
            "type" => type,
            "name" => target_name,
            "severity" => "critical",
            "group" => "upright"
          }
        }

        if type == "http"
          [
            { "eval_time" => "4m30s", "alertname" => alertname, "exp_alerts" => [] },
            { "eval_time" => "5m", "alertname" => alertname, "exp_alerts" => [ fired_alert ] }
          ]
        else
          [
            { "eval_time" => "30m", "alertname" => alertname, "exp_alerts" => [] },
            { "eval_time" => "30m30s", "alertname" => alertname, "exp_alerts" => [ fired_alert ] }
          ]
        end
      end.flatten

      {
        "rule_files" => [ rules_path ],
        "evaluation_interval" => "30s",
        "tests" => [
          {
            "name" => "configured probes with no first metric follow missing-alert timing",
            "interval" => "30s",
            "input_series" => [],
            "alert_rule_test" => expected_alerts
          },
          {
            "name" => "reported probes that stop are detected",
            "interval" => "30s",
            "input_series" => alert_names.map do |type, (_alertname, target_name)|
              values = type == "http" ? "1" : "1 stale"
              other_target = type == "http" ? "nginx proxy" : "verifier_pos_new_order"
              [
                { "series" => "upright_probe_up{type=\"#{type}\", name=#{target_name.to_json}}", "values" => values },
                { "series" => "upright_probe_up{type=\"#{type}\", name=#{other_target.to_json}}", "values" => "1+0x60" }
              ]
            end.flatten,
            "alert_rule_test" => expected_stopped_alerts
          }
        ]
      }
    end
end
