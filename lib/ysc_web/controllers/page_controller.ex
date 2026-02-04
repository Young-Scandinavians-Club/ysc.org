defmodule YscWeb.PageController do
  use YscWeb, :controller

  use Timex

  def home(conn, _params) do
    render(conn, :home)
  end

  def history(conn, _params) do
    past_presidents = [
      {"1951", "Arnold Rolkert"},
      {"1952", "Uno Odman"},
      {"1953", "Erik Stenstedt"},
      {"1954", "Stefan Gjerstad"},
      {"1955", "Sven Thomasen"},
      {"1956", "Arnold Rolkert"},
      {"1957", "Carlo Hojsgaard"},
      {"1958", "Ole Trock Jansen"},
      {"1959", "Arne(Rolf) Gille"},
      {"1960", "Svend Svendsen"},
      {"1961-1964", "Lisa Wiborg"},
      {"1965", "Al Wold"},
      {"1966", "Svend Baekgaard, Carsten Mikkelsen"},
      {"1967", "Lisa Wiborg"},
      {"1968", "Arne Waslund"},
      {"1969-1970", "Soren Walther"},
      {"1971", "Amund Barstad"},
      {"1973", "Jorgen Larsen"},
      {"1974", "Gertrud Markgren"},
      {"1975", "Ben Bylander"},
      {"1976", "Jens Bruun de Neergaard"},
      {"1977", "Per Madsen"},
      {"1978", "Wiveca Remon"},
      {"1979", "Mogens Schow"},
      {"1980-1981", "Inge Sullivan"},
      {"1982", "Einar Asbo"},
      {"1983", "Birgitta Lotman"},
      {"1984", "Signe Vik"},
      {"1985-1986", "David McGehee"},
      {"1987-1988", "Bent Kjolby"},
      {"1989-1990", "David Anderson"},
      {"1991-1993", "Craig Lieber"},
      {"1994-1996", "Stig Tisell"},
      {"1997", "Andrew Vik"},
      {"1998", "Rodney Hiram"},
      {"1999", "Jeanette Sorensen"},
      {"2000-2001", "Craig Lieber"},
      {"2002-2003", "Morten Qwist"},
      {"2004", "Joshua Aasved"},
      {"2005", "Thomas Nielsen"},
      {"2006", "Ben Blount"},
      {"2007-2008", "Jennifer Arton Tegnerud"},
      {"2009", "Amanda Aasved Merritt"},
      {"2010-2011", "Thomas Nielsen"},
      {"2012-2013", "Niels Kvaavik"},
      {"2014-2019", "Peter Nordström"},
      {"2020-2022", "Ulrika Lidström"},
      {"2023-2026", "Jeanette Flodell"},
      {"2026-present", "TBD"}
    ]

    conn
    |> assign(:past_presidents, past_presidents)
    |> assign(:page_title, "History")
    |> render(:history)
  end

  def privacy_policy(conn, _params) do
    conn
    |> assign(:page_title, "Privacy Policy")
    |> render(:privacy_policy)
  end

  def terms_of_service(conn, _params) do
    conn
    |> assign(:page_title, "Terms of Service")
    |> render(:terms_of_service)
  end

  def board(conn, _params) do
    bod_members =
      Ysc.Accounts.list_bod_members()
      |> Enum.map(fn member ->
        Map.merge(member, %{
          first_name: String.capitalize(member.first_name || ""),
          last_name: String.capitalize(member.last_name || "")
        })
      end)

    existing_filled =
      MapSet.new(Enum.map(bod_members, fn member -> member.board_position end))

    all_positions =
      MapSet.new([
        :president,
        :vice_president,
        :secretary,
        :treasurer,
        :clear_lake_cabin_master,
        :tahoe_cabin_master,
        :event_director,
        :member_outreach,
        :membership_director
      ])

    vacant_positions = MapSet.difference(all_positions, existing_filled)

    conn
    |> assign(:bod_members, bod_members)
    |> assign(:vacant_positions, vacant_positions)
    |> assign(:page_title, "Board of Directors")
    |> render(:board)
  end

  def contact(conn, _params) do
    conn
    |> assign(:page_title, "Contact")
    |> render(:contact)
  end

  def code_of_conduct(conn, _params) do
    conn
    |> assign(:page_title, "Non-Discrimination Code of Conduct")
    |> render(:code_of_conduct)
  end

  def bylaws(conn, _params) do
    conn
    |> assign(:page_title, "Bylaws")
    |> render(:bylaws)
  end

  def financials(conn, _params) do
    conn
    |> assign(:page_title, "Financials & Annual Meetings")
    |> render(:financials)
  end

  def pending_review(conn, _params) do
    accounts_module = Application.get_env(:ysc, :accounts_module, Ysc.Accounts)
    current_user = conn.assigns.current_user

    submitted_application_at =
      accounts_module.get_signup_application_submission_date(current_user.id)

    submitted_date = submitted_application_at[:submit_date]

    timezone =
      case submitted_application_at[:timezone] do
        nil -> "America/Los_Angeles"
        v -> v
      end

    local_date = Timex.Timezone.convert(submitted_date, timezone)
    days_ago = Timex.from_now(submitted_date)

    conn
    |> assign(:application_submitted_date, local_date)
    |> assign(:time_delta, days_ago)
    |> assign(:page_title, "Account Pending Review")
    |> render(:pending_review)
  end
end
