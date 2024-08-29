defmodule SwaySock.MixProject do
  use Mix.Project

  def project do
    [
      app: :sway_sock,
      description: "Library for controlling SwayWM via IPC",
      source_url: "https://github.com/eze-works/sway_sock",
      version: "0.2.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: []
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"Source" => "https://github.com/eze-works/sway_sock"}
    ]
  end
end
