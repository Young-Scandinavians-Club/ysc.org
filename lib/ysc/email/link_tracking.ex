defmodule Ysc.Email.LinkTracking do
  @moduledoc """
  Controls Amazon SES click tracking per email template.

  Non-newsletter emails get `ses:no-track` on every `<a>` tag before delivery so
  SES does not rewrite links to `awstrack.me`. Newsletter templates (category
  `:newsletter` in `Ysc.Accounts.EmailCategories`) keep click tracking enabled.

  To opt out a specific link inside a tracked newsletter, add `ses:no-track`
  manually in the template — this module skips anchors that already have it.
  """

  require Ysc.Logging

  alias Ysc.Accounts.EmailCategories

  @ses_no_track_attr "ses:no-track"

  @doc """
  Returns whether SES should rewrite links for click tracking.

  Enabled only for templates in the `:newsletter` category.
  """
  @spec enabled_for_template?(String.t() | atom() | nil) :: boolean()
  def enabled_for_template?(template_name) when is_binary(template_name) do
    EmailCategories.link_tracking_enabled?(template_name)
  end

  def enabled_for_template?(template_name) when is_atom(template_name) do
    template_name |> to_string() |> enabled_for_template?()
  end

  def enabled_for_template?(_), do: false

  @doc """
  Adds `ses:no-track` to every `<a>` tag in the HTML that lacks it.

  Returns the original string unchanged when `html` is nil or empty.
  On parse failure, logs a warning and applies a conservative regex fallback
  so transactional links are still protected from SES click rewriting.
  """
  @spec disable_tracking(String.t() | nil) :: String.t()
  def disable_tracking(nil), do: ""
  def disable_tracking(""), do: ""

  def disable_tracking(html) when is_binary(html) do
    case Floki.parse_fragment(html) do
      {:ok, document} ->
        document
        |> Floki.traverse_and_update(&add_no_track_to_anchor/1)
        |> Floki.raw_html()

      {:error, reason} ->
        Ysc.Logging.warning(
          "Failed to parse email HTML for SES link tracking disable, using regex fallback",
          reason: inspect(reason)
        )

        inject_no_track_regex(html)
    end
  end

  # Conservative fallback when Floki cannot parse the fragment. Matches opening
  # <a> tags that lack ses:no-track and injects the attribute before ">".
  @anchor_without_no_track ~r/<a\b(?![^>]*\bses:no-track\b)([^>]*?)>/i

  @doc false
  @spec inject_no_track_regex(String.t()) :: String.t()
  def inject_no_track_regex(html) when is_binary(html) do
    Regex.replace(@anchor_without_no_track, html, "<a\\1 ses:no-track>")
  end

  defp add_no_track_to_anchor({"a", attrs, children} = node) do
    if has_no_track_attr?(attrs) do
      node
    else
      {"a", attrs ++ [{@ses_no_track_attr, ""}], children}
    end
  end

  defp add_no_track_to_anchor(node), do: node

  defp has_no_track_attr?(attrs) do
    Enum.any?(attrs, fn
      {@ses_no_track_attr, _} -> true
      _ -> false
    end)
  end
end
