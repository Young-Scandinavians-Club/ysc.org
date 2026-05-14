defmodule YscWeb.Components.FormatFormErrorTest do
  use ExUnit.Case, async: true

  alias YscWeb.CoreComponents

  describe "format_form_error/1" do
    test "extracts message from {msg, type} tuple" do
      assert CoreComponents.format_form_error({"can't be blank", :required}) ==
               "can't be blank"
    end

    test "extracts message from {key, {msg, type}} tuple" do
      assert CoreComponents.format_form_error({:name, {"is invalid", :invalid}}) ==
               "is invalid"
    end
  end
end
