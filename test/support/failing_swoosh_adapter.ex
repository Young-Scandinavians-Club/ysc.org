defmodule Ysc.Test.FailingSwooshAdapter do
  @moduledoc false
  use Swoosh.Adapter

  @impl Swoosh.Adapter
  def deliver(_email, _config), do: {:error, :smtp_unavailable}

  @impl Swoosh.Adapter
  def deliver_many(_emails, _config), do: {:error, :smtp_unavailable}
end
