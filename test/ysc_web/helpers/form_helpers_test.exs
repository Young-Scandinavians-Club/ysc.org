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

  describe "translate_error/1" do
    test "interpolates option placeholders" do
      assert FormHelpers.translate_error(
               {"must be at least %{count} characters", count: 8}
             ) ==
               "must be at least 8 characters"
    end
  end

  describe "changeset_errors/1" do
    test "returns a field-keyed map of translated messages" do
      changeset =
        {%{}, %{email: :string}}
        |> Ecto.Changeset.cast(%{}, [:email])
        |> Ecto.Changeset.validate_required([:email])

      assert FormHelpers.changeset_errors(changeset) == %{
               email: ["can't be blank"]
             }
    end
  end

  describe "format_changeset_errors/2" do
    setup do
      changeset =
        {%{}, %{email: :string, name: :string}}
        |> Ecto.Changeset.cast(%{}, [:email, :name])
        |> Ecto.Changeset.validate_required([:email, :name])

      [changeset: changeset]
    end

    test "groups errors by field with default separator", %{
      changeset: changeset
    } do
      message = FormHelpers.format_changeset_errors(changeset)

      assert message =~ "email: can't be blank"
      assert message =~ "name: can't be blank"
      assert message =~ "; "
    end

    test "supports flat style with custom separator", %{changeset: changeset} do
      message =
        FormHelpers.format_changeset_errors(changeset,
          style: :flat,
          separator: ". "
        )

      assert message =~ "email: can't be blank"
      assert message =~ "name: can't be blank"
      assert message =~ ". "
    end

    test "humanizes field names when requested", %{changeset: changeset} do
      message =
        FormHelpers.format_changeset_errors(changeset, field_format: :humanize)

      assert message =~ "Email: can't be blank"
      assert message =~ "Name: can't be blank"
    end
  end
end
