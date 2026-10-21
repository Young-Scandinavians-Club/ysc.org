defmodule YscWeb.Components.CabinInfoTest do
  use YscWeb.ConnCase, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]
  import YscWeb.Components.CabinInfo

  defp rule(days, percentage) do
    %{days_before_checkin: days, refund_percentage: Decimal.new(percentage)}
  end

  describe "info_tabs/1" do
    test "renders the three journey tabs and marks the active one" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.info_tabs active={:manual} />
        """)

      assert html =~ ~s(phx-value-tab="general")
      assert html =~ ~s(phx-value-tab="manual")
      assert html =~ ~s(phx-value-tab="rules")
      assert html =~ "The Cabin & Rooms"
      assert html =~ "Arrival & House Manual"
      assert html =~ "Booking & Cancellation Policies"
      refute html =~ "info-tab-rooms"
      assert html =~ ~s(aria-selected="true")
      assert html =~ "border-blue-600"
    end

    test "uses the property accent on the active underline" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.info_tabs active={:general} accent={:teal} />
        """)

      assert html =~ "border-teal-600"
    end
  end

  describe "info_section/1" do
    test "puts the title in a left rail and the content beside it" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.info_section
          id="s"
          heading_id="s-heading"
          title="Bear Safety"
          eyebrow="Safety"
          description="Read before you arrive."
        >
          <p>Body copy</p>
        </.info_section>
        """)

      assert html =~ ~s(id="s")
      assert html =~ ~s(id="s-heading")
      assert html =~ "Bear Safety"
      assert html =~ "Safety"
      assert html =~ "Read before you arrive."
      assert html =~ "lg:col-span-4"
      assert html =~ "lg:col-span-8"
      assert html =~ "Body copy"
    end
  end

  describe "spec_list/1" do
    test "renders label/value rows and an id on the value" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.spec_list>
          <:row label="Check-in / out" id="hours">3:00 PM / 11:00 AM</:row>
          <:row label="Maximum stay">4 nights</:row>
        </.spec_list>
        """)

      assert html =~ "<dl"
      assert html =~ "Check-in / out"
      assert html =~ ~s(id="hours")
      assert html =~ "3:00 PM / 11:00 AM"
      assert html =~ "Maximum stay"
    end
  end

  describe "stat_strip/1" do
    test "renders each stat with an optional unit and detail" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.stat_strip id="rates">
          <:stat label="Adults" value="$45.00" unit="/night" />
          <:stat label="Under 5" value="Free" detail="No charge" />
        </.stat_strip>
        """)

      assert html =~ ~s(id="rates")
      assert html =~ "Adults"
      assert html =~ "$45.00"
      assert html =~ "/night"
      assert html =~ "Free"
      assert html =~ "No charge"
    end
  end

  describe "rule_strip/1" do
    test "renders one cell per rule with its icon, title and detail" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.rule_strip>
          <:item icon="hero-no-symbol" title="No Pets" detail="No exceptions" />
          <:item icon="hero-sparkles" tone={:warn} title="Linens" />
        </.rule_strip>
        """)

      assert html =~ "hero-no-symbol"
      assert html =~ "text-red-600"
      assert html =~ "No Pets"
      assert html =~ "No exceptions"
      assert html =~ "text-amber-600"
      assert html =~ "Linens"
    end
  end

  describe "numbered_steps/1" do
    test "zero-pads step numbers and omits the header without a title" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.numbered_steps>
          <:step>First</:step>
          <:step>Second</:step>
        </.numbered_steps>
        """)

      assert html =~ "01"
      assert html =~ "02"
      assert html =~ "First"
      refute html =~ "<h3"
    end

    test "renders a titled sequence with a status dot" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.numbered_steps title="To enter" dot={:amber}>
          <:step>Remove the wire</:step>
        </.numbered_steps>
        """)

      assert html =~ "To enter"
      assert html =~ "bg-amber-500"
    end
  end

  describe "checklist/1" do
    test "accepts plain strings and label/detail tuples" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.checklist items={["Clean up", {"Screenshot code", "Cell service is spotty"}]} />
        """)

      assert html =~ "Clean up"
      assert html =~ "Screenshot code"
      assert html =~ "Cell service is spotty"
      assert html =~ ~s(type="checkbox")
    end
  end

  describe "refund_table/1" do
    test "lists the union of thresholds with a column per stay type" do
      assigns = %{
        columns: [
          %{label: "Entire cabin", rules: [rule(21, "50"), rule(14, "0")]},
          %{label: "Individual room(s)", rules: [rule(14, "50")]}
        ]
      }

      html =
        rendered_to_string(~H"""
        <.refund_table id="refunds" columns={@columns} />
        """)

      assert html =~ ~s(id="refunds")
      assert html =~ "Entire cabin"
      assert html =~ "Individual room(s)"
      assert html =~ "21 or more days before check-in"
      assert html =~ "14 or more days before check-in"
      assert html =~ "50%"
      assert html =~ "0%"
      # Individual room(s) has no rule at the 21-day threshold.
      assert html =~ "—"
      refute html =~ "Policy information will be displayed here"
    end

    test "shows an empty state when no column has rules" do
      assigns = %{columns: [%{label: "Entire cabin", rules: []}]}

      html =
        rendered_to_string(~H"""
        <.refund_table columns={@columns} />
        """)

      assert html =~ "Policy information will be displayed here"
      refute html =~ "or more days before check-in"
    end
  end

  describe "essentials_strip/1" do
    test "renders each essential with its icon and optional id" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.essentials_strip id="essentials" accent={:teal}>
          <:item id="sleeping" icon="hero-moon">Bring your own linens</:item>
          <:item icon="hero-no-symbol">No pets or smoking</:item>
        </.essentials_strip>
        """)

      assert html =~ ~s(id="essentials")
      assert html =~ ~s(id="sleeping")
      assert html =~ "hero-moon"
      assert html =~ "text-teal-600"
      assert html =~ "No pets or smoking"
    end
  end

  describe "segmented_control/1" do
    test "renders a native radio group with the selected option checked" do
      assigns = %{
        options: [
          %{value: "room", id: "mode-room", label: "Individual Room(s)"},
          %{
            value: "buyout",
            id: "mode-buyout",
            label: "Entire Cabin",
            disabled: true
          }
        ]
      }

      html =
        rendered_to_string(~H"""
        <.segmented_control
          name="booking_mode"
          label="Booking type"
          selected="room"
          options={@options}
        />
        """)

      assert html =~ ~s(role="radiogroup")
      assert html =~ ~s(aria-label="Booking type")
      assert html =~ ~s(id="mode-room")
      assert html =~ ~s(id="mode-buyout")
      assert html =~ ~s(name="booking_mode")
      assert html =~ "Individual Room(s)"
      assert html =~ "Entire Cabin"
      assert html =~ "disabled"
      assert html =~ "cursor-not-allowed"
    end
  end

  describe "rules_bar/1" do
    test "renders one line item per rule" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.rules_bar id="date-rules">
          <:rule icon="hero-moon">Max 4 nights</:rule>
          <:rule icon="hero-calendar-days">No Saturday check-in</:rule>
        </.rules_bar>
        """)

      assert html =~ ~s(id="date-rules")
      assert html =~ "Max 4 nights"
      assert html =~ "No Saturday check-in"
    end
  end

  describe "refund_summary/1" do
    test "summarises the best refundable tier per stay type" do
      assigns = %{
        columns: [
          %{label: "Entire cabin", rules: [rule(21, "50"), rule(14, "0")]},
          %{label: "Individual room(s)", rules: [rule(14, "50"), rule(7, "25")]}
        ]
      }

      html =
        rendered_to_string(~H"""
        <.refund_summary id="refunds" columns={@columns} />
        """)

      assert html =~ "Entire cabin: 50% refund 21+ days before check-in"
      assert html =~ "Individual room(s): 50% refund 14+ days before check-in"
      assert html =~ "3% processing fee"
    end

    test "renders nothing when no stay type has a refundable tier" do
      assigns = %{columns: [%{label: "Entire cabin", rules: [rule(14, "0")]}]}

      html =
        rendered_to_string(~H"""
        <.refund_summary id="refunds" columns={@columns} />
        """)

      refute html =~ "refunds"
      refute html =~ "processing fee"
    end
  end

  describe "fine_print/1 and nearby_list/1" do
    test "render their items" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.fine_print>
          <:note>3% processing fee</:note>
        </.fine_print>
        <.nearby_list id="nearby">
          <:place name="Palisades Tahoe" minutes={20} />
        </.nearby_list>
        """)

      assert html =~ "3% processing fee"
      assert html =~ ~s(id="nearby-0")
      assert html =~ "Palisades Tahoe"
      assert html =~ "20 min"
    end
  end
end
