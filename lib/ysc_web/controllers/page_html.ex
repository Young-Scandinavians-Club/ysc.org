defmodule YscWeb.PageHTML do
  use YscWeb, :html

  import Ysc.Text, only: [titleize: 1]
  import YscWeb.Components.History.HistoryComponents

  embed_templates "page_html/*"

  # General meetings shown on the financials page, newest first. `fy` is the
  # fiscal year reviewed at that meeting (the 2026 meeting reviews FY 2025).
  # Each document is `{kind, href, meta}`; the title comes from the kind.
  defp recent_meetings do
    [
      %{
        year: 2026,
        fy: 2025,
        docs: [
          {:summary,
           ~p"/annual_meetings/2026/YSC_ANNUAL_MEETING_REPORT_FY_2025.pdf",
           "PDF • 70K"},
          {:report, ~p"/annual_meetings/2026/YSC_ANNUAL_REPORT_FY_2025.pdf",
           "PDF • 107K"},
          {:minutes, ~p"/annual_meetings/2026/YSC_AGM_2026_meeting_minutes.pdf",
           "PDF • 104K"}
        ]
      },
      %{
        year: 2025,
        fy: 2024,
        docs: [
          {:summary,
           ~p"/annual_meetings/2025/annual_meeting_financials_2024_handout.pdf",
           "PDF • 70K"},
          {:report, ~p"/annual_meetings/2025/YSC_Annual_Report_2024.pdf",
           "PDF • 106K"},
          {:minutes,
           "/annual_meetings/2025/YSC_AGM%202025_meeting_minutes.docx",
           "DOCX • 51K"}
        ]
      },
      %{
        year: 2024,
        fy: 2023,
        docs: [
          {:summary,
           ~p"/annual_meetings/2024/YSC-Financials-2023-General-Meeting-Handout.pdf",
           "PDF • 57K"},
          {:report, ~p"/annual_meetings/2024/YSC-AGM-2025_final.pdf",
           "PDF • 158K"},
          {:minutes,
           "/annual_meetings/2024/YSC%20Annual%20General%20Meeting%2001.28.24.docx",
           "DOCX • 15K"}
        ]
      },
      %{
        year: 2023,
        fy: 2022,
        docs: [
          {:summary,
           ~p"/annual_meetings/2023/YSC-General-Meeting-Financials-Summary-2022.pdf",
           "PDF • 49K"},
          {:report, ~p"/annual_meetings/2023/YSC-Financials-2022.v2.pdf",
           "PDF • 717K"},
          {:minutes, ~p"/annual_meetings/2023/YSC-AGM-Minutes-02.27.22.pdf",
           "PDF • 90K"}
        ]
      }
    ]
  end

  defp archived_meetings do
    [
      %{
        year: 2022,
        fy: 2021,
        docs: [
          {:summary,
           ~p"/annual_meetings/2022/YSC-Financials-2021-General-Meeting-Overview.pdf",
           "PDF • 49K"},
          {:report, ~p"/annual_meetings/2022/YSC-Financials-2021-2.18.22.pdf",
           "PDF • 763K"}
        ]
      },
      %{
        year: 2021,
        fy: 2020,
        docs: [
          {:summary, ~p"/annual_meetings/2021/YSC-Annual-Meeting-2021.pdf",
           "PDF • 7.9M"},
          {:report, ~p"/annual_meetings/2021/YSC-Financials-2020-1.10.21.pdf",
           "PDF • 430K"},
          {:minutes,
           ~p"/annual_meetings/2021/YSC-Annual-Meeting-Minutes-022121.pdf",
           "PDF • 88K"}
        ]
      },
      %{
        year: 2020,
        fy: 2019,
        docs: [
          {:summary,
           ~p"/annual_meetings/2020/YSC-General-Meeting-Financials-2019-Summary-2.4.2020.pdf",
           "PDF • 79K"},
          {:report, ~p"/annual_meetings/2020/YSC-Financials-2019-2.4.2020.pdf",
           "PDF • 484K"}
        ]
      },
      %{
        year: 2019,
        fy: 2018,
        docs: [
          {:summary,
           ~p"/annual_meetings/2019/YSC-General-Meeting-Financials-Summary-2018-v02.07.19.pdf",
           "PDF • 74K"},
          {:report, ~p"/annual_meetings/2019/YSC-Financials-2018-v02.07.19.pdf",
           "PDF • 532K"}
        ]
      },
      %{
        year: 2018,
        fy: 2017,
        docs: [
          {:summary,
           ~p"/annual_meetings/2018/YSC-2017-financials-2018-02-14-CPA-approved.pdf",
           "PDF • 63K"},
          {:slides, ~p"/annual_meetings/2018/YSC-2017-financials.pptx",
           "PPTX • 284K"}
        ]
      }
    ]
  end

  defp doc_title(:summary, fy), do: "Financials Summary #{fy}"
  defp doc_title(:report, _fy), do: "Full Annual Report"
  defp doc_title(:minutes, _fy), do: "Meeting Minutes"
  defp doc_title(:slides, _fy), do: "Financials Presentation"
end
