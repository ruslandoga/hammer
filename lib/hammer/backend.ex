defmodule Hammer.Backend do
  @moduledoc """
  The backend Behaviour module.
  """

  @type bucket_key :: {bucket :: integer, id :: String.t()}
  @type bucket_info ::
          {key :: bucket_key, count :: integer, created :: integer, updated :: integer}

  @callback count_hit(key :: bucket_key, now :: integer, increment :: integer, opts :: keyword) ::
              {:ok, count :: integer} | {:error, reason :: any}

  @callback get_bucket(key :: bucket_key, opts :: keyword) ::
              {:ok, info :: bucket_info | nil} | {:error, reason :: any}

  @callback delete_buckets(id :: String.t(), opts :: keyword) ::
              {:ok, count_deleted :: integer} | {:error, reason :: any}
end
