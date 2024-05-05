defmodule Hammer do
  @moduledoc """
  Documentation for Hammer module.

  This is the main API for the Hammer rate-limiter. This module assumes a
  backend pool has been started, most likely by the Hammer application.

      defmodule MyApp.RateLimit do
        use Hammer, backend: Hammer.Backend.ETS
      end

      MyApp.RateLimit.start_link(expiry_ms: :timer.minutes(10), cleanup_interval_ms: :timer.minutes(1))
      {:allow, 1] = MyApp.RateLimit.hit("some-key", _scale = :timer.seconds(60), _limit = 10)
      {:allow, 1} = MyApp.RateLimit.get("some-key", _scale = :timer.seconds(60), _limit = 10)
      MyApp.RateLimit.wait("some-key", _scale = :timer.seconds(60), _limit = 10)

      backend = Hammer.backend(Hammer.Backend.ETS, opts)
      Hammer.check_rate(backend, )

  """

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      backend = Keyword.fetch!(opts, :backend)

      unless is_atom(backend) do
        raise ArgumentError,
              "expected :backend to be a module name like Hammer.Backend.ETS, got: #{inspect(backend)}"
      end

      @behaviour Hammer
      @backend backend

      def __backend__ do
        @backend
      end

      def start_link(opts) do
        @backend.start_link(opts)
      end

      def child_spec(opts) do
        @backend.child_spec(opts)
      end

      def check_rate(id, scale_ms, limit) do
        @backend.check_rate_inc(id, scale_ms, limit, 1)
      end

      def check_rate_inc(id, scale_ms, limit, increment) do
        @backend.check_rate_inc(id, scale_ms, limit, increment)
      end

      def inspect_bucket(id, scale_ms, limit) do
        {stamp, key} = Hammer.Utils.stamp_key(id, scale_ms)
        ms_to_next_bucket = elem(key, 0) * scale_ms + scale_ms - stamp

        case @backend.get_bucket(key) do
          {:ok, nil} ->
            {:ok, {0, limit, ms_to_next_bucket, nil, nil}}

          {:ok, {_, count, created_at, updated_at}} ->
            count_remaining = if limit > count, do: limit - count, else: 0
            {:ok, {count, count_remaining, ms_to_next_bucket, created_at, updated_at}}

          {:error, reason} ->
            {:error, reason}
        end
      end

      def delete_buckets(id) do
        @backend.delete_buckets(id)
      end
    end
  end

  @doc """
  Check if the action you wish to perform is within the bounds of the rate-limit.

  Args:
  - `id`: String name of the bucket. Usually the bucket name is comprised of
  some fixed prefix, with some dynamic string appended, such as an IP address or
  user id.
  - `scale_ms`: Integer indicating size of bucket in milliseconds
  - `limit`: Integer maximum count of actions within the bucket

  Returns either `{:allow,  count}`, `{:deny,   limit}` or `{:error,  reason}`

  Example:

      user_id = 42076
      case MyHammer.check_rate("file_upload:\#{user_id}", 60_000, 5) do
        {:allow, _count} ->
          # do the file upload
        {:deny, _limit} ->
          # render an error page or something
      end

  """
  @callback check_rate(id :: String.t(), scale_ms :: integer, limit :: integer) ::
              {:allow, count :: integer}
              | {:deny, limit :: integer}
              | {:error, reason :: any}

  @doc """
  Same as check_rate/3, but allows the increment number to be specified.
  This is useful for limiting apis which have some idea of 'cost', where the cost
  of each hit can be specified.
  """
  @callback check_rate_inc(
              id :: String.t(),
              scale_ms :: integer,
              limit :: integer,
              increment :: integer
            ) ::
              {:allow, count :: integer}
              | {:deny, limit :: integer}
              | {:error, reason :: any}

  @doc """
  Inspect bucket to get count, count_remaining, ms_to_next_bucket, created_at,
  updated_at. This function is free of side-effects and should be called with
  the same arguments you would use for `check_rate` if you intended to increment
  and check the bucket counter.

  Arguments:

  - `id`: String name of the bucket. Usually the bucket name is comprised of
    some fixed prefix,with some dynamic string appended, such as an IP address
    or user id.
  - `scale_ms`: Integer indicating size of bucket in milliseconds
  - `limit`: Integer maximum count of actions within the bucket

  Returns either
  `{:ok, {count, count_remaining, ms_to_next_bucket, created_at, updated_at}`,
  or `{:error, reason}`.

  Example:

      inspect_bucket("file_upload:2042", 60_000, 5)
      {:ok, {1, 2499, 29381612, 1450281014468, 1450281014468}}

  """
  @callback inspect_bucket(id :: String.t(), scale_ms :: integer, limit :: integer) ::
              {:ok,
               {count :: integer, count_remaining :: integer, ms_to_next_bucket :: integer,
                created_at :: integer | nil, updated_at :: integer | nil}}
              | {:error, reason :: any}

  @doc """
  Delete all buckets belonging to the provided id, including the current one.
  Effectively resets the rate-limit for the id.

  Arguments:

  - `id`: String name of the bucket

  Returns either `{:ok, count}` where count is the number of buckets deleted,
  or `{:error, reason}`.

  Example:

      user_id = 2406
      {:ok, _count} = MyHammer.delete_buckets("file_uploads:\#{user_id}")

  """
  @callback delete_buckets(id :: String.t()) :: {:ok, count :: integer} | {:error, reason :: any}
end
