defmodule Membrane.Protocol.RTSP.MixProject do
  use Mix.Project

  def project do
    [
      app: :membrane_protocol_rtsp,
      version: "0.1.0",
      elixir: "~> 1.7",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Membrane.Protocol.RTSP.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bunch, "~> 0.3"},
      {:dialyxir, "~> 1.0.0-rc.4", only: [:dev], runtime: false},
      {:qex, "~> 0.5"},
      {:mockery, "~> 2.3.0", runtime: false},
      {:membrane_protocol_sdp,
       github: "membraneframework/membrane-protocol-sdp", branch: "basic-sdp"}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
    ]
  end
end
