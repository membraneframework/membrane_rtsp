defmodule Membrane.RTSP.MixProject do
  use Mix.Project

  @version "0.2.0"

  def project do
    [
      app: :membrane_rtsp,
      version: @version,
      elixir: "~> 1.10",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs()
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"],
      source_ref: "v#{@version}",
      nest_modules_by_prefix: [
        Membrane.RTSP
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  def application do
    [
      extra_applications: [:logger],
      mod: {Membrane.RTSP.Application, []}
    ]
  end

  defp deps do
    [
      {:bunch, "~> 1.0"},
      {:membrane_protocol_sdp, "~> 0.1"},
      {:dialyxir, "~> 1.0.0-rc.4", only: [:dev], runtime: false},
      {:mockery, "~> 2.3.0", runtime: false},
      {:ex_doc, "~> 0.19", only: :dev, runtime: false},
      {:mix_test_watch, "~> 0.8", only: :dev, runtime: false},
      {:credo, "~> 1.0.4", only: [:dev, :test], runtime: false}
    ]
  end
end
