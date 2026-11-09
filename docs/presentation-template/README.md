# YSC presentation template

PowerPoint template for board, admin and member presentations, styled after the website.

| File | Use |
| --- | --- |
| `YSC-presentation-template.potx` | PowerPoint template. Double-click to start a new deck from it. |
| `YSC-presentation-template.pptx` | Same content as a regular deck. Use it to upload to Google Slides (Drive, then open with Google Slides) or to edit the master. |

## Layouts

- **Title**: photo cover, plus five solid-color versions, one per Nordic country.
- **Section** and **Statement**: five versions each, one per country.
- **Title and content**, **Title only**, **Two columns**, **Three columns**, **Image and text**.
- **Five columns**: one filled card per country color.
- **Process**: five numbered steps in the five country colors.
- **Chart and commentary**, **Closing**, **Blank**.

The sample slides in the file show how each layout is used and carry speaker notes. Delete them in your own decks.

## Nordic palette

All five countries get equal weight. Rotate through the Title, Section and Statement versions and use each color in turn for charts and highlights.

| Country | Colors |
| --- | --- |
| Denmark | `#C8102E` |
| Finland | `#002F6C` |
| Iceland | `#02529C`, `#DC1E35` |
| Norway | `#BA0C2F`, `#00205B` |
| Sweden | `#005293`, `#FECB00` |

These match the flag colors in `assets/tailwind.config.js`. Norway red (`#BA0C2F`) is not in the PowerPoint theme color picker because the theme has too few slots, so paste its hex code when you need it.

## Charts

Charts you insert with Insert, then Chart pick up the theme's series order automatically: Sweden blue, Denmark red, Sweden yellow, Finland blue. The Charts section of the sample deck shows the house style:

- Bar and pie charts by country use each country's color.
- Multi-series column and line charts use the theme series order.
- No chart title (the slide title does that), light gray gridlines, labels 11 pt or larger, four series at most.

## Icons

The "Icon library" slide has 32 icons (Heroicons, MIT license, the same set the website uses). Each is a theme-colored circle plus a symbol. Group the pair (right-click, Group), copy it and paste it into your slide. Circle colors are theme colors, so they follow the theme.

## Typeface

Arial, set once in the theme (Design, Variants, Fonts). The website uses the system font, and Arial is installed everywhere.
