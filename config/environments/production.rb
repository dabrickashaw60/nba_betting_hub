require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Ensure logger writes to a file in production
  config.log_level = :info
  config.log_tags = [:request_id]
  config.logger = ActiveSupport::Logger.new("log/production.log")
  config.logger.formatter = ::Logger::Formatter.new

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot.
  config.eager_load = true

  # Full error reports are disabled, and caching is turned on.
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  # Require a master key to decrypt credentials.
  config.require_master_key = true

  # Disable serving static files from `public/`, relying on NGINX/Apache.
  config.public_file_server.enabled = ENV['RAILS_SERVE_STATIC_FILES'].present?

  # Compress CSS using a preprocessor.
  # config.assets.css_compressor = :sass

  # Do not fallback to assets pipeline if a precompiled asset is missed.
  config.assets.compile = false
  config.assets.digest = true

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Force all access to the app over SSL and use secure cookies.
  config.force_ssl = true

  # Log to STDOUT (if running in a Docker container or similar environment).
  if ENV["RAILS_LOG_TO_STDOUT"].present?
    logger           = ActiveSupport::Logger.new(STDOUT)
    logger.formatter = ::Logger::Formatter.new
    config.logger    = ActiveSupport::TaggedLogging.new(logger)
  end

  # Prepend all log lines with the following tags.
  config.log_tags = [:request_id]

  # Use a real queuing backend for Active Job (and separate queues per environment).
  # config.active_job.queue_adapter = :sidekiq
  # config.active_job.queue_name_prefix = "nba_betting_hub_production"

  config.action_mailer.perform_caching = false

  # Enable locale fallbacks for I18n.
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Enable DNS rebinding protection and other `Host` header attacks.
  config.hosts << "nbaportal.com"

  # Add any additional trusted hostnames (e.g., subdomains) if needed:
  # config.hosts << /.*\.nbaportal\.com/

  # Ensure deprecation warnings are not logged in production.
  config.active_support.report_deprecations = false

  # Prevent sensitive information from being logged in production.
  config.filter_parameters += [:password, :password_confirmation]
end
