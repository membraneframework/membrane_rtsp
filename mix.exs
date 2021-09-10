defmodule Membrane.RTSP.MixProject do
  use Mix.Project

  @version "0.2.1"
  @github_url "https://github.com/membraneframework/membrane_rtsp"

  def project do
    [
      app: :membrane_rtsp,
      version: @version,
      elixir: "~> 1.12",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      name: "Membrane RTSP",
      description: "RTSP client for Elixir",
      source_url: @github_url,
      package: package(),
      docs: docs(),
      deps: deps()
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

  defp package do
    [
      maintainers: ["Membrane Team"],
      licenses: ["Apache 2.0"],
      links: %{
        "GitHub" => @github_url,
        "Membrane Framework Homepage" => "https://membraneframework.org"
      }
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
      {:membrane_protocol_sdp, "~> 0.1.0"},
      {:dialyxir, "~> 1.0.0", only: [:dev], runtime: false},
      {:mockery, "~> 2.3.0", runtime: false},
      {:ex_doc, "~> 0.23", only: :dev, runtime: false},
      {:mix_test_watch, "~> 0.8", only: :dev, runtime: false},
      {:credo, "~> 1.5.6", only: [:dev, :test], runtime: false}
    ]
  end
end
