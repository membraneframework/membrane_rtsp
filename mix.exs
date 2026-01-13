defmodule Membrane.RTSP.MixProject do
  use Mix.Project

  @version "0.12.0"
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
      homepage_url: "https://membrane.stream",
      docs: docs()
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"],
      formatters: ["html"],
      source_ref: "v#{@version}",
      groups_for_modules: [
        "RTSP Server": [~r/Membrane.RTSP.Server.*/]
      ],
      nest_modules_by_prefix: [
        Membrane.RTSP
      ],
      before_closing_body_tag: &inject_mermaid/1,
      extras: [
        "README.md",
        "livebook/basic_server.livemd",
        "LICENSE"
      ]
    ]
  end

  defp inject_mermaid(:html) do
    """
    <script src="https://cdn.jsdelivr.net/npm/mermaid@10.2.3/dist/mermaid.min.js"></script>
    <script>
      document.addEventListener("DOMContentLoaded", function () {
        mermaid.initialize({
          startOnLoad: false,
          theme: document.body.className.includes("dark") ? "dark" : "default"
      });
      let id = 0;
      for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
        const preEl = codeEl.parentElement;
        const graphDefinition = codeEl.textContent;
        const graphEl = document.createElement("div");
        const graphId = "mermaid-graph-" + id++;
        mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
          graphEl.innerHTML = svg;
          bindFunctions?.(graphEl);
          preEl.insertAdjacentElement("afterend", graphEl);
          preEl.remove();
        });
      }
      });
    </script>
    """
  end

  defp inject_mermaid(:epub), do: ""

  defp package do
    [
      maintainers: ["Membrane Team"],
      licenses: ["Apache 2.0"],
      links: %{
        "GitHub" => @github_url,
        "Membrane Framework Homepage" => "https://membrane.stream"
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
      {:bunch, "~> 1.6"},
      {:ex_sdp, "~> 0.17.0 or ~> 1.0"},
      {:nimble_parsec, "~> 1.4.0", runtime: false},
      {:dialyxir, "~> 1.1", only: [:dev], runtime: false},
      {:mockery, "~> 2.3", runtime: false},
      {:ex_doc, "~> 0.25", only: :dev, runtime: false},
      {:mix_test_watch, "~> 1.0", only: :dev, runtime: false},
      {:credo, "~> 1.6", only: :dev, runtime: false}
    ]
  end
end
