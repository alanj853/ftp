defmodule Ftp.Mixfile do
  use Mix.Project

  def project do
    [app: :ftp,
     version: "0.1.0",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [
      mod: applications(Mix.env),
      extra_applications: [:logger, :ranch]
    ]
  end

  def applications(:test) do
    { Ftp, [] }
  end

  def applications(_) do
    []
  end

  # Dependencies can be Hex packages:
  #
  #   {:my_dep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:my_dep, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:ranch, "~> 1.3.2"},
      {:fsm, "~> 0.3.0"},
      {:propcheck, "~> 1.0", only: :test},
      {:mix_test_watch, "~> 0.5", only: :dev, runtime: false}
    ]
  end
end
