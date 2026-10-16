defmodule YscWeb.Sms.MerchOrderUpdate do
  @moduledoc """
  SMS for a merch order update (delivered, returned, failed, canceled).
  Wording lives in `Ysc.Merch.UpdateCopy`.
  """
  alias Ysc.Merch.UpdateCopy
  alias YscWeb.Sms.Template

  # Keys required in priv/dev/notification_preview_samples.exs (mix lint_notification_samples).
  @preview_keys [:first_name, :reference_id, :kind]

  def preview_keys, do: @preview_keys

  def get_template_name, do: "merch_order_update"

  def render(variables) do
    first_name = Template.optional_first_name(variables)
    reference_id = Map.get(variables, :reference_id, "")
    kind = variables |> Map.get(:kind) |> to_kind()

    kind
    |> UpdateCopy.sms(reference_id)
    |> Template.greeting(first_name)
    |> Template.format()
  end

  def prepare_sms_data(kind, order, first_name \\ nil) do
    %{
      first_name: first_name,
      reference_id: order.reference_id,
      kind: to_string(kind)
    }
  end

  defp to_kind(kind) when is_atom(kind) and not is_nil(kind), do: kind

  defp to_kind(kind) when is_binary(kind) do
    Enum.find(UpdateCopy.kinds(), :delivered, &(Atom.to_string(&1) == kind))
  end

  defp to_kind(_), do: :delivered
end
