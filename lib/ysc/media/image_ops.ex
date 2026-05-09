defmodule Ysc.Media.ImageOps do
  @moduledoc """
  Shared image operation helpers.
  """

  @spec autorotate(Vix.Vips.Image.t()) ::
          {:ok, Vix.Vips.Image.t()} | {:error, term()}
  def autorotate(image) do
    case Image.autorotate(image) do
      {:ok, {%Vix.Vips.Image{} = oriented, _orientation}} -> {:ok, oriented}
      {:error, _} = error -> error
    end
  end
end
