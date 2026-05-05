# Used by `mix ci.query_explain` and PR CI. Each target must return a SELECT-style
# `%Ecto.Query{}` from `apply(module, function, args)`.
[
  %{
    id: "ticket_orders_pending_timeout",
    source_paths: [
      "lib/ysc/ci/query_explain.ex",
      "lib/ysc/tickets/timeout_worker.ex"
    ],
    mfa: {Ysc.Ci.QueryExplain, :ticket_orders_pending_timeout_batch_query, []}
  },
  %{
    id: "upcoming_events_with_preload",
    source_paths: ["lib/ysc/events.ex"],
    mfa: {Ysc.Events, :upcoming_events_with_preload_query, []}
  }
]
