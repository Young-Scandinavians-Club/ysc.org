defmodule Ysc.Test.SesThrottlingAdapter do
  @moduledoc false
  use Swoosh.Adapter

  @impl Swoosh.Adapter
  def deliver(_email, _config) do
    {:error, %{code: "Throttling", message: "Maximum sending rate exceeded"}}
  end

  @impl Swoosh.Adapter
  def deliver_many(_emails, _config) do
    {:error, %{code: "Throttling", message: "Maximum sending rate exceeded"}}
  end
end
