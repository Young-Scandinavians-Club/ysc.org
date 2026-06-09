defmodule Ysc.AdminHelp.Assistant do
  @moduledoc """
  Grounded LLM assistant for admin help: guide finder and step clarifier.

  Answers are grounded in registered guide content plus a markdown knowledge
  base (`Ysc.AdminHelp.KnowledgeBase`) and allowlisted live-data snapshots
  (`Ysc.AdminHelp.LiveExamples` — real recent posts, events, and newsletters).
  The model sees only a lightweight index of both and may request up to three
  full sources on the fly, so detailed reference material never enters the
  context window unless it is relevant to the question. Disabled when
  OpenRouter is not configured.
  """

  alias Ysc.AdminHelp.KnowledgeBase
  alias Ysc.AdminHelp.LiveExamples
  alias Ysc.AdminHelpRateLimit
  alias Ysc.OpenRouter
  alias YscWeb.AdminHelp.Registry

  @max_docs 3

  @doc "Whether the assistant UI should be shown."
  def enabled? do
    api_key =
      Application.get_env(:ysc, :open_router, [])
      |> Keyword.get(:api_key)

    is_binary(api_key) and String.trim(api_key) != ""
  end

  @doc """
  Finds the best guide for a natural-language query, and — when a guide is
  found — pinpoints the step that answers it plus an exact quote from that
  step's body to highlight.

  Returns `{:ok, %{guide_slug: String.t() | nil, explanation: String.t(),
  confidence: atom(), step: pos_integer() | nil, highlight: String.t() | nil}}`
  or `{:error, reason}`.
  """
  def find_guide(query, role, user_id \\ nil) do
    with :ok <- check_rate(user_id),
         catalog <- Registry.catalog_for_llm(role),
         {:ok, parsed} <-
           chat_json(find_guide_messages(query, catalog, role), role),
         {:ok, result} <- validate_finder_result(parsed, role) do
      {:ok, locate_in_guide(result, query)}
    end
  end

  # Second pass: given the matched guide's full content, ask which step
  # answers the query and for a verbatim quote to highlight. Best-effort —
  # any failure falls back to plain guide-level navigation.
  defp locate_in_guide(%{guide_slug: nil} = result, _query) do
    Map.merge(result, %{step: nil, highlight: nil})
  end

  defp locate_in_guide(%{guide_slug: slug} = result, query) do
    location =
      with {:ok, guide_mod} <- Registry.fetch(slug),
           {:ok, parsed} <-
             chat_json(
               locate_messages(Registry.guide_context_for_llm(guide_mod), query)
             ) do
        validate_location(parsed, guide_mod)
      else
        _ -> %{step: nil, highlight: nil}
      end

    Map.merge(result, location)
  end

  @doc """
  Clarifies the current step of a guide.

  Returns `{:ok, %{answer: String.t(), suggested_step: integer() | nil}}` or `{:error, reason}`.
  """
  def clarify_step(guide_mod, step_index, question, role, user_id \\ nil) do
    with :ok <- check_rate(user_id),
         {:ok, parsed} <-
           chat_json(
             clarify_messages(
               Registry.guide_context_for_llm(guide_mod),
               step_index,
               question,
               role
             ),
             role
           ) do
      validate_clarifier_result(parsed, guide_mod)
    end
  end

  defp check_rate(nil), do: :ok

  defp check_rate(user_id) do
    case AdminHelpRateLimit.check(user_id) do
      :ok -> :ok
      :rate_limited -> {:error, :rate_limited}
    end
  end

  # Sends the messages and parses the JSON reply. If the model asks for
  # reference documents ({"read_docs": [...]}), loads them from the knowledge
  # base and runs one follow-up turn with the documents included.
  defp chat_json(messages, role \\ nil) do
    with {:ok, raw} <- chat(messages),
         {:ok, parsed} <- parse_json(raw) do
      case parsed do
        %{"read_docs" => slugs} when is_list(slugs) ->
          follow_up_with_docs(messages, raw, slugs, role)

        _ ->
          {:ok, parsed}
      end
    end
  end

  defp follow_up_with_docs(messages, assistant_raw, slugs, role) do
    docs = fetch_sources(slugs, role)

    docs_content =
      case docs do
        [] ->
          "None of the requested documents exist. Answer with what you already have."

        docs ->
          Enum.map_join(docs, "\n\n", fn {slug, content} ->
            "<document slug=\"#{slug}\">\n#{content}\n</document>"
          end)
      end

    follow_up =
      messages ++
        [
          %{role: "assistant", content: assistant_raw},
          %{
            role: "user",
            content: """
            Requested reference documents:

            #{docs_content}

            Now respond with ONLY the final JSON object in the format from the system message. Do not request more documents.
            """
          }
        ]

    with {:ok, raw} <- chat(follow_up) do
      parse_json(raw)
    end
  end

  # Resolves requested slugs against the markdown knowledge base and the
  # live-data snapshots ("live-" prefix), skipping unknown ones.
  defp fetch_sources(slugs, role) do
    slugs
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
    |> Enum.take(@max_docs)
    |> Enum.flat_map(fn slug ->
      case fetch_source(slug, role) do
        {:ok, content} -> [{slug, content}]
        :error -> []
      end
    end)
  end

  defp fetch_source("live-" <> _ = slug, _role), do: LiveExamples.fetch(slug)

  defp fetch_source(slug, role) do
    if is_nil(role) or KnowledgeBase.visible_to_role?(slug, role) do
      KnowledgeBase.fetch(slug)
    else
      :error
    end
  end

  defp chat(messages) do
    case OpenRouter.chat(messages) do
      {:ok, content} -> {:ok, content}
      {:error, :not_configured} -> {:error, :not_configured}
      {:error, reason} -> {:error, reason}
    end
  end

  defp find_guide_messages(query, catalog, role) do
    catalog_json = Jason.encode!(catalog)

    [
      %{
        role: "system",
        content: """
        You help YSC volunteers and admins find the right how-to guide.

        You MUST pick a guide_slug from the catalog below, or return guide_slug null if nothing fits.
        Respond with ONLY valid JSON (no markdown fences):
        {"guide_slug":"slug-or-null","explanation":"1-2 sentences","confidence":"high"|"low"}

        #{read_docs_instructions(role)}

        Rules:
        - guide_slug MUST be exactly one slug from the catalog, or null.
        - Do not invent guides or UI features.
        - explanation is friendly and brief. When no guide fits but the reference documents answer the question, put a short answer in explanation.

        Catalog:
        #{catalog_json}
        """
      },
      %{role: "user", content: query}
    ]
  end

  defp locate_messages(context, query) do
    [
      %{
        role: "system",
        content: """
        You pinpoint where in a how-to guide the answer to a user's question lives.

        Respond with ONLY valid JSON (no markdown fences):
        {"step": 1-based step number, "highlight": "short quote copied VERBATIM from that step's body"}

        Rules:
        - highlight must be an exact, contiguous quote from the chosen step's body (max ~120 characters). Do not include markdown ** markers, do not paraphrase.
        - Pick the single most helpful step. If no specific step clearly answers the question, respond {"step": null, "highlight": null}.

        Guide content:
        #{context}
        """
      },
      %{role: "user", content: query}
    ]
  end

  defp clarify_messages(context, step_index, question, role) do
    [
      %{
        role: "system",
        content: """
        You help explain admin how-to steps for YSC (#{role} role).

        Answer ONLY using the guide content below and the reference documents. Max 150 words.
        If the question is outside the admin tools entirely (billing disputes, member approvals, etc.), say you cannot help and suggest asking a board member.

        Respond with ONLY valid JSON (no markdown fences):
        {"answer":"your answer","suggested_step":null or step number 1-based}

        #{read_docs_instructions(role)}

        Current step index: #{step_index}

        Guide content:
        #{context}
        """
      },
      %{role: "user", content: question}
    ]
  end

  defp read_docs_instructions(role) do
    """
    Detailed reference documents and live-data snapshots are available. If the
    guide content is not enough to answer accurately, first respond with ONLY:
    {"read_docs":["slug",...]}
    using up to #{@max_docs} slugs from the lists below, and the content will
    be provided so you can give the final answer. Only request sources that
    are relevant to the question.

    Reference documents (how the admin tools work):
    #{KnowledgeBase.index_for_llm(role)}

    Live data (real, current content from this site — request these when the
    user asks about actual posts, events, newsletters, or wants examples):
    #{LiveExamples.index_for_llm()}
    """
  end

  defp parse_json(raw) do
    cleaned =
      raw
      |> String.trim()
      |> strip_code_fence()

    case Jason.decode(cleaned) do
      {:ok, map} when is_map(map) -> {:ok, map}
      _ -> {:error, :invalid_json}
    end
  end

  defp strip_code_fence(raw) do
    raw
    |> String.replace_prefix("```json", "")
    |> String.replace_prefix("```", "")
    |> String.trim_trailing("```")
    |> String.trim()
  end

  defp validate_finder_result(%{"explanation" => explanation} = parsed, role) do
    confidence =
      case parsed["confidence"] do
        "high" -> :high
        _ -> :low
      end

    slug = parsed["guide_slug"]

    guide_slug =
      cond do
        is_nil(slug) or slug == "null" or slug == "" ->
          nil

        Registry.valid_slug?(slug) and guide_allowed?(slug, role) and
            confidence == :high ->
          slug

        Registry.valid_slug?(slug) and guide_allowed?(slug, role) ->
          slug

        true ->
          nil
      end

    {:ok,
     %{
       guide_slug: guide_slug,
       explanation: String.trim(to_string(explanation)),
       confidence: confidence
     }}
  end

  defp validate_finder_result(_, _), do: {:error, :invalid_json}

  defp guide_allowed?(slug, role) when role in [:admin, :volunteer] do
    Registry.accessible?(slug, role)
  end

  defp guide_allowed?(slug, _role), do: Registry.valid_slug?(slug)

  # Validates the locate response: the step must exist and the highlight must
  # actually appear in that step's body (markdown markers ignored), otherwise
  # they are dropped rather than trusted.
  defp validate_location(parsed, guide_mod) when is_map(parsed) do
    steps = guide_mod.steps()
    step_count = length(steps)

    step =
      case parsed["step"] do
        n when is_integer(n) and n >= 1 and n <= step_count -> n
        n when is_binary(n) -> parse_step(n, step_count)
        _ -> nil
      end

    highlight =
      with n when is_integer(n) <- step,
           quote_text when is_binary(quote_text) <- parsed["highlight"],
           normalized <- normalize_highlight(quote_text),
           true <- highlight_in_step?(normalized, Enum.at(steps, n - 1)) do
        normalized
      else
        _ -> nil
      end

    %{step: step, highlight: highlight}
  end

  defp normalize_highlight(quote_text) do
    quote_text
    |> String.replace("**", "")
    |> String.trim()
    |> String.slice(0, 200)
  end

  defp highlight_in_step?("", _step), do: false

  defp highlight_in_step?(highlight, %{body: body}) do
    plain = String.replace(body, "**", "")

    String.contains?(String.downcase(plain), String.downcase(highlight))
  end

  defp highlight_in_step?(_, _), do: false

  defp validate_clarifier_result(%{"answer" => answer} = parsed, guide_mod) do
    step_count = length(guide_mod.steps())

    suggested =
      case parsed["suggested_step"] do
        n when is_integer(n) and n >= 1 and n <= step_count -> n
        n when is_binary(n) -> parse_step(n, step_count)
        _ -> nil
      end

    {:ok, %{answer: String.trim(to_string(answer)), suggested_step: suggested}}
  end

  defp validate_clarifier_result(_, _), do: {:error, :invalid_json}

  defp parse_step(str, max) do
    case Integer.parse(str) do
      {n, _} when n >= 1 and n <= max -> n
      _ -> nil
    end
  end
end
