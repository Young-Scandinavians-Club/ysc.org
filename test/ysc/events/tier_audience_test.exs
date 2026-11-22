defmodule Ysc.Events.TierAudienceTest do
  use Ysc.DataCase, async: true

  alias Ysc.Events.TicketTier
  alias Ysc.Events.TierAudience

  describe "audience/1" do
    test "reads sale_audience from atom and string keys" do
      assert TierAudience.audience(%{sale_audience: :public}) == :public
      assert TierAudience.audience(%{"sale_audience" => "public"}) == :public

      assert TierAudience.audience(%{sale_audience: :members_only}) ==
               :members_only

      assert TierAudience.audience(%{sale_audience: :member_guests}) ==
               :member_guests
    end

    test "falls back to the legacy member_only flag" do
      assert TierAudience.audience(%{member_only: true}) == :members_only
      assert TierAudience.audience(%{member_only: false}) == :member_guests
      assert TierAudience.audience(%{}) == :member_guests
    end

    test "donation tiers are never members-only" do
      assert TierAudience.audience(%{
               type: :donation,
               sale_audience: :members_only
             }) == :member_guests

      assert TierAudience.audience(%{type: :donation, sale_audience: :public}) ==
               :public
    end
  end

  describe "public?/1, any_public?/1, all_public?/1" do
    test "classify tier lists" do
      public = %{sale_audience: :public}
      members = %{sale_audience: :members_only}

      assert TierAudience.public?(public)
      refute TierAudience.public?(members)
      refute TierAudience.public?(nil)

      assert TierAudience.any_public?([members, public])
      refute TierAudience.any_public?([members])

      assert TierAudience.all_public?([public, public])
      refute TierAudience.all_public?([public, members])
      refute TierAudience.all_public?([])
    end
  end

  describe "access/2" do
    test "public tiers are available to everyone" do
      tier = %{sale_audience: :public}

      for viewer <- [:anonymous, :non_member, :member] do
        assert TierAudience.access(tier, viewer) == :available
      end
    end

    test "member tiers ask anonymous visitors to sign in" do
      for audience <- [:members_only, :member_guests] do
        tier = %{sale_audience: audience}
        assert TierAudience.access(tier, :anonymous) == :sign_in_required
        assert TierAudience.access(tier, :non_member) == :membership_required
        assert TierAudience.access(tier, :member) == :available
      end
    end
  end

  describe "TicketTier.changeset/2 keeps member_only in sync" do
    defp changeset(attrs) do
      TicketTier.changeset(
        %TicketTier{},
        Map.merge(
          %{
            name: "Tier",
            type: :paid,
            price: Money.new(10, :USD),
            event_id: Ecto.ULID.generate()
          },
          attrs
        )
      )
    end

    test "defaults to member_guests and not member-only" do
      cs = changeset(%{})
      assert Ecto.Changeset.get_field(cs, :sale_audience) == :member_guests
      refute Ecto.Changeset.get_field(cs, :member_only)
    end

    test "members_only audience sets member_only" do
      cs = changeset(%{sale_audience: "members_only"})
      assert Ecto.Changeset.get_field(cs, :sale_audience) == :members_only
      assert Ecto.Changeset.get_field(cs, :member_only)
    end

    test "public audience clears member_only" do
      cs = changeset(%{sale_audience: "public", member_only: true})
      assert Ecto.Changeset.get_field(cs, :sale_audience) == :public
      refute Ecto.Changeset.get_field(cs, :member_only)
    end

    test "an explicit audience wins even when it equals the current value" do
      tier = %TicketTier{sale_audience: :member_guests, member_only: false}

      cs =
        TicketTier.changeset(tier, %{
          "sale_audience" => "member_guests",
          "member_only" => "true"
        })

      assert Ecto.Changeset.get_field(cs, :sale_audience) == :member_guests
      refute Ecto.Changeset.get_field(cs, :member_only)
    end

    test "legacy member_only: true lands on members_only" do
      cs = changeset(%{member_only: true})
      assert Ecto.Changeset.get_field(cs, :sale_audience) == :members_only
    end

    test "rejects an unknown audience" do
      cs = changeset(%{sale_audience: "everyone"})
      refute cs.valid?
      assert %{sale_audience: [_]} = errors_on(cs)
    end

    test "public tiers cannot require per-ticket details" do
      cs = changeset(%{sale_audience: "public", requires_registration: true})
      refute cs.valid?
      assert %{sale_audience: [message]} = errors_on(cs)
      assert message =~ "name and email"

      assert changeset(%{
               sale_audience: "members_only",
               requires_registration: true
             }).valid?

      assert changeset(%{sale_audience: "public", requires_registration: false}).valid?
    end
  end
end
