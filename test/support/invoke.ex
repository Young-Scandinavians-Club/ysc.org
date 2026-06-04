defmodule Ysc.Test.Invoke do
  @moduledoc false

  @doc """
  Dynamic apply for tests that intentionally pass invalid arguments to `assert_raise/2`.
  Avoids gradual-typing compile warnings when calling typed context functions with `nil`.
  """
  def call(module, function, args)
      when is_atom(module) and is_atom(function) and is_list(args) do
    apply(module, function, args)
  end
end
