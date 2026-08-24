defmodule YscWeb.PageHTML do
  use YscWeb, :html

  import Ysc.Text, only: [titleize: 1]
  import YscWeb.Components.History.HistoryComponents

  embed_templates "page_html/*"
end
