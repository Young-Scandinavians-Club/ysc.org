defmodule Ysc.History.Timeline do
  @moduledoc """
  Static timeline data for the YSC history page.
  """

  @type event_type :: :decade | :event | :milestone | :featured

  @type image :: %{
          src: String.t(),
          alt: String.t(),
          caption: String.t() | nil,
          era: String.t() | nil,
          aspect: String.t() | nil
        }

  @type event :: %{
          type: event_type(),
          year: String.t(),
          title: String.t() | nil,
          tags: [String.t()],
          body: String.t() | nil,
          body_html: String.t() | nil,
          images: [image()],
          blockquote: String.t() | nil,
          ledger: String.t() | nil,
          extra_tags: [String.t()]
        }

  @doc """
  Returns all timeline entries in display order.
  """
  @spec events() :: [event()]
  def events do
    [
      decade("1950s"),
      featured(
        "1950",
        "The Beginning: Five Friends, One Vision",
        ["founding", "club leadership"],
        body:
          "The idea was to build a club for newly settled Scandinavians far from home—where they could speak their native language, celebrate Scandinavian traditions, and find a fun, active alternative to the more traditional lodges in San Francisco. Thirty members attended the club's first general meeting the following January, and Arnold became its first president. This moment marked the birth of a community that would span generations and create countless memories.",
        blockquote:
          "On August 19, 1950, Arnold Rolkert gathered a group of friends together including Gunnar Engen, Carlo Hojsgaard, Peter Larsen Bernard, and Ulla Lindberg to form what they called The Young Scandinavians Club of San Francisco. The name was later shortened to The Young Scandinavians Club.",
        ledger:
          "Initial Membership Fee: $5.00 annual dues\nCharter Members: 30 founding members",
        extra_tags: ["Founder's Corner"],
        images: [
          %{
            src: "/images/history/ysc_origin_story_by_arnold.webp",
            alt: "Arnold Rolkert's account of founding the YSC in 1950",
            caption: nil,
            era: "1950s",
            aspect: nil
          }
        ]
      ),
      event(
        "1957",
        "Seasonal Cabin Rentals Begin",
        ["cabin life", "organization"],
        "President Svend Svendsen led the club in beginning the annual tradition of renting seasonal properties at Clear Lake and in the Sierra Nevada—laying the groundwork for the cabin culture that would define YSC for decades."
      ),
      decade("1960s"),
      event(
        "1960",
        "Incorporated as Non-Profit",
        ["organization", "anniversary"],
        "YSC incorporated as a nonprofit organization; 10th anniversary banquet at Canterbury Hotel (anniversaries celebrated every 5 years since); first ski cabin rented at Lake Tahoe.",
        images: [
          %{
            src: "/images/history/nordic_highlight_1960_frontpage.webp",
            alt: "Nordic Highlight frontpage from 1960",
            caption: "Nordic Highlight newsletter from 1960",
            era: "1960s",
            aspect: "3/4"
          }
        ]
      ),
      event(
        "1961",
        "Lisa for President",
        ["club leadership"],
        "Lisa Gille (now Wiborg) begins four-year reign as president. She later serves another year. Started renting current Clear Lake cabin."
      ),
      milestone(
        "1963",
        "The Clear Lake Acquisition",
        ["cabin life"],
        "The Clear Lake property was acquired, establishing the club's first permanent home. That same year, 40 members took a legendary group flight back to Scandinavia.",
        ledger:
          "Purchase Price: $28,000\nDown Payment: $10,000\nFinancing: $200/month for 10 years",
        images: [
          %{
            src: "/images/history/SAS 1963.webp",
            alt: "YSC members on SAS flight to Scandinavia in 1963",
            caption:
              "40 YSC members on their legendary group flight back to Scandinavia",
            era: "1960s",
            aspect: "4/3"
          },
          %{
            src: "/images/history/clear_lake_from_above.webp",
            alt: "Aerial view of Clear Lake cabin and dock",
            caption: "Clear Lake cabin with the 100-foot private dock",
            era: "2000s",
            aspect: "4/3"
          }
        ]
      ),
      event(
        "1964",
        "Cabin Manager and Activities Director on the Board",
        ["club leadership"],
        "Cabin Manager and Activities Director positions elevated to Executive Committee status."
      ),
      event(
        "1965",
        "15th Anniversary Celebration",
        ["anniversary"],
        "YSC celebrates its 15th Anniversary, continuing the tradition of commemorating club milestones every five years with members and friends.",
        images: [
          %{
            src: "/images/history/ysc_15th_anniversary.webp",
            alt: "YSC 15th Anniversary celebration",
            caption: "15th Anniversary banquet celebration",
            era: "1960s",
            aspect: "4/3"
          }
        ]
      ),
      event(
        "1966",
        "Improvements to Clear Lake",
        ["cabin life"],
        "Members make major improvements to Clear Lake property, including septic tank, parking area, and leach field."
      ),
      event(
        "1967",
        "Clear Lake Bathroom Construction",
        ["cabin life"],
        "New bathrooms constructed at Clear Lake cabin."
      ),
      event(
        "1974",
        "Clear Lake Paid Off",
        ["cabin life"],
        "Clear Lake loan paid off. The cabin and its 3/4 acre lot is ours."
      ),
      decade("1970s"),
      event(
        "1970",
        "20th Anniversary",
        ["anniversary"],
        "On September 26, 1970, YSC celebrates its 20th Anniversary with a grand celebration at Del Webb's Townhouse in San Francisco. In a remarkable show of diplomatic support, all the Consul Generals of the Nordic countries attended—representing Iceland, Norway, Denmark, Sweden, and Finland—marking this as one of the most prestigious events in YSC history.",
        images: [
          %{
            src: "/images/history/ysc_20th_anniversary.webp",
            alt: "YSC 20th Anniversary celebration",
            caption: "YSC 20th Anniversary celebration",
            era: "1970s",
            aspect: "4/3"
          }
        ]
      ),
      event(
        "1970s",
        "Yosemite Adventure",
        ["organization"],
        "YSC members embark on memorable outdoor adventures to Yosemite National Park, strengthening bonds through shared experiences in nature.",
        images: [
          %{
            src: "/images/history/ysc_yosemite.webp",
            alt: "YSC members at Yosemite National Park",
            caption: "YSC members at Yosemite National Park",
            era: "1970s",
            aspect: "4/3"
          }
        ]
      ),
      event(
        "1976",
        "New pier",
        ["cabin life"],
        "New pier built at Clear Lake."
      ),
      event(
        "1980",
        "New dock",
        ["cabin life"],
        "New floating dock at Clear Lake."
      ),
      event(
        "1979-1981",
        "Clear Lake rebuild",
        ["cabin life"],
        "Formed CL Task Force to rebuild cabin. Produced architectural plans and received bids from contractors for 2-story building, cost $135 to $160K. Plans were dropped due to an existing building moratorium and resulting permit problems. It was decided to renovate instead."
      ),
      event(
        "1981-1982",
        "Major Clear Lake renovations",
        ["cabin life"],
        "Major renovations on Clear Lake cabin, with member Inge Sullivan as key contractor—carrying forward the renovation plan after rebuild plans were shelved due to the building moratorium.",
        ledger:
          "Total Cost: $80,000\nPlumbing: Connections for two shower stalls and a toilet installed in the men's dressing room"
      ),
      decade("1980s"),
      event(
        "1985",
        "35th Anniversary Celebration",
        ["anniversary"],
        nil,
        body_html:
          "On <strong>November 2, 1985</strong>, YSC celebrates its 35th Anniversary with an elegant celebration at the <strong>St. Francis Yacht Club</strong>, commemorating 35 years of Scandinavian fellowship and tradition.",
        images: [
          %{
            src: "/images/history/35th_anniversary_program.webp",
            alt: "35th Anniversary celebration program cover",
            caption: "Anniversary program cover",
            era: "1980s",
            aspect: "3/4"
          },
          %{
            src: "/images/history/35th_anniversary_program_2.webp",
            alt: "35th Anniversary celebration program inside",
            caption: "Program details",
            era: "1980s",
            aspect: "3/4"
          }
        ]
      ),
      decade("1990s"),
      event(
        "1985",
        "Lucia Celebration",
        ["organization"],
        "YSC Lucia celebration captured in this memorable photo.",
        images: [
          %{
            src: "/images/history/Lucia 1985 03.webp",
            alt: "YSC Lucia celebration, 1985",
            caption: "YSC Lucia celebration, 1985",
            era: "1980s",
            aspect: "4/3"
          }
        ]
      ),
      event(
        "1986",
        "Executive Committee",
        ["cabin life", "club leadership"],
        "The Executive Committee meeting at Clear Lake. New floating docks with steel pilings and sea wall reconstruction completed.",
        images: [
          %{
            src: "/images/history/Exec Comm 1986.webp",
            alt: "Executive Committee at Clear Lake, 1986",
            caption: "Executive Committee at Clear Lake, 1986",
            era: "1980s",
            aspect: "4/3"
          }
        ]
      ),
      event(
        "1988",
        "Tahoe Acquisition Campaign Begins",
        ["cabin life"],
        "After years of renting winter properties in the Sierras, the club formally committed to purchasing a Tahoe cabin. A Tahoe Acquisition Committee led by Bent Kjølby, with Curt Berg, Bobby Weinstein, and Joe MacKie, launched an organized fundraising drive that would culminate in the 1993 purchase."
      ),
      milestone(
        "1993",
        "Tahoe Cabin Purchase",
        ["cabin life"],
        "Under President Craig Lieber, the club purchased the Tahoe cabin for $190,000 in August 1993—financing $100,000 at 7.5% with a balloon payment due in 2008. Members raised over $75,000 through fundraising efforts, matched by $15,000 from the general fund, under the leadership of Bent Kjølby's acquisition committee."
      ),
      event(
        "1996-1999",
        "New Clear Lake ambitions",
        ["cabin life"],
        "A Bathroom Subcommittee was charged with expanding and remodeling the bathrooms at CL. After ten different design schemes construction drawings were submitted for bidding. The plans incorporated a separate new structure complete with handicapped access and resistant to periodic flooding. At a cost of $106,000 it was decided that we might as well build a whole new cabin. Preliminary drawings for a 2-story structure were made for a presentation at our 50th anniversary. The Bathroom Subcommittee was disbanded in 1999."
      ),
      event(
        "1997",
        "Tahoe Cabin Master on the Board",
        ["club leadership"],
        "Andrew Vik, 24, becomes youngest president in YSC history. Changes made to the bylaws to include Tahoe Cabin Manager on the Executive Committee and the Board of Trustees at six full members (formerly five plus an alternate)."
      ),
      decade("2000s"),
      milestone(
        "2000",
        "YSC 50th Anniversary",
        ["anniversary"],
        nil,
        body_html:
          "On <strong>Saturday, October 7, 2000</strong>, YSC celebrates its 50th anniversary with a grand party at the <strong>Sir Francis Drake Hotel</strong>. Svend Svendsen serves as master of ceremonies; past presidents are introduced; and guest of honor <strong>Arnold Rolkert</strong>—the club's first president—flies in from Sweden to address the membership. The evening features a custom 50th anniversary song by Wenche Lier, Mogens Lauesen, and Knud Dyby, accordion music by Andy Nielsen, and dancing until 1:00 a.m."
      ),
      milestone(
        "2004",
        "Tahoe Cabin Mortgage Paid Off",
        ["cabin life", "anniversary"],
        "On April 8, 2004, the club pays off the remaining $83,908.56 balance on the Tahoe cabin mortgage—more than four years ahead of the 2008 balloon due date. Clear Lake and Tahoe are now owned debt-free, completing a dream that began with seasonal rentals nearly five decades earlier."
      ),
      event(
        "2005",
        "55th Anniversary Celebration",
        ["anniversary"],
        "On October 1, 2005, YSC celebrates its 55th anniversary with a dinner and party at the Swedish American Hall in San Francisco—featuring Scandinavian fare, a custom-labeled wine from Søren Bloch, kransekage by Carsten Johansen, and a program organized by Signe Vik, Thomas Nielsen, Per Madsen, and fellow volunteers."
      ),
      event(
        "2003",
        "New ski boat",
        ["cabin life"],
        "Clear Lake – Replaced 21 year old Ski Supreme with a brand new Moomba ski boat."
      ),
      event(
        "2007",
        "Clear Lake bathroom remodel",
        ["cabin life"],
        "Bathrooms finally remodeled according to 1982 scheme – move wall to add a toilet and a shower from men's to women's room, and installing two showers in men's room using existing plumbing. Purchase new gas stove, an electric double oven and a refrigerator for the pantry."
      ),
      decade("2010s"),
      event(
        "2014",
        "Sauna in Tahoe",
        ["cabin life"],
        "Tahoe Cabin – After a strong fundraising drive by the Tahoe committee, the John Rollings Memorial Sauna is inaugurated in November this year.",
        images: [
          %{
            src: "/images/history/ysc_tahoe_sauna_tiles.webp",
            alt: "John Rollings Memorial Sauna at Tahoe",
            caption: "John Rollings Memorial Sauna at Tahoe",
            era: "2010s",
            aspect: "4/3"
          }
        ]
      ),
      event(
        "2015",
        "65th Anniversary",
        ["anniversary"],
        "In September, YSC celebrates its 65th Anniversary with a grand black-tie party at the Maritime Museum in San Francisco.",
        images: [
          %{
            src: "/images/history/7_presidents_65th_anniversary.webp",
            alt: "Seven YSC presidents at the 65th Anniversary celebration",
            caption: "Seven YSC presidents at the 65th Anniversary celebration",
            era: "2010s",
            aspect: "4/3"
          }
        ]
      ),
      event(
        "2017",
        "Clear Lake flooded",
        ["cabin life"],
        "Clear Lake – After several dry years with many wildfires around the lake it is finally raining again. The Clear Lake cabin is again flooded with a foot of water on throughout the cabin."
      ),
      event(
        "2019",
        "Longest serving President",
        ["club leadership"],
        "With six consecutive years, Peter Nordström becomes the longest serving president of the YSC to date."
      ),
      decade("2020s"),
      event(
        "2020",
        "Covid-19 Pandemic",
        ["organization"],
        "Due to the COVID-19 pandemic, the YSC, (together with most of the world), has to freeze all operations and close our cabins."
      ),
      milestone(
        "2025",
        "75 Year Anniversary",
        ["anniversary"],
        "The YSC celebrates its 75th Anniversary with a grand party at the Swedish American Hall in San Francisco.",
        images: [
          %{
            src: "/images/history/ysc_75th_anniversary.webp",
            alt: "YSC 75th Anniversary celebration",
            caption: "YSC 75th Anniversary celebration",
            era: "2020s",
            aspect: "4/3"
          }
        ]
      ),
      event(
        "2026",
        "Peter Nordström Returns as President",
        ["club leadership"],
        "Peter Nordström returns as president of the club after coming back to the board in 2025 as an event coordinator, marking his return to leadership."
      ),
      event(
        "2026",
        "YSC Choir Founded",
        ["organization"],
        "The YSC Choir is launched as a welcoming community choir rooted in Scandinavian musical tradition—open to all members, with no auditions or prior choral experience required."
      )
    ]
  end

  @doc """
  Returns the rounded anniversary year count (e.g. 75 for 2025).
  """
  @spec years_since_founding() :: integer()
  def years_since_founding do
    div(Date.utc_today().year - 1950, 5) * 5
  end

  defp decade(label) do
    %{
      type: :decade,
      year: label,
      title: nil,
      tags: [],
      body: nil,
      body_html: nil,
      images: [],
      blockquote: nil,
      ledger: nil,
      extra_tags: []
    }
  end

  defp event(year, title, tags, body, opts \\ []) do
    %{
      type: :event,
      year: year,
      title: title,
      tags: tags,
      body: body,
      body_html: Keyword.get(opts, :body_html),
      images: Keyword.get(opts, :images, []),
      blockquote: nil,
      ledger: Keyword.get(opts, :ledger),
      extra_tags: []
    }
  end

  defp milestone(year, title, tags, body, opts \\ []) do
    %{
      type: :milestone,
      year: year,
      title: title,
      tags: tags,
      body: body,
      body_html: Keyword.get(opts, :body_html),
      images: Keyword.get(opts, :images, []),
      blockquote: nil,
      ledger: Keyword.get(opts, :ledger),
      extra_tags: []
    }
  end

  defp featured(year, title, tags, opts) do
    %{
      type: :featured,
      year: year,
      title: title,
      tags: tags,
      body: Keyword.get(opts, :body),
      body_html: nil,
      images: Keyword.get(opts, :images, []),
      blockquote: Keyword.get(opts, :blockquote),
      ledger: Keyword.get(opts, :ledger),
      extra_tags: Keyword.get(opts, :extra_tags, [])
    }
  end
end
