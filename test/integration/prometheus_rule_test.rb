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

    scheduled_playwright_names = YAML.safe_load_file("./config/recurring.yml").fetch("production").values.filter_map do |job|
      class_name = job["command"]&.match(/Probes::Playwright::([A-Za-z]+Probe)/)&.captures&.first
      class_name&.delete_suffix("Probe")&.underscore
    end.uniq.sort
    assert_equal scheduled_playwright_names, playwright_targets.map { |target| target.fetch("name") }.sort

    down_fraction = rules.find { |entry| entry["record"] == "upright:probe_down_fraction" }
    uptime_daily = rules.find { |entry| entry["record"] == "upright:probe_uptime_daily" }
    assert down_fraction, "upright:probe_down_fraction recording rule was not rendered"
    assert uptime_daily, "upright:probe_uptime_daily recording rule was not rendered"
    assert_includes down_fraction["expr"], "count by (name, type, probe_target, alert_severity, probe_service, environment)"
    assert_includes uptime_daily["expr"], "sum by (name, type, probe_target, alert_severity, probe_service, environment)"
    assert_includes uptime_daily["expr"], "count by (name, type, probe_target, alert_severity, probe_service, environment)"

    chart_values = YAML.safe_load_file("./charts/upright/values.yaml")
    environment_relabel = chart_values.dig("app-template", "serviceMonitor", "main", "endpoints", 0, "metricRelabelings")
      &.find { |relabel| relabel["targetLabel"] == "environment" }
    assert_equal "production", environment_relabel&.fetch("replacement")

    http_missing_rules = rules.select { |entry| entry["alert"] == "UprightHTTPProbesMissing" }
    playwright_missing_rules = rules.select { |entry| entry["alert"] == "UprightPlaywrightProbesMissing" }

    # Two rules per target: first-run grace (absent + for) and stopped heartbeat (age, no for).
    assert_equal http_targets.size * 2, http_missing_rules.size
    assert_equal playwright_targets.size * 2, playwright_missing_rules.size

    http_targets.each do |target|
      name = target.fetch("name").to_json
      absent_rule = http_missing_rules.find { |entry| entry["expr"].include?(%Q(absent(upright_probe_last_run_timestamp_seconds{type="http", name=#{name}}))) }
      stale_rule = http_missing_rules.find { |entry| entry["expr"].include?(%Q(time() - upright_probe_last_run_timestamp_seconds{type="http", name=#{name}} >= 1200)) }
      assert absent_rule, "HTTP first-run missing rule was not rendered for #{target.fetch("name")}"
      assert stale_rule, "HTTP stopped-heartbeat missing rule was not rendered for #{target.fetch("name")}"
      assert_equal "20m", absent_rule["for"]
      assert_nil stale_rule["for"]
    end

    playwright_targets.each do |target|
      name = target.fetch("name").to_json
      absent_rule = playwright_missing_rules.find { |entry| entry["expr"].include?(%Q(absent(upright_probe_last_run_timestamp_seconds{type="playwright", name=#{name}}))) }
      stale_rule = playwright_missing_rules.find { |entry| entry["expr"].include?(%Q(time() - upright_probe_last_run_timestamp_seconds{type="playwright", name=#{name}} >= 1800)) }
      assert absent_rule, "Playwright first-run missing rule was not rendered for #{target.fetch("name")}"
      assert stale_rule, "Playwright stopped-heartbeat missing rule was not rendered for #{target.fetch("name")}"
      assert_equal "30m", absent_rule["for"]
      assert_nil stale_rule["for"]
    end

    promtool = "promtool"
    skip "promtool is required to evaluate Prometheus alert rules" unless system(promtool, "--version", out: File::NULL, err: File::NULL)

    first_http = http_targets.first.fetch("name")
    first_playwright = playwright_targets.first.fetch("name")
    missing_rules = http_missing_rules.select { |entry| entry["expr"].include?(%Q(name=#{first_http.to_json}})) }
      .concat(playwright_missing_rules.select { |entry| entry["expr"].include?(%Q(name=#{first_playwright.to_json}})) })
      .map { |entry| entry.slice("alert", "expr", "for", "labels") }
    http_site_missing_rule = rules.find { |entry| entry["alert"] == "UprightHTTPSiteMissing" }
    assert http_site_missing_rule, "UprightHTTPSiteMissing rule was not rendered"
    assert_includes http_site_missing_rule["expr"], "< 1200"
    site_missing_rules = [ http_site_missing_rule.slice("alert", "expr", "for", "labels") ]
    recording_rules = [ down_fraction, uptime_daily ].map do |entry|
      entry.slice("record", "expr")
    end

    Dir.mktmpdir("upright-prometheus-rules") do |directory|
      rules_path = File.join(directory, "rules.yml")
      tests_path = File.join(directory, "tests.yml")

      File.write(
        rules_path,
        YAML.dump(
          "groups" => [
            { "name" => "missing_probe_tests", "rules" => missing_rules },
            { "name" => "site_missing_tests", "rules" => site_missing_rules },
            { "name" => "recording_tests", "interval" => "30s", "rules" => recording_rules }
          ]
        )
      )
      test_cases = promtool_test_cases(rules_path, http_targets.first, playwright_targets.first)
      test_cases["tests"] << production_recording_rule_test
      test_cases["tests"] << http_site_missing_test
      File.write(tests_path, YAML.dump(test_cases))

      output, status = Open3.capture2e(promtool, "test", "rules", tests_path)
      assert status.success?, output
    end
  end

  private
    def production_recording_rule_test
      labels = 'name="EUDI Wallet", type="http", probe_target="https://wallet.eudi-adorsys.com", alert_severity="high", probe_service="eudi_wallet", environment="production"'

      {
        "name" => "recording rules preserve environment for production status queries",
        "interval" => "30s",
        "input_series" => [
          {
            "series" => "upright_probe_up{#{labels}}",
            "values" => "0+0x5"
          }
        ],
        "promql_expr_test" => [
          {
            "expr" => 'upright:probe_down_fraction{environment="production", probe_service="eudi_wallet"}',
            "eval_time" => "1m",
            "exp_samples" => [
              {
                "labels" => "upright:probe_down_fraction{#{labels}}",
                "value" => 1
              }
            ]
          },
          {
            "expr" => 'upright:probe_uptime_daily{environment="production", probe_service="eudi_wallet"}',
            "eval_time" => "1m",
            "exp_samples" => [
              {
                "labels" => "upright:probe_uptime_daily{#{labels}}",
                "value" => 0
              }
            ]
          }
        ]
      }
    end

    # Heartbeat stuck at unix 0: site stays "seen in last hour" via max_over_time,
    # but drops from the fresh set once age is no longer < 1200s (20m).
    def http_site_missing_test
      site_labels = 'type="http", site_code="fra", site_city="Frankfurt", name="EUDI Wallet"'
      fired_alert = {
        "exp_labels" => {
          "alertname" => "UprightHTTPSiteMissing",
          "site_code" => "fra",
          "site_city" => "Frankfurt",
          "severity" => "warning",
          "group" => "upright"
        }
      }

      {
        "name" => "HTTP site missing fires at the 20m heartbeat threshold",
        "interval" => "30s",
        "input_series" => [
          {
            "series" => "upright_probe_last_run_timestamp_seconds{#{site_labels}}",
            "values" => "0+0x120"
          }
        ],
        "alert_rule_test" => [
          { "eval_time" => "19m30s", "alertname" => "UprightHTTPSiteMissing", "exp_alerts" => [] },
          { "eval_time" => "20m", "alertname" => "UprightHTTPSiteMissing", "exp_alerts" => [ fired_alert ] }
        ]
      }
    end

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
            { "eval_time" => "19m30s", "alertname" => alertname, "exp_alerts" => [] },
            { "eval_time" => "20m", "alertname" => alertname, "exp_alerts" => [ fired_alert ] }
          ]
        else
          [
            { "eval_time" => "29m30s", "alertname" => alertname, "exp_alerts" => [] },
            { "eval_time" => "30m", "alertname" => alertname, "exp_alerts" => [ fired_alert ] }
          ]
        end
      end
      expected_alerts = expected_alerts.flatten

      # Heartbeat stuck at unix 0 while upright_probe_up remains present. The
      # stopped rule has no `for`, so HTTP fires at 20m and Playwright at 30m.
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
            { "eval_time" => "19m30s", "alertname" => alertname, "exp_alerts" => [] },
            { "eval_time" => "20m", "alertname" => alertname, "exp_alerts" => [ fired_alert ] }
          ]
        else
          [
            { "eval_time" => "29m30s", "alertname" => alertname, "exp_alerts" => [] },
            { "eval_time" => "30m", "alertname" => alertname, "exp_alerts" => [ fired_alert ] }
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
            "name" => "reported probes that stop are detected via last-run heartbeat expiry",
            "interval" => "30s",
            "input_series" => alert_names.map do |type, (_alertname, target_name)|
              other_target = type == "http" ? "nginx proxy" : "verifier_pos_new_order"
              [
                {
                  "series" => "upright_probe_last_run_timestamp_seconds{type=\"#{type}\", name=#{target_name.to_json}}",
                  "values" => "0+0x120"
                },
                {
                  "series" => "upright_probe_up{type=\"#{type}\", name=#{target_name.to_json}}",
                  "values" => "1+0x120"
                },
                {
                  "series" => "upright_probe_last_run_timestamp_seconds{type=\"#{type}\", name=#{other_target.to_json}}",
                  "values" => "0+30x120"
                },
                {
                  "series" => "upright_probe_up{type=\"#{type}\", name=#{other_target.to_json}}",
                  "values" => "1+0x120"
                }
              ]
            end.flatten,
            "alert_rule_test" => expected_stopped_alerts
          }
        ]
      }
    end
end
