import Config

if config_env() == :test do
  config :hammer,
    backend:
      {Hammer.Backend.ETS,
       ets_table_name: :hammer_backend_ets_test_buckets,
       expiry_ms: :timer.hours(2),
       cleanup_interval_ms: :timer.minutes(2)}
end
