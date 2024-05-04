defmodule Hammer.Supervisor do
  @moduledoc """
  Top-level Supervisor for the Hammer application.

  Starts a set of poolboy pools based on provided configuration,
  which are latter called to by the `Hammer` module.
  See the Application module for configuration examples.
  """

  use Supervisor

  def start_link(config, opts) do
    Supervisor.start_link(__MODULE__, config, opts)
  end

  # Single backend
  def init(config) when is_tuple(config) do
    children = [config]
    Supervisor.init(children, strategy: :one_for_one)
  end

  # Multiple backends
  def init(config) when is_list(config) do
    children = Enum.map(config, fn {_k, c} -> c end)
    Supervisor.init(children, strategy: :one_for_one)
  end
end
