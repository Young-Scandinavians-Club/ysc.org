defmodule YscWeb.AdminMessageTypeBadgeTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.AdminComponents

  describe "admin_message_type_badge/1" do
    test "table variant uses channel colors and uppercase label" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_message_type_badge message_type={:email} variant={:table} />
        """)

      assert html =~ "EMAIL"
      assert html =~ "bg-blue-100 text-blue-800"
    end

    test "table variant uses green for SMS" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_message_type_badge message_type={:sms} variant={:table} />
        """)

      assert html =~ "SMS"
      assert html =~ "bg-green-100 text-green-800"
    end

    test "detail variant uses default badge styling" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_message_type_badge message_type={:email} variant={:detail} />
        """)

      assert html =~ "Email"
      assert html =~ "bg-blue-100 text-blue-800"
      refute html =~ "EMAIL"
    end
  end
end
