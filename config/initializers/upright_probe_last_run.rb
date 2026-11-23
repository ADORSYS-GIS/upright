module UprightProbeLastRun
  private
    def increment_metrics
      super

      labels = {
        type: probe_type,
        name: probe_name,
        probe_target: probe_target,
        probe_service: probe_service,
        alert_severity: probe_alert_severity || :high
      }

      Yabeda.upright_probe_last_run_timestamp_seconds.set(labels, created_at.to_f)
    end
end

# ProbeResult lives in the upright engine and is not loaded while this
# initializer file is evaluated, so prepend after the app is prepared.
Rails.application.config.to_prepare do
  unless Upright::ProbeResult.ancestors.include?(UprightProbeLastRun)
    Upright::ProbeResult.prepend(UprightProbeLastRun)
  end
end
