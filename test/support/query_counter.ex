defmodule Ysc.QueryCounter do
  @moduledoc """
  Counts Ecto SQL queries matching a pattern during a block.
  """

  def with_query_counter(fun, opts \\ []) when is_function(fun, 0) do
    # Serialize query counting across the suite. Telemetry handlers are global,
    # so parallel async tests can otherwise pollute counts.
    :global.trans({:ysc, :query_counter}, fn ->
      pattern = Keyword.get(opts, :pattern, ~r/SELECT/)
      ref = :atomics.new(1, [])

      handler_id = {:ysc_query_counter, make_ref()}

      :telemetry.attach(
        handler_id,
        [:ysc, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          query = metadata |> Map.get(:query, "") |> IO.iodata_to_binary()

          if Regex.match?(pattern, query) do
            :atomics.add(ref, 1, 1)
          end
        end,
        nil
      )

      try do
        result = fun.()
        count = :atomics.get(ref, 1)
        {result, count}
      after
        :telemetry.detach(handler_id)
      end
    end)
  end
end
