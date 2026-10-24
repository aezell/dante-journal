defmodule DanteJournal.MixProject do
  use Mix.Project

  def project do
    [
      app: :dante_journal,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [dante_journal: [include_executables_for: [:unix]]]
    ]
  end

  def cli, do: [preferred_envs: ["dante.app": :prod]]

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [
      # Published packages ship a precompiled Apple silicon NIF, so no Rust
      # toolchain is needed. `gpui_native` brings `gpui` and `gpui_components`.
      {:gpui_native, "== 0.2.0"}
    ]
  end
end
