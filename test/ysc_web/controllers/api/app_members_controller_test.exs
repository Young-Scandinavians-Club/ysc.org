defmodule YscWeb.Api.AppMembersControllerTest do
  @moduledoc """
  Tests for the admin/volunteer mobile app's member search endpoint
  (`AppMembersController` + `AppMembersJSON`).
  """
  use YscWeb.ConnCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Accounts

  setup %{conn: conn} do
    admin = user_fixture(%{role: :admin})
    token = Accounts.generate_user_mobile_token(admin)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")

    {:ok, conn: conn}
  end

  describe "GET /api/v1/app/members/search" do
    test "finds a member by name", %{conn: conn} do
      unique = System.unique_integer([:positive])

      member =
        user_fixture(%{
          first_name: "Zaphod#{unique}",
          last_name: "Beeblebrox",
          email: unique_user_email()
        })

      response = get(conn, ~p"/api/v1/app/members/search?q=Zaphod#{unique}")

      assert %{"data" => [result]} = json_response(response, 200)
      assert result["id"] == to_string(member.id)
      assert result["first_name"] == member.first_name
      assert result["email"] == member.email
      assert result["has_active_membership"] == false
      assert is_binary(result["avatar_url"]) and result["avatar_url"] != ""
    end

    test "reports active membership from a batched lookup", %{conn: conn} do
      unique = System.unique_integer([:positive])

      member =
        user_fixture(%{
          first_name: "Trillian#{unique}",
          last_name: "McMillan",
          email: unique_user_email()
        })

      {:ok, _subscription} =
        Ysc.Subscriptions.create_subscription(%{
          user_id: member.id,
          stripe_id: "sub_app_search_#{unique}",
          stripe_status: "active",
          name: "Membership",
          current_period_end:
            DateTime.utc_now()
            |> DateTime.add(30, :day)
            |> DateTime.truncate(:second)
        })

      Ysc.Accounts.MembershipCache.invalidate_user(member.id)

      response = get(conn, ~p"/api/v1/app/members/search?q=Trillian#{unique}")

      assert %{"data" => [result]} = json_response(response, 200)
      assert result["id"] == to_string(member.id)
      assert result["has_active_membership"] == true
    end

    test "does not query subscriptions once per search hit", %{conn: conn} do
      unique = System.unique_integer([:positive])
      prefix = "Zarniwoop#{unique}"

      members =
        for i <- 1..8 do
          member =
            user_fixture(%{
              first_name: "#{prefix}#{i}",
              last_name: "Search",
              email: unique_user_email()
            })

          {:ok, _subscription} =
            Ysc.Subscriptions.create_subscription(%{
              user_id: member.id,
              stripe_id: "sub_app_n1_#{unique}_#{i}",
              stripe_status: "active",
              name: "Membership",
              current_period_end:
                DateTime.utc_now()
                |> DateTime.add(30, :day)
                |> DateTime.truncate(:second)
            })

          Ysc.Accounts.MembershipCache.invalidate_user(member.id)
          member
        end

      {_response, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn -> get(conn, ~p"/api/v1/app/members/search?q=#{prefix}") end,
          pattern: ~r/FROM "subscriptions"/i,
          caller_pids: [self()]
        )

      assert query_count <= 2
      assert length(members) == 8
    end

    test "falls back to a default avatar when the member has none uploaded", %{
      conn: conn
    } do
      member = user_fixture()

      response = get(conn, ~p"/api/v1/app/members/search?q=#{member.email}")

      assert %{"data" => [result]} = json_response(response, 200)
      assert result["avatar_url"] =~ "/images/default_avatars/"
    end

    test "uses the member's uploaded avatar when one is set", %{conn: conn} do
      member = user_fixture()

      avatar =
        %Ysc.Avatars.Avatar{
          user_id: member.id,
          source: :upload,
          original_path: "orig.jpg",
          processing_state: :completed,
          thumb_path: "https://cdn.example.com/avatar_thumb.webp",
          profile_path: "https://cdn.example.com/avatar_profile.webp"
        }
        |> Ysc.Repo.insert!()

      member
      |> Ecto.Changeset.change(current_avatar_id: avatar.id)
      |> Ysc.Repo.update!()

      response = get(conn, ~p"/api/v1/app/members/search?q=#{member.email}")

      assert %{"data" => [result]} = json_response(response, 200)
      assert result["avatar_url"] == "https://cdn.example.com/avatar_thumb.webp"
    end

    test "finds a member by email", %{conn: conn} do
      member = user_fixture()

      response = get(conn, ~p"/api/v1/app/members/search?q=#{member.email}")

      assert %{"data" => data} = json_response(response, 200)
      assert Enum.any?(data, &(&1["id"] == to_string(member.id)))
    end

    test "returns an empty list for no matches", %{conn: conn} do
      response = get(conn, ~p"/api/v1/app/members/search?q=nonexistent-zzz")

      assert %{"data" => []} = json_response(response, 200)
    end

    test "returns 400 when q is missing", %{conn: conn} do
      response = get(conn, ~p"/api/v1/app/members/search")

      assert json_response(response, 400)
    end

    test "returns 400 when q is too short", %{conn: conn} do
      response = get(conn, ~p"/api/v1/app/members/search?q=a")

      assert json_response(response, 400)
    end

    test "returns 401 without a bearer token", %{conn: conn} do
      response =
        conn
        |> Plug.Conn.delete_req_header("authorization")
        |> get(~p"/api/v1/app/members/search?q=test")

      assert json_response(response, 401)
    end
  end
end
