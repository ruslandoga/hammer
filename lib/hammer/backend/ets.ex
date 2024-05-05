defmodule Hammer.Backend.ETS do
  @moduledoc "An ETS backend for Hammer"

  use GenServer
  @behaviour Hammer.Backend

  @doc """
  Starts the process that creates and cleans the ETS table.

  Accepts the following options:

    - `GenServer.option()`
    - `:table` for the ETS table name, defaults to `#{__MODULE__}`
    - `:clean_period` for how often to perform garbage collection

  """
  @spec start_link([GenServer.option() | {:table, atom} | {:clean_period, pos_integer}]) ::
          GenServer.on_start()
  def start_link(opts) do
    {gen_opts, opts} =
      Keyword.split(opts, [:debug, :name, :timeout, :spawn_opt, :hibernate_after])

    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @impl Hammer.Backend
  def count_hit(key, now, increment, opts) do
    table = Keyword.get(opts, :table, __MODULE__)

    [count | _] =
      :ets.update_counter(
        table,
        key,
        [
          # Increment count field
          {2, increment},
          # Set updated_at to now
          {4, 1, 0, now}
        ],
        {key, increment, now, now}
      )

    count
  end

  @impl Hammer.Backend
  def get_bucket(key, opts) do
    table = opts[:ets_table] || @ets_table_name

    case :ets.lookup(table, key) do
      [] -> nil
      [bucket] -> bucket
    end
  end

  @impl Hammer.Backend
  def delete_buckets(id, opts) do
    table = opts[:ets_table] || @ets_table_name
    ms = [{{{:"$1", :"$2"}, :_, :_, :_}, [{:==, :"$2", {:const, id}}], [true]}]
    :ets.select_delete(table, ms)
  end

  @impl GenServer
  def init(opts) do
    cleanup_interval_ms = Keyword.fetch!(opts, :cleanup_interval_ms)
    expiry_ms = Keyword.fetch!(opts, :expiry_ms)
    table = Keyword.get(opts, :table, __MODULE__)

    ^table =
      :ets.new(@ets_table_name, [
        :named_table,
        :set,
        :public,
        {:read_concurrency, true},
        {:write_concurrency, true},
        {:decentralized_counters, true}
      ])

    schedule(cleanup_interval_ms)

    {:ok,
     %{
       table: table,
       cleanup_interval_ms: cleanup_interval_ms,
       expiry_ms: expiry_ms
     }}
  end

  @impl GenServer
  def handle_info(:clean, state) do
    %{table: table, expiry_ms: expiry_ms} = state
    clean(table)
    schedule(cleanup_interval_ms)
    {:noreply, state}
  end

  defp schedule(cleanup_interval_ms) do
    Process.send_after(self(), :clean, cleanup_interval_ms)
  end

  defp clean(table) do
    ms = [{{:_, :_, :_, :"$1"}, [{:<, :"$1", {:const, expire_before}}], [true]}]
    :ets.select_delete(table, ms)
  end
end
