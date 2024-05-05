defmodule Hammer.Backend do
  @moduledoc """
  The backend Behaviour module.
  """

  @type opts :: keyword
  @type bucket_key :: {Hammer.id(), bucket :: pos_integer}
  @type bucket_info :: {
          bucket_key,
          Hammer.count(),
          created :: pos_integer | nil,
          updated :: pos_integer | nil
        }

  @callback count_hit(bucket_key, now :: pos_integer, Hammer.increment(), opts) :: Hammer.count()
  @callback get_bucket(bucket_key, opts) :: bucket_info | nil
  @callback delete_buckets(Hammer.id(), opts) :: count_deleted :: non_neg_integer
end
