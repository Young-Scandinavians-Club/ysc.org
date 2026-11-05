defmodule YscWeb.Components.Events.PosterQualityNotice do
  @moduledoc """
  Soft warnings shown under the event cover image picker.

  Two sources feed it, neither of which blocks anything:

    * `issues` - programmatic findings from `Ysc.Media.PosterQuality`
      (not 16:9, low resolution)
    * `review` - the multimodal LLM check from `Ysc.Media.PosterReview`:
      `nil` (nothing to show), `:running`, or a non-empty list of findings the
      admin can dismiss because the model can be wrong
  """
  use Phoenix.Component

  import YscWeb.CoreComponents

  alias Ysc.Media.PosterQuality
  alias Ysc.Media.PosterReview

  attr :id, :string, default: "cover-image-quality"
  attr :issues, :list, default: []
  attr :review, :any, default: nil

  def poster_quality_notice(assigns) do
    ~H"""
    <div
      :if={@issues != [] or @review != nil}
      id={@id}
      class="mt-4 space-y-3"
    >
      <.callout
        :for={issue <- @issues}
        id={"#{@id}-#{elem(issue, 0)}"}
        type="warning"
        icon="hero-exclamation-triangle"
        size="compact"
      >
        <:title>{issue |> PosterQuality.describe() |> elem(0)}</:title>
        {issue |> PosterQuality.describe() |> elem(1)}
      </.callout>

      <p
        :if={@review == :running}
        id={"#{@id}-review-running"}
        class="flex items-center gap-2 text-xs text-zinc-500"
        role="status"
      >
        <.icon name="hero-arrow-path" class="size-4 motion-safe:animate-spin" />
        Checking the photo against our layout guidelines…
      </p>

      <.callout
        :if={is_list(@review)}
        id={"#{@id}-review"}
        type="warning"
        icon="hero-sparkles"
        size="compact"
      >
        <:title>Automated photo check</:title>
        <ul class="list-disc space-y-1 pl-4">
          <li :for={finding <- @review} id={"#{@id}-review-#{finding.rule}"}>
            <span class="font-medium">
              {finding.rule |> PosterReview.describe() |> elem(0)}.
            </span>
            {finding.rule |> PosterReview.describe() |> elem(1)}
          </li>
        </ul>
        <p class="mt-2 text-zinc-600">
          This check is automatic and can be wrong. You can keep this photo.
        </p>
        <:actions>
          <button
            type="button"
            id={"#{@id}-review-dismiss"}
            phx-click="dismiss-cover-review"
            class="rounded-md border border-amber-300 bg-white px-2.5 py-1 text-xs font-medium text-amber-800 transition-colors hover:bg-amber-100"
          >
            Keep this photo
          </button>
        </:actions>
      </.callout>
    </div>
    """
  end
end
