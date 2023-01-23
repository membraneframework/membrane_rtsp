defmodule Membrane.RTSP.MixProject do
  use Mix.Project

  @version "0.3.2"
  @github_url "https://github.com/membraneframework/membrane_rtsp"

  def project do
    [
      app: :membrane_rtsp,
      version: @version,
      elixir: "~> 1.12",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),

      # hex
      description: "RTSP client for Elixir",
      package: package(),

      # docs
      name: "Membrane RTSP",
      source_url: @github_url,
      homepage_url: "https://membraneframework.org",
      docs: docs()
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"],
      formatters: ["html"],
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

  defp dialyzer() do
    opts = [
      flags: [:error_handling]
    ]

    if System.get_env("CI") == "true" do
      # Store PLTs in cacheable directory for CI
      [plt_local_path: "priv/plts", plt_core_path: "priv/plts"] ++ opts
    else
      opts
    end
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:bunch, "~> 1.3"},
      {:ex_sdp, "~> 0.10.1"},
      {:dialyxir, "~> 1.1", only: [:dev], runtime: false},
      {:mockery, "~> 2.3", runtime: false},
      {:ex_doc, "~> 0.25", only: :dev, runtime: false},
      {:mix_test_watch, "~> 0.8", only: :dev, runtime: false},
      {:credo, "~> 1.6", only: :dev, runtime: false}
    ]
  end
end
