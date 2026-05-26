defmodule YscWeb.FormHelpersTest do
  use ExUnit.Case, async: true

  alias YscWeb.FormHelpers

  describe "format_form_error/1" do
    test "extracts message from keyed tuple" do
      assert FormHelpers.format_form_error({:email, {"is invalid", []}}) ==
               "is invalid"
    end

    test "extracts message from message tuple" do
      assert FormHelpers.format_form_error({"can't be blank", []}) ==
               "can't be blank"
    end
  end
end
