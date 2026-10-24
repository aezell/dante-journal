import Config

# Tests use GPUI's renderer-independent test display; no native library.
config :gpui_native, build_native: config_env() != :test
config :gpui_native, GPUI.Native, host: :gpui_component
config :logger, level: :info

# Tests must not see a Mandelbaum import on the developer's Mac.
if config_env() == :test do
  config :dante_journal, texts_dir: Path.expand("../_build/test/texts", __DIR__)
end
