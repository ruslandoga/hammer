defmodule Hammer do
  @moduledoc """
  Documentation for Hammer module.

  This is the main API for the Hammer rate-limiter. This module assumes a
  backend pool has been started, most likely by the Hammer application.
  """

  alias Hammer.Utils

  backends =
    case Application.compile_env!(:hammer, :backend) do
      {_mod, _opts} = backend -> [single: backend]
      [_ | _] = backends -> backends
    end

  {default_backend, _config} =
    List.first(backends) ||
      raise ArgumentError,
            "expected at least one backend provided in :backends, got: #{inspect(backends)}"

  @type id :: String.t()
  @type scale_ms :: pos_integer
  @type limit :: pos_integer
  @type count :: pos_integer
  @type increment :: non_neg_integer
  @type backend :: atom

  @type bucket_info :: {
          count,
          count_remaining :: non_neg_integer,
          ms_to_next_bucket :: pos_integer,
          created_at :: pos_integer | nil,
          updated_at :: pos_integer | nil
        }

  @doc """
  Check if the action you wish to perform is within the bounds of the rate-limit.

  Args:
  - `id`: String name of the bucket. Usually the bucket name is comprised of
  some fixed prefix, with some dynamic string appended, such as an IP address or
  user id
  - `scale`: Integer indicating size of bucket in milliseconds
  - `limit`: Integer maximum count of actions within the bucket

  Returns either `{:allow,  count}`, `{:deny,   limit}` or `{:error,  reason}`

  Example:

      user_id = 42076
      case check_rate("file_upload:\#{user_id}", _scale = :timer.seconds(60), _limit = 5) do
        {:allow, _count} ->
          # do the file upload
        {:deny, _limit} ->
          # render an error page or something
      end

  """
  @spec check_rate(id, scale_ms, limit) :: {:allow, count} | {:deny, limit} | {:error, term}
  def check_rate(id, scale, limit) do
    check_rate_inc(id, scale, limit, 1)
  end

  @doc "Same as `check_rate/3`, but allows specifying a backend"
  @spec check_rate(backend, id, scale_ms, limit) ::
          {:allow, count} | {:deny, limit} | {:error, reason}
  def check_rate(backend, id, scale_ms, limit) do
    check_rate_inc(backend, id, scale_ms, limit, 1)
  end

  @doc """
  Same as check_rate/3, but allows the increment number to be specified.
  This is useful for limiting apis which have some idea of 'cost', where the cost
  of each hit can be specified.
  """
  @spec check_rate_inc(id, scale_ms, limit, increment) ::
          {:allow, count} | {:deny, limit} | {:error, term}
  def check_rate_inc(id, scale_ms, limit, increment) do
    check_rate_inc(unquote(default_backend), id, scale_ms, limit, increment)
  end

  @doc "Same as check_rate_inc/4, but allows specifying a backend"
  @spec check_rate_inc(backend, id, scale_ms, limit, increment) ::
          {:allow, count} | {:deny, limit} | {:error, term}
  def check_rate_inc(backend, id, scale_ms, limit, increment)

  for {backend, {mod, opts}} <- backends do
    def check_rate_inc(unquote(backend), id, scale_ms, limit, increment) do
      {stamp, key} = stamp_key(id, scale_ms)

      try do
        count = unquote(mod).count_hit(key, stamp, increment, unquote(opts))
        if count > limit, do: {:deny, limit}, else: {:allow, count}
      rescue
        e -> {:error, e}
      end
    end
  end

  def check_rate_inc(backend, _id, _scale_ms, _limit, _increment) do
    unknown_backend(backend)
  end

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
  @spec inspect_bucket(id, scale_ms, limit) :: {:ok, bucket_info} | {:error, term}
  def inspect_bucket(id, scale_ms, limit) do
    inspect_bucket(unquote(default_backend), id, scale_ms, limit)
  end

  @doc """
  Same as inspect_bucket/3, but allows specifying a backend
  """
  @spec inspect_bucket(backend, id, scale_ms, limit) :: {:ok, bucket_info} | {:error, term}
  def inspect_bucket(backend, id, scale_ms, limit)

  for {backend, {mod, opts}} <- backends do
    def inspect_bucket(unquote(backend), id, scale_ms, limit) do
      {stamp, key} = stamp_key(id, scale_ms)
      ms_to_next_bucket = elem(key, 0) * scale_ms + scale_ms - stamp

      result =
        try do
          {:ok, unquote(mod).get_bucket(key, unquote(opts))}
        rescue
          e -> {:error, e}
        end

      with {:ok, bucket} <- result do
        case bucket do
          {_, count, created_at, updated_at} ->
            count_remaining = if limit > count, do: limit - count, else: 0
            {:ok, {count, count_remaining, ms_to_next_bucket, created_at, updated_at}}

          nil ->
            {:ok, {0, limit, ms_to_next_bucket, nil, nil}}
        end
      end
    end
  end

  def inspect_bucket(backend, _id, _scale_ms, _limit) do
    unknown_backend(backend)
  end

  @doc """
  Delete all buckets belonging to the provided id, including the current one.
  Effectively resets the rate-limit for the id.

  Arguments:

  - `id`: String name of the bucket

  Returns either `{:ok, count}` where count is the number of buckets deleted,
  or `{:error, reason}`.

  Example:

      user_id = 2406
      {:ok, _count} = delete_buckets("file_uploads:\#{user_id}")

  """
  @spec delete_buckets(id) :: {:ok, count_deleted :: non_neg_integer} | {:error, term}
  def delete_buckets(id) do
    delete_buckets(unquote(default_backend), id)
  end

  @doc """
  Same as delete_buckets/1, but allows specifying a backend
  """
  @spec delete_buckets(backend, id) :: {:ok, count_deleted :: non_neg_integer} | {:error, term}
  def delete_buckets(backend, id)

  for {backend, {mod, opts}} <- backends do
    def delete_buckets(unquote(backend), id) do
      try do
        {:ok, unquote(mod).delete_buckets(id, unquote(opts))}
      rescue
        e -> {:error, e}
      end
    end
  end

  def delete_buckets(backend, _id) do
    unknown_backend(backend)
  end

  @compile inline: [unknown_backend: 1]
  defp unknown_backend(backend) do
    raise ArgumentError, "unknown backend #{inspect(backend)}"
  end

  @compile inline: [timestamp: 0]
  defp timestamp, do: System.system_time(:millisecond)

  @compile inline: [full_key: 2]
  defp full_key(key, scale) do
    bucket = div(now(), scale)
    {key, bucket}
  end
end
