defmodule Ysc.Media.TestS3Uploader do
  @moduledoc false

  alias Ysc.S3Config

  @doc false
  def upload(_path, key, _opts) when is_binary(key) do
    key = String.trim_leading(key, "/")
    location = S3Config.object_url(key)

    %{
      body: %{
        key: key,
        location: location
      }
    }
  end
end
