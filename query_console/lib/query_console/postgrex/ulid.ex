defmodule QueryConsole.Postgrex.ULID do
  @moduledoc false

  # YSC stores ULIDs in Postgres `uuid` columns. Decode them as Crockford
  # Base32 strings so raw AnalyticsRepo queries render like Ecto schemas.
  import Postgrex.BinaryUtils, warn: false
  use Postgrex.BinaryExtension, send: "uuid_send"

  def encode(_) do
    quote location: :keep, generated: true do
      binary when is_binary(binary) and byte_size(binary) == 16 ->
        [<<16::int32()>> | binary]

      encoded when is_binary(encoded) and byte_size(encoded) == 26 ->
        case Ecto.ULID.dump(encoded) do
          {:ok, binary} -> [<<16::int32()>> | binary]
          :error -> raise ArgumentError, "invalid ULID encoding: #{inspect(encoded)}"
        end

      uuid when is_binary(uuid) and byte_size(uuid) == 36 ->
        case Ecto.UUID.dump(uuid) do
          {:ok, binary} -> [<<16::int32()>> | binary]
          :error -> raise ArgumentError, "invalid UUID encoding: #{inspect(uuid)}"
        end

      other ->
        raise DBConnection.EncodeError,
              Postgrex.Utils.encode_msg(
                other,
                "a ULID string, UUID string, or 16-byte binary"
              )
    end
  end

  def decode(_) do
    quote location: :keep do
      <<16::int32(), binary::binary-16>> ->
        case Ecto.ULID.load(binary) do
          {:ok, encoded} -> encoded
          :error -> raise ArgumentError, "invalid ULID binary"
        end
    end
  end
end
