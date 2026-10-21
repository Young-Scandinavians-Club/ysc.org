defmodule YscWeb.Components.CabinInfoTest do
  use YscWeb.ConnCase, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]
  import YscWeb.Components.CabinInfo

  defp rule(days, percentage) do
    %{days_before_checkin: days, refund_percentage: Decimal.new(percentage)}
  end

  defp percentages(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("tbody tr")
    |> Enum.map(fn row ->
      row
      |> Floki.find("td")
      |> Enum.map(
        &(&1
          |> Floki.text()
          |> String.trim()
          |> String.trim_trailing("%")
          |> String.to_integer())
      )
    end)
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
    test "lists bands between the union of thresholds, one column per stay type" do
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
      assert html =~ "More than 21 days before check-in"
      assert html =~ "15–21 days before check-in"
      assert html =~ "14 days or fewer before check-in"
      refute html =~ "or more days"
      refute html =~ "Policy information will be displayed here"

      # Entire cabin: full refund early, 50% within 21 days, none within 14.
      # Individual room(s): full until 14 days, then 50%.
      assert percentages(html) == [[100, 100], [50, 100], [0, 50]]
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
          <:item id="sleeping" icon="hero-moon" title="Sleeping">
            Bring your own linens
          </:item>
          <:item icon="hero-no-symbol" title="House rules">
            No pets or smoking
          </:item>
        </.essentials_strip>
        """)

      assert html =~ ~s(id="essentials")
      assert html =~ ~s(id="sleeping")
      assert html =~ "hero-moon"
      assert html =~ "bg-teal-50"
      assert html =~ "Sleeping"
      assert html =~ "House rules"
      assert html =~ "No pets or smoking"
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

  describe "cabin_modal/1" do
    test "renders an accessible dialog above the navbar with header, body and footer" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.cabin_modal
          id="rules"
          title="Rules & Policies"
          description="Read before booking."
          on_close="close-rules"
        >
          <.modal_section title="Quiet hours">10 PM – 7 AM</.modal_section>
          <:footer><button type="button">I Understand</button></:footer>
        </.cabin_modal>
        """)

      assert html =~ ~s(id="rules")
      assert html =~ "z-200"
      assert html =~ ~s(role="dialog")
      assert html =~ ~s(aria-modal="true")
      assert html =~ ~s(aria-labelledby="rules-title")
      assert html =~ ~s(id="rules-title")
      assert html =~ "Rules &amp; Policies"
      assert html =~ "Read before booking."
      assert html =~ ~s(phx-click="close-rules")
      assert html =~ ~s(phx-key="escape")
      assert html =~ "Quiet hours"
      assert html =~ "10 PM – 7 AM"
      assert html =~ "I Understand"
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
