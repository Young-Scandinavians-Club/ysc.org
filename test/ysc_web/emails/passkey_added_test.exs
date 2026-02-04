defmodule YscWeb.Emails.PasskeyAddedTest do
  use ExUnit.Case, async: true

  alias YscWeb.Emails.PasskeyAdded

  describe "get_template_name/0" do
    test "returns correct template name" do
      assert PasskeyAdded.get_template_name() == "passkey_added"
    end
  end
end
