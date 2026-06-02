defmodule YscWeb.EventTvPosterHTML do
  @moduledoc false
  use YscWeb, :html

  import YscWeb.Components.Events.EventTvPoster

  embed_templates "event_tv_poster_html/*"
end
