defmodule Ysc.Html.Links do
  @moduledoc """
  Helpers for rewriting links in sanitized HTML fragments.
  """

  require Ysc.Logging

  @doc """
  Adds `target="_blank"` and `rel="noopener noreferrer"` to every `<a href>` tag.

  Returns the original string unchanged when `html` is nil or empty.
  On parse failure, logs a warning and returns the original HTML.
  """
  @spec open_in_new_tab(String.t() | nil) :: String.t()
  def open_in_new_tab(nil), do: ""
  def open_in_new_tab(""), do: ""

  def open_in_new_tab(html) when is_binary(html) do
    case Floki.parse_fragment(html) do
      {:ok, document} ->
        document
        |> Floki.traverse_and_update(&add_blank_target/1)
        |> Floki.raw_html()

      {:error, reason} ->
        Ysc.Logging.warning(
          "Failed to parse HTML for open-in-new-tab link rewrite",
          reason: inspect(reason)
        )

        html
    end
  end

  defp add_blank_target({"a", attrs, children} = node) do
    if has_href?(attrs) do
      {"a",
       put_attr(
         put_attr(attrs, "target", "_blank"),
         "rel",
         "noopener noreferrer"
       ), children}
    else
      node
    end
  end

  defp add_blank_target(node), do: node

  defp has_href?(attrs) do
    Enum.any?(attrs, fn
      {"href", value} when is_binary(value) and value != "" -> true
      _ -> false
    end)
  end

  defp put_attr(attrs, name, value) do
    attrs
    |> Enum.reject(fn {key, _} -> key == name end)
    |> Kernel.++([{name, value}])
  end
end
