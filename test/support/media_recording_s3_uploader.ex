defmodule Ysc.Media.RecordingTestS3Uploader do
  @moduledoc false

  @key {__MODULE__, :uploads}

  def reset do
    :persistent_term.put(@key, [])
    :ok
  end

  def uploads do
    :persistent_term.get(@key, [])
  end

  def last_upload do
    case uploads() do
      [] -> nil
      recorded -> List.last(recorded)
    end
  end

  def upload(path, key, opts) when is_binary(key) do
    :persistent_term.put(@key, uploads() ++ [{path, key, opts}])
    Ysc.Media.TestS3Uploader.upload(path, key, opts)
  end
end
