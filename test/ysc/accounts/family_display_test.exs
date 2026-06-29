defmodule Ysc.Accounts.FamilyDisplayTest do
  use ExUnit.Case, async: true

  alias Ysc.Accounts.FamilyDisplay

  describe "relationship_label/1" do
    test "returns Spouse for spouse values" do
      assert FamilyDisplay.relationship_label(:spouse) == "Spouse"
      assert FamilyDisplay.relationship_label("spouse") == "Spouse"
    end

    test "returns Child for child values" do
      assert FamilyDisplay.relationship_label(:child) == "Child"
      assert FamilyDisplay.relationship_label("child") == "Child"
    end

    test "defaults nil and unknown values to Child" do
      assert FamilyDisplay.relationship_label(nil) == "Child"
      assert FamilyDisplay.relationship_label("other") == "Child"
      assert FamilyDisplay.relationship_label(:unknown) == "Child"
    end
  end
end
