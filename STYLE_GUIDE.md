# YSC Style Guide

Canonical design reference for the YSC web application. All UI changes must follow these rules.

## Typography

| Token | Size | Usage |
|-------|------|-------|
| `text-xs` | 12px | **Minimum allowed size.** Captions, badges, metadata |
| `text-sm` | 14px | Body text, form labels, table cells |
| `text-base` | 16px | Default prose, descriptions |
| `text-lg` | 18px | Section sub-headings |
| `text-xl`–`text-3xl` | 20–30px | Page headings, hero text |

**Banned tokens:** `text-[8px]`, `text-[9px]`, `text-[10px]` — these are unreadable for many users. Use `text-xs` (12px) as the minimum.

## Color System

### Neutrals — Zinc only

| Token | Hex | Usage |
|-------|-----|-------|
| `zinc-50` | #fafafa | Page backgrounds, subtle fills |
| `zinc-100` | #f4f4f5 | Card backgrounds, hover states |
| `zinc-200` | #e4e4e7 | Borders, dividers |
| `zinc-300` | #d4d4d8 | Disabled borders |
| `zinc-400` | #a1a1aa | Placeholder text, decorative separators |
| `zinc-500` | #71717a | Secondary text (minimum for contrast on light bg) |
| `zinc-600` | #52525b | Body text |
| `zinc-700` | #3f3f46 | Headings, strong labels |
| `zinc-800` | #27272a | Primary text |
| `zinc-900` | #18181b | High-emphasis text, dark backgrounds |

**Banned neutrals:** `gray-*`, `slate-*` — do not use. Convert to the closest `zinc-*` equivalent.

### Primary — Blue

| Token | Usage |
|-------|-------|
| `blue-400` | Focus rings (on dark bg) |
| `blue-500` | Primary buttons, links, focus rings |
| `blue-600` | Primary text, active states |

**Banned accent:** `indigo-*` — convert all `ring-indigo-*`, `border-indigo-*`, `text-indigo-*` to `blue-*`.

### Semantic Colors

- **Success:** `green-*` (badges, status indicators)
- **Warning:** `amber-*` / `yellow-*`
- **Danger:** `red-*` (destructive actions, error states)

## Contrast Requirements

Minimum contrast pairings (WCAG AA):

| Background | Minimum text color |
|---|---|
| `white` / `zinc-50` | `text-zinc-500` or darker |
| `zinc-100` | `text-zinc-500` or darker |
| `zinc-800` / `zinc-900` | `text-zinc-300` or lighter |

**Common violation:** `text-zinc-300` or `text-zinc-400` on light backgrounds — fix to `text-zinc-500`.

## Focus Indicators

Every interactive element must have a visible focus indicator:

```
focus:ring-2 focus:ring-blue-500
```

- Never use `focus:ring-0 focus:outline-none` without providing an alternative visible indicator.
- Form inputs: `focus:ring-2 focus:ring-blue-500 focus:border-blue-500`
- Buttons inherit focus from the button component.

## Cards

| Property | Value |
|----------|-------|
| Border radius | `rounded-xl` (default) or `rounded-2xl` (large feature cards) |
| Shadow | `shadow-sm` (default) or `shadow-md` (elevated) |
| Padding | `p-4` (compact) or `p-6` (standard) |

**Banned radius:** `rounded-3xl` — too round for cards. Use `rounded-2xl` max.

## Badges

```html
<span class="text-xs font-bold bg-zinc-800 text-white px-2 py-0.5 rounded">
  BADGE
</span>
```

- Minimum size: `text-xs`
- Border radius: `rounded` (not `rounded-full` for text badges)

## Buttons

- Primary: `bg-blue-500 hover:bg-blue-600 text-white rounded-xl`
- Secondary: `bg-zinc-100 hover:bg-zinc-200 text-zinc-700 rounded-xl`
- Danger: `bg-red-500 hover:bg-red-600 text-white rounded-xl`
- All buttons: `focus:ring-2 focus:ring-blue-500 focus:ring-offset-2`

## Spacing

Use Tailwind's default spacing scale. Prefer `gap-*` for flex/grid layouts over margin hacks.

| Context | Spacing |
|---------|---------|
| Between cards | `gap-4` or `gap-6` |
| Card internal | `p-4` or `p-6` |
| Section spacing | `mt-8` / `mb-8` or `space-y-8` |
| Inline elements | `gap-2` |
