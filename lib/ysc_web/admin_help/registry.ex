defmodule YscWeb.AdminHelp.Registry do
  @moduledoc """
  Registry of all admin help guides. Slugs are allowlisted for routing and LLM grounding.
  """

  alias YscWeb.AdminHelp.Guide
  alias YscWeb.AdminHelp.Guides

  @guides [
    Guides.GettingStarted,
    Guides.RolesAndPermissions,
    Guides.PublishPost,
    Guides.PinAndDrafts,
    Guides.ComposeNewsletter,
    Guides.SendNewsletter,
    Guides.ManageSubscribers,
    Guides.CreateEvent,
    Guides.EventTickets,
    Guides.EventPublish,
    Guides.EventUpdates,
    Guides.UploadMedia,
    Guides.EventCheckIn,
    Guides.QrScanner
  ]

  @doc "All guide modules in display order."
  def all, do: @guides

  @doc "Find a guide module by slug string (e.g. `\"posts/publish\"`)."
  def fetch(slug) when is_binary(slug) do
    case Enum.find(@guides, &(module_slug(&1) == slug)) do
      nil -> :error
      mod -> {:ok, mod}
    end
  end

  def fetch!(slug) do
    case fetch(slug) do
      {:ok, mod} ->
        mod

      :error ->
        raise ArgumentError, "unknown admin help guide slug: #{inspect(slug)}"
    end
  end

  def valid_slug?(slug), do: match?({:ok, _}, fetch(slug))

  def module_slug(mod), do: mod.slug()

  def accessible?(slug, role) when is_binary(slug) and is_atom(role) do
    case fetch(slug) do
      {:ok, mod} -> accessible?(mod, role)
      :error -> false
    end
  end

  def accessible?(guide_mod, role) when is_atom(guide_mod) and is_atom(role) do
    role in guide_mod.audience()
  end

  @doc """
  Like `fetch/1`, but returns `{:error, :forbidden}` when the guide exists
  but is not in the user's role audience.
  """
  def fetch_for_role(slug, role)
      when is_binary(slug) and role in [:admin, :volunteer] do
    case fetch(slug) do
      {:ok, mod} = ok ->
        if accessible?(mod, role), do: ok, else: {:error, :forbidden}

      :error ->
        :error
    end
  end

  def guides_for_role(role) when role in [:admin, :volunteer] do
    Enum.filter(@guides, &accessible?(&1, role))
  end

  def guides_for_role(_role), do: []

  def guides_by_category(role) when role in [:admin, :volunteer] do
    role
    |> guides_for_role()
    |> Enum.group_by(& &1.category())
    |> Enum.sort_by(fn {cat, _} ->
      Guide.categories()
      |> Enum.find_index(&(&1 == cat))
      |> Kernel.||(99)
    end)
  end

  def catalog_for_llm(role) when role in [:admin, :volunteer] do
    guides_for_role(role)
    |> Enum.map(fn mod ->
      %{
        slug: mod.slug(),
        title: mod.title(),
        summary: mod.summary(),
        audience: mod.audience()
      }
    end)
  end

  def guide_context_for_llm(mod) do
    steps =
      mod.steps()
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {step, idx} ->
        "#{idx}. #{step.title}\n#{step.body}"
      end)

    faq =
      Enum.map_join(mod.faq(), "\n\n", fn {q, a} ->
        "Q: #{q}\nA: #{a}"
      end)

    troubleshooting =
      Enum.map_join(mod.troubleshooting(), "\n", fn item ->
        "- #{item}"
      end)

    """
    Guide: #{mod.title()}
    Summary: #{mod.summary()}

    Steps:
    #{steps}

    FAQ:
    #{if faq == "", do: "(none)", else: faq}

    Troubleshooting:
    #{if troubleshooting == "", do: "(none)", else: troubleshooting}
    """
  end
end
