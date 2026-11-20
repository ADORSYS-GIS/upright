require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Upright
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    # Register before upright.yabeda calls Yabeda.configure!. DirectFileStore
    # keeps upright_probe_up after a probe stops, so missing alerts age this
    # heartbeat instead of relying on absent(upright_probe_up).
    initializer "upright.probe_last_run_metric", before: "upright.yabeda" do
      Yabeda.configure do
        group :upright do
          gauge :probe_last_run_timestamp_seconds,
            comment: "Unix time when this probe last recorded a result",
            aggregation: :max,
            tags: %i[type name probe_target probe_service alert_severity]
        end
      end
    end
  end
end
