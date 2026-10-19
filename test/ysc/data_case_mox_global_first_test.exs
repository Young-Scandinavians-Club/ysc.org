defmodule Ysc.DataCaseMoxGlobalFirstTest do
  @moduledoc """
  DataCase `mox_global_first: true` must claim global Mox before default stubs
  and return to private mode on exit.

  `setup :set_mox_global` in a DataCase module runs *after* those stubs and
  does not reset the owner. The next test then flakes in
  `stub_default_external_mocks/0` with "only the process that set Mox to global
  can set expectations/stubs" — see `Ysc.Ledgers.MerchShippingTest` on main
  (CI seed 161110).
  """
  use Ysc.DataCase, async: false, mox_global_first: true

  test "this process owns global mode so default stubs can be reinstalled" do
    Ysc.DataCase.stub_default_external_mocks()
  end

  test "a sibling process cannot stub while this test owns global mode" do
    result =
      Task.await(
        Task.async(fn ->
          try do
            Ysc.DataCase.stub_default_external_mocks()
            :ok
          rescue
            error in ArgumentError -> {:error, Exception.message(error)}
          end
        end)
      )

    assert {:error, message} = result
    assert message =~ "Only the process that set Mox to global"
  end

  test "a later test in the same module can still install default stubs" do
    Ysc.DataCase.stub_default_external_mocks()
  end
end
