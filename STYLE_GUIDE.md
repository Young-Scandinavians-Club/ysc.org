# YSC Style Guide

Canonical design reference for the YSC web application. All UI changes must follow these rules.

---

## Typography

### Font stack

**Sans (UI, forms, tables, navigation — everything by default):**

```
system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif
```

Renders as the OS native sans: SF Pro on Apple, Segoe UI on Windows, Roboto on Android/Linux. Zero latency, no FOUT, tuned for legibility on each platform.

**Serif (optional, long-form editorial prose only):**

```
"Source Serif 4", Georgia, "Times New Roman", serif
```

Use only with `font-serif` on multi-paragraph reading blocks (articles, long descriptions). Do **not** use globally. Do **not** mix more than two families on the same page.

**Banned:** do not import or reference `Inter`, custom web fonts, or Google Fonts unless explicitly approved. The system stack is intentional.

---

### Size scale

| Token                 | Size    | Usage                                                                                    |
| --------------------- | ------- | ---------------------------------------------------------------------------------------- |
| `text-xs`             | 12px    | Badge overlays, map markers, decorative labels with tight space constraints              |
| `text-sm`             | 14px    | Navigation, form labels, metadata, captions, dense table cells, sub-labels              |
| `text-base`           | 16px    | **Minimum for primary prose.** Card descriptions, booking flows, settings copy, legal text |
| `text-lg`             | 18px    | Section sub-headings                                                                     |
| `text-xl`–`text-3xl`  | 20–30px | Section headings, stats                                                                  |
| `text-4xl`–`text-9xl` | 36px+   | Page heroes (responsive scale)                                                           |

**Banned tokens:** `text-[8px]`, `text-[9px]`, `text-[10px]` — unreadable. Use `text-xs` (12px) minimum.

**Weight conventions:**

- `font-black` — event/news card titles, dates, badge pills, hero headlines
- `font-bold` — CTA buttons, section headings
- `font-semibold` — component buttons, labels, column headers
- `font-medium` — table cells, list items, secondary labels
- `font-normal` — paragraph body text; **avoid `font-light` on paragraph body** — too thin for the full age range of members

**Line spacing:** use `leading-relaxed` on all multi-line prose. Hero display text may use tighter leading, but should not use `tracking-tighter` on body-level copy.

---

## Color System

### Neutrals — Zinc only

| Token      | Hex     | Usage                                             |
| ---------- | ------- | ------------------------------------------------- |
| `zinc-50`  | #fafafa | Page backgrounds, subtle alternate fills          |
| `zinc-100` | #f4f4f5 | Card backgrounds, default borders, hover fills    |
| `zinc-200` | #e4e4e7 | Borders on hover, dividers                        |
| `zinc-300` | #d4d4d8 | Disabled / muted borders                          |
| `zinc-400` | #a1a1aa | Placeholder text, decorative separators           |
| `zinc-500` | #71717a | Secondary text — **minimum on light backgrounds** |
| `zinc-600` | #52525b | Body text, icons                                  |
| `zinc-700` | #3f3f46 | Headings, strong labels                           |
| `zinc-800` | #27272a | Primary dark text, dark card backgrounds          |
| `zinc-900` | #18181b | High-emphasis text, dark section backgrounds      |

**Banned neutrals:** `gray-*`, `slate-*` — convert to nearest `zinc-*`.

### Primary — Blue

| Token      | Usage                                                    |
| ---------- | -------------------------------------------------------- |
| `blue-50`  | Info badge backgrounds, CTA button hover fill            |
| `blue-100` | Icon containers                                          |
| `blue-300` | Interactive text on **dark** backgrounds (links, labels) |
| `blue-600` | Primary buttons, links, active states, focus rings       |
| `blue-700` | Primary button base                                      |
| `blue-800` | Button hover                                             |

**Rule:** Use `text-blue-600` on light backgrounds. Use `text-blue-300` on dark backgrounds (`zinc-800`, `zinc-900`) for sufficient contrast.

**Banned accent:** `indigo-*` — convert `ring-indigo-*`, `border-indigo-*`, `text-indigo-*` to `blue-*`.

### Semantic Colors

| Intent  | Colors                 | Notes                                         |
| ------- | ---------------------- | --------------------------------------------- |
| Success | `green-*`, `emerald-*` | Badges, status indicators, confirmations      |
| Warning | `amber-*`, `orange-*`  | Selling-fast alerts, demand notices           |
| Danger  | `red-*`                | Destructive actions, errors, cancelled events |
| Info    | `sky-*`                | Countdown badges                              |
| Forms   | `rose-*`               | Validation error text                         |

---

## Contrast Requirements (WCAG AA)

| Background                       | Minimum text               |
| -------------------------------- | -------------------------- |
| `white` / `zinc-50` / `zinc-100` | `text-zinc-500` or darker  |
| `zinc-800` / `zinc-900`          | `text-zinc-300` or lighter |

**Common violations to avoid:**

- `text-zinc-400` on light backgrounds — use `text-zinc-500`
- `text-blue-400` on dark backgrounds — use `text-blue-300`
- `text-zinc-400` on dark backgrounds — use `text-zinc-300`

---

## Border Radii

Use the four-tier system. Each tier maps to a specific element category:

| Token          | px   | Category                       | Examples                                                                 |
| -------------- | ---- | ------------------------------ | ------------------------------------------------------------------------ |
| `rounded`      | 4px  | **Controls**                   | Inputs, selects, textareas, checkboxes, small badges, tag pills          |
| `rounded-md`   | 6px  | **Interactive buttons / tabs** | Hero CTAs, tab/pill buttons, small icon wrappers inside colored sections |
| `rounded-xl`   | 12px | **Cards and panels**           | Content cards, callout boxes, info panels, modal dialogs, notices        |
| `rounded-2xl`  | 16px | **Large feature elements**     | Bento grid cards, large image containers, hero feature blocks            |
| `rounded-full` | 50%  | **Circular elements**          | Avatars, section eyebrow pills, toggle tracks, icon buttons              |

**Banned:** `rounded-3xl` — too round for UI elements. Use `rounded-2xl` maximum for non-circular items.

**Banned:** `rounded-lg` — replaced. Map all legacy `rounded-lg` usages to one of the four tiers above based on element type.

---

## Shadows

Shadows signal elevation. Use sparingly — most content lives on a flat surface.

| Token        | Usage                                                                |
| ------------ | -------------------------------------------------------------------- |
| `shadow-sm`  | Content cards, form inputs, subtle depth on hover                    |
| `shadow-md`  | Modal close button, OTP input group                                  |
| `shadow-lg`  | Modal dialogs (functional elevation), dropdowns, navigation drawer   |
| `shadow-2xl` | Fixed mobile bottom bars (sticky chrome that must sit above content) |

**Rules:**

- **Never** use `shadow-xl` on content cards or sections.
- **Never** use colored shadows (e.g. `shadow-blue-200`, `shadow-zinc-900/20`).
- Cards default to no shadow; use `border border-zinc-100` for definition instead.
- Hover state may add `hover:shadow-sm` to give subtle lift on feature cards.

---

## Focus Indicators

Every interactive element must have a visible focus ring.

**Standard (light background):**

```
focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-600 focus-visible:ring-offset-2
```

**On dark background:**

```
focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white focus-visible:ring-offset-2 focus-visible:ring-offset-transparent
```

**Form inputs:**

```
focus:border-blue-600 focus:ring-blue-600
```

- Never use `focus:ring-0 focus:outline-none` without providing an alternative visible indicator.
- Buttons inherit focus from the `<.button>` core component (including link-style usage via `navigate`, `patch`, or `href`).
- Minimum touch target: `min-h-[44px]` on all interactive elements (mobile).

---

## Buttons

Buttons are defined in `core_components.ex`. Always use `<.button>`. For LiveView links that look like buttons, pass `navigate`, `patch`, or `href` to the same component. Use `phx-disable-with` or `loading_text` with LiveView actions so the built-in spinner and loading label appear while the request is in flight (the real `phx-disable-with` attribute is not forwarded; the label is used for the loading row only).

**Base classes (applied automatically):**

```
rounded py-2 px-3 text-sm font-semibold leading-6
transition duration-150 ease-in-out
disabled:cursor-not-allowed disabled:opacity-80
focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-600 focus-visible:ring-offset-2
```

**Solid variants** (add to `class=` when needed):

- Primary: `bg-blue-700 hover:bg-blue-800 text-zinc-100 active:scale-[0.98] active:transition-none`
- Danger: `bg-red-700 hover:bg-red-800 text-zinc-100 active:scale-[0.98] active:transition-none`
- Neutral: `bg-zinc-700 hover:bg-zinc-800 text-zinc-100 active:scale-[0.98] active:transition-none`

**Outline variants:**

- `border border-blue-200 hover:bg-blue-50 text-blue-700 bg-transparent`

**Hero / custom CTA buttons** (outside core component):

- Border radius: `rounded-md`
- On dark bg: `ring-white` focus ring with `ring-offset-transparent`
- Minimum height: `min-h-[48px]`

---

## Cards

### Standard content card

```
bg-white rounded-xl border border-zinc-100
```

Hover (border shift only, no shadow escalation):

```
hover:border-zinc-200 transition-colors duration-150
```

### Feature / bento card

```
bg-white rounded-2xl border border-zinc-100
hover:border-zinc-200 transition-colors duration-200
```

### Actionable card (clickable, acts like a button)

```
bg-white p-6 rounded-xl border border-zinc-200
hover:bg-zinc-50 hover:border-zinc-300 hover:shadow-sm
active:scale-[0.98] active:transition-none
transition-all duration-150
```

### Card padding

| Context  | Padding         |
| -------- | --------------- |
| Compact  | `p-4`           |
| Standard | `p-6`           |
| Spacious | `p-8` or `p-10` |

---

## Images

**Zoom on hover:**

```
overflow-hidden  →  image inside: group-hover:scale-[1.03] transition-transform duration-500
```

Use `scale-[1.03]` universally. Do **not** use `scale-105` or `scale-110` — too aggressive.

**Aspect ratio:** Use `object-cover` with a fixed height or `aspect-*` class. Never let images stretch.

**Past/muted events:**

```
opacity-80 hover:opacity-100 transition-opacity duration-300
```

---

## Badges

### Core `<.badge>` component

```html
<.badge>Text</.badge>
<.badge type="red">Danger</.badge>
```

Rendered as: `text-xs font-medium px-2 py-1 rounded bg-{color}-100 text-{color}-800`

### Inline status pill (card overlay / standalone)

```html
<span
  class="px-3 py-1.5 rounded text-xs font-black uppercase tracking-widest bg-zinc-800 text-white"
>
  LABEL
</span>
```

### Section eyebrow / label pill

```html
<span
  class="text-sm font-bold px-3 py-1 rounded-full bg-blue-50 text-blue-600 uppercase tracking-widest"
>
  Section Name
</span>
```

**Rules:**

- Minimum size: `text-xs`
- Badge border radius: `rounded` (short text pill) or `rounded-full` (eyebrow / section labels)
- Never `rounded-lg` for badges

---

## Transitions

| Duration       | Use                                                                   |
| -------------- | --------------------------------------------------------------------- |
| `duration-150` | **Default.** Buttons, card borders, color changes, interactive states |
| `duration-300` | Opacity changes, mobile menu, multi-step reveals                      |
| `duration-500` | Image scale transforms (`group-hover:scale-[1.03]`)                   |

**Easing:**

- `ease-in-out` — buttons and form controls
- `ease-out` — show/enter transitions
- `ease-in` — hide/leave transitions

Avoid `duration-200`, `duration-400`, `duration-700` — non-standard, replaced with closest standard value.

---

## Spacing

Use Tailwind's default spacing scale. Prefer `gap-*` for flex/grid layouts over margin stacking.

| Context                    | Spacing                             |
| -------------------------- | ----------------------------------- |
| Between cards in a grid    | `gap-4` or `gap-6`                  |
| Card internal padding      | `p-4` (compact) or `p-6` (standard) |
| Section vertical spacing   | `space-y-8` or `mb-8 / mt-8`        |
| Inline element gaps        | `gap-2`                             |
| Section-to-section on page | `py-16` or `py-24`                  |

---

## Hover Pattern Summary

| Element                | Hover effect                                                                                     |
| ---------------------- | ------------------------------------------------------------------------------------------------ |
| Content card           | Border color: `zinc-100 → zinc-200`                                                              |
| Actionable card        | Background: `white → zinc-50` + border: `zinc-200 → zinc-300` + `shadow-sm`                      |
| Card image             | Scale: `group-hover:scale-[1.03]`                                                                |
| Card title / link text | `group-hover:underline`                                                                          |
| Arrow icon in card     | `group-hover:translate-x-1`                                                                      |
| Inline link            | `hover:underline` or `hover:text-blue-600`                                                       |
| Footer link            | `hover:text-zinc-100 underline underline-offset-4 decoration-zinc-400 hover:decoration-zinc-200` |
| Button (solid)         | Darker shade (`-800`)                                                                            |
| Button (outline)       | Light fill (`-50`)                                                                               |

---

## Accessibility Checklist

- `text-base` (16px) minimum for all primary prose (booking flows, descriptions, settings, legal text)
- `text-sm` for navigation, labels, metadata, and dense UI elements
- `text-xs` only for badge overlays, map markers, and space-constrained decorative elements
- `min-h-[44px]` minimum touch target for all interactive elements
- Every interactive element has a `focus-visible:ring-2` ring
- Sufficient contrast: `zinc-500+` on light bg, `zinc-300+` on dark bg
- `blue-600` on light; `blue-300` on dark for interactive text
- Image alt text on all meaningful images
