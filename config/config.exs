import Config

# Tests use GPUI's renderer-independent test display; no native library.
config :gpui_native, build_native: config_env() != :test
config :gpui_native, GPUI.Native, host: :gpui_component
config :logger, level: :info
