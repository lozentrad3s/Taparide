---
name: Tap A Ride
description: Abuja Smart Mobility Platform. Fixed fares, published departures and verified vehicles, legible for riders, operators, fleet owners and the FCTA.
colors:
  forest: "#0B5A3A"
  forest-hover: "#0E6B45"
  forest-deep: "#06331F"
  leaf: "#4DB52A"
  leaf-text: "#237A2E"
  mint: "#E6F2EA"
  mint-strong: "#CDE6D5"
  ink: "#111814"
  ink-soft: "#34423A"
  muted: "#5B6B62"
  faint: "#8A9890"
  line: "#DDE6E0"
  line-strong: "#C6D3CA"
  ground: "#F2F6F3"
  surface: "#FFFFFF"
  surface-sunk: "#F7FAF8"
  on-forest-muted: "#B9D5C5"
  amber: "#8A5A00"
  amber-soft: "#FBF0D9"
  red: "#C0392B"
  red-soft: "#FBE5E2"
  blue: "#2861B8"
  blue-soft: "#E3ECF9"
typography:
  display-large:
    fontFamily: "Barlow, 'Fira Sans', sans-serif"
    fontSize: "64px"
    fontWeight: 800
    lineHeight: 0.96
    letterSpacing: "-1.6px"
  display-medium:
    fontFamily: "Barlow, 'Fira Sans', sans-serif"
    fontSize: "46px"
    fontWeight: 800
    lineHeight: 1.0
    letterSpacing: "-1px"
  display-small:
    fontFamily: "Barlow, 'Fira Sans', sans-serif"
    fontSize: "36px"
    fontWeight: 800
    lineHeight: 1.04
    letterSpacing: "-0.6px"
  headline-large:
    fontFamily: "Barlow, 'Fira Sans', sans-serif"
    fontSize: "30px"
    fontWeight: 700
    lineHeight: 1.1
    letterSpacing: "-0.4px"
  headline-medium:
    fontFamily: "Barlow, 'Fira Sans', sans-serif"
    fontSize: "25px"
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: "-0.2px"
  headline-small:
    fontFamily: "Barlow, 'Fira Sans', sans-serif"
    fontSize: "21px"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "normal"
  title-large:
    fontFamily: "Barlow, 'Fira Sans', sans-serif"
    fontSize: "18px"
    fontWeight: 700
    lineHeight: 1.25
    letterSpacing: "normal"
  title-medium:
    fontFamily: "Barlow, 'Fira Sans', sans-serif"
    fontSize: "16px"
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: "normal"
  title-small:
    fontFamily: "Barlow, 'Fira Sans', sans-serif"
    fontSize: "14px"
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: "normal"
  body-large:
    fontFamily: "Barlow, 'Fira Sans', sans-serif"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: "normal"
  body-medium:
    fontFamily: "Barlow, 'Fira Sans', sans-serif"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.45
    letterSpacing: "normal"
  body-small:
    fontFamily: "Barlow, 'Fira Sans', sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.4
    letterSpacing: "normal"
  label-large:
    fontFamily: "Barlow, 'Fira Sans', sans-serif"
    fontSize: "15px"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "normal"
  label-medium:
    fontFamily: "Barlow, 'Fira Sans', sans-serif"
    fontSize: "13px"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "normal"
  label-small:
    fontFamily: "Barlow, 'Fira Sans', sans-serif"
    fontSize: "12px"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "0.2px"
  figure:
    fontFamily: "Barlow, 'Fira Sans', sans-serif"
    fontSize: "26px"
    fontWeight: 800
    lineHeight: 1
    letterSpacing: "-0.4px"
    fontFeature: "tnum"
  figure-large:
    fontFamily: "Barlow, 'Fira Sans', sans-serif"
    fontSize: "32px"
    fontWeight: 800
    lineHeight: 1
    letterSpacing: "-0.4px"
    fontFeature: "tnum"
rounded:
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "22px"
  pill: "999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
  xxl: "32px"
components:
  button-primary:
    backgroundColor: "{colors.forest}"
    textColor: "{colors.surface}"
    typography: "{typography.label-large}"
    rounded: "{rounded.md}"
    padding: "14px 22px"
    height: "50px"
  button-primary-hover:
    backgroundColor: "{colors.forest-hover}"
  button-primary-disabled:
    backgroundColor: "{colors.line-strong}"
    textColor: "{colors.muted}"
  button-primary-large:
    backgroundColor: "{colors.forest}"
    textColor: "{colors.surface}"
    rounded: "{rounded.md}"
    height: "56px"
  button-outlined:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.label-large}"
    rounded: "{rounded.md}"
    padding: "14px 20px"
    height: "50px"
  button-danger:
    backgroundColor: "{colors.red}"
    textColor: "{colors.surface}"
    typography: "{typography.label-large}"
    rounded: "{rounded.md}"
    height: "50px"
  button-on-forest:
    backgroundColor: "{colors.leaf}"
    textColor: "{colors.forest-deep}"
    typography: "{typography.label-large}"
    rounded: "{rounded.md}"
    padding: "0 16px"
    height: "40px"
  button-text:
    textColor: "{colors.forest}"
    typography: "{typography.label-large}"
    rounded: "{rounded.md}"
    height: "44px"
  input:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.body-medium}"
    rounded: "{rounded.md}"
    padding: "16px"
  chip:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.label-medium}"
    rounded: "{rounded.sm}"
    padding: "8px 10px"
  chip-selected:
    backgroundColor: "{colors.forest}"
    textColor: "{colors.surface}"
  panel:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.lg}"
    padding: "16px"
  forest-field:
    backgroundColor: "{colors.forest}"
    textColor: "{colors.surface}"
    rounded: "{rounded.xl}"
    padding: "20px"
  status-pill-success:
    backgroundColor: "{colors.mint}"
    textColor: "{colors.leaf-text}"
    rounded: "{rounded.pill}"
    padding: "4px 9px"
  status-pill-warning:
    backgroundColor: "{colors.amber-soft}"
    textColor: "{colors.amber}"
    rounded: "{rounded.pill}"
    padding: "4px 9px"
  status-pill-danger:
    backgroundColor: "{colors.red-soft}"
    textColor: "{colors.red}"
    rounded: "{rounded.pill}"
    padding: "4px 9px"
  status-pill-info:
    backgroundColor: "{colors.blue-soft}"
    textColor: "{colors.blue}"
    rounded: "{rounded.pill}"
    padding: "4px 9px"
  status-pill-neutral:
    backgroundColor: "{colors.surface-sunk}"
    textColor: "{colors.muted}"
    rounded: "{rounded.pill}"
    padding: "4px 9px"
  status-pill-brand:
    backgroundColor: "{colors.forest}"
    textColor: "{colors.surface}"
    rounded: "{rounded.pill}"
    padding: "4px 9px"
  icon-badge:
    backgroundColor: "{colors.mint}"
    textColor: "{colors.forest}"
    rounded: "{rounded.md}"
    size: "44px"
  nav-bar:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.muted}"
    typography: "{typography.label-small}"
    height: "68px"
  nav-bar-indicator:
    backgroundColor: "{colors.mint}"
    textColor: "{colors.forest}"
  portal-sidebar:
    backgroundColor: "{colors.forest-deep}"
    textColor: "{colors.on-forest-muted}"
    width: "260px"
  rider-rail:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink-soft}"
    width: "232px"
  rider-rail-item-selected:
    backgroundColor: "{colors.mint}"
    textColor: "{colors.forest}"
    rounded: "{rounded.md}"
    padding: "13px 14px"
  snackbar:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.surface}"
    typography: "{typography.body-medium}"
    rounded: "{rounded.md}"
  tooltip:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.surface}"
    typography: "{typography.label-small}"
    rounded: "{rounded.sm}"
  dialog:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.xl}"
---

# Design System: Tap A Ride

## Overview

**Creative North Star: "The Published Route Board"**

Tap A Ride is drawn like a well-run terminal's departure board, printed in the logo's own greens. Every route on it carries three facts: a fixed fare, a published departure and a verified vehicle. The interface exists to make those facts readable at a glance, on a mid-range Android phone in Abuja sunlight as much as on an FCTA desktop. The palette comes straight from the logo. A deep forest green does the acting, a bright pin green is kept for signals, and every neutral is tinted with the same green, so even the greys belong to the brand. Barlow, a typeface descended from road-sign lettering, carries every word.

Density follows the job. The landing page persuades: heavy Barlow 800 headlines, real photographs of Abuja and generous white space around a single floating "next departure" card. The rider app and partner portal operate: white bordered cards on a pale green-grey ground, compact rows, tabular fares and honest status pills. The same objects travel across all three surfaces. A booking made in the rider app reappears in operator, fleet and FCTA views, and it is always drawn with the same transit-map route line, the same pill tones and the same forest field for headline numbers.

The system is calm, factual and flat-leaning. Depth is a whisper: hairline borders plus a soft green-tinted shadow. Colour is meaning: forest means act, pin green means signal, amber means pending or demo, red means danger. Photography is real, openly licensed and credited. Nothing in the world is illustrated, generated or stock.

**Key Characteristics:**
- Forest green actions and fields on white cards over a pale green-grey ground.
- One typeface (Barlow), with hierarchy from weight: 800 display, 700 headline and title, 600 label, 400 body.
- The transit-map route line (hollow origin, small stops, solid destination) wherever a trip is named.
- Tabular, heavy fares and figures; money is always the boldest thing on a row.
- Green-tinted neutrals, shadows and photo scrims; no pure grey or black.
- Real, credited Abuja photography at large radii.
- Demo data is always visibly flagged.

## Colors

The palette is one green family taken from the Tap A Ride logo, with a small, strictly semantic set of status tones beside it.

### Primary
- **Abuja Forest** (#0B5A3A): the action colour. Filled buttons, selected chips and segmented controls, departure-time selection, text links, focus borders, the cursor, progress indicators, the route line on light surfaces, the map polyline, and the brand field on the landing "Everyone connected" band. Contrast with white is 8.3:1, so white text sits on it at any size.
- **Forest Lift** (#0E6B45): hover state of the primary button and the light end of the forest-field gradient on the Tap Card and headline figure panels.
- **Night Forest** (#06331F): the portal sidebar, the portal phone app bar and drawer, the landing footer, the dark end of forest-field gradients, and the base of every photo scrim.
- **Mint Wash** (#E6F2EA): forest tint for selected navigation indicators, icon badges, avatars, empty-state discs, the success pill background, photo fallbacks and the progress track.
- **Mint Bar** (#CDE6D5): the non-highlighted bars in ridership charts and the text-selection colour.

### Secondary
- **Pin Green** (#4DB52A): the logo's bright map-pin green, a signal. It draws the route line on forest fields, the selected Tap Card ring, the active portal sidebar icon, the portal user avatar, check bullets, the verified and active shares of share bars and their legend dots, snackbar success icons and snackbar action text. On a forest field it may also fill a secondary action with a Night Forest label (5.3:1). It is 2.6:1 on white, so it is never text on a light surface.
- **Readable Leaf** (#237A2E): the green that can be read. Success pill text, positive deltas and live-mode badge text on mint or white.

### Tertiary
- **Pending Amber** (#8A5A00) on **Amber Wash** (#FBF0D9): pending verification, requested bookings, late departures, maintenance, and the "Demo data" badge.
- **Signal Red** (#C0392B) on **Red Wash** (#FBE5E2): suspended, cancelled, declined, inactive, negative deltas, input errors, and the emergency action.
- **Transit Blue** (#2861B8) on **Blue Wash** (#E3ECF9): in-motion information such as boarding, on trip and charging, plus the battery legend.

### Neutral
- **Green Ink** (#111814): headlines, titles, fares, QR modules, and the snackbar and tooltip fields. Near-black with the forest hue, never #000.
- **Soft Ink** (#34423A): body copy, unselected segmented labels, rail labels, and the header of a closed (past or cancelled) ticket.
- **Sage Muted** (#5B6B62): secondary text, captions, hints, labels above figures, unselected navigation. 5.2:1 on the ground.
- **Faint Sage** (#8A9890): chevrons and the route line of a closed booking. Graphics only, never running text.
- **Hairline** (#DDE6E0): card borders and dividers.
- **Strong Hairline** (#C6D3CA): input, outlined-button and chip strokes, vertical dividers in the feature strip, scrollbar thumbs, ticket perforation dashes and disabled fills.
- **Pale Green Ground** (#F2F6F3): the canvas of the rider app and portal, the app bar, the landing feature strip and step tiles.
- **Card White** (#FFFFFF): cards, inputs, dialogs, sheets, the navigation bar and the landing page canvas.
- **Sunk White** (#F7FAF8): table header rows, neutral pills and disabled chips.
- **Forest Mist** (#B9D5C5): secondary text and labels on forest and night-forest fields. 5.3:1 on forest.

### Named Rules
**The Forest Acts Rule.** Forest is the colour that means "do this". On light surfaces every filled action, selection and focus state is forest. The one exception is a destructive confirmation (cancel booking, suspend provider), which fills Signal Red.

**The Pin Green Is a Signal Rule.** On light surfaces pin green marks and never carries words or fills an action. When green text is needed on white or mint, it is Readable Leaf. Pin green fills a button only on a forest field.

**The Green-Tinted Neutrals Rule.** Every neutral, shadow and photo scrim carries the forest hue. Ink is #111814, shadows are rgba(11,42,26,…), scrims are night forest at varying alpha. A pure grey or pure black is off-world.

**The Honest Tone Rule.** Status colour maps to meaning and nothing else: success for verified, on time and confirmed; amber for pending, requested, late and demo; red for suspended and cancelled; blue for boarding, on trip and charging; neutral for completed. Demo figures always carry the amber "Demo data" badge.

## Typography

**Display Font:** Barlow (with Fira Sans, sans-serif)
**Body Font:** Barlow (with Fira Sans, sans-serif)
**Label/Mono Font:** Barlow; Fira Sans 400/700 is bundled only to supply the ₦ sign, which Barlow lacks.

**Character:** A single grotesque descended from road-sign lettering, set heavy and tight at display sizes and plain at body sizes. It reads as civic signage rather than a startup voice, and it keeps fares, times and plates legible at small sizes outdoors.

### Hierarchy
- **Display** (800, 64px / 46px / 36px, line-height 0.96–1.04, tracking −1.6px to −0.6px): landing headlines only. Large on wide screens, medium on phones and on the closing photo band, small for landing section titles.
- **Headline** (700, 30px / 25px / 21px, line-height 1.1–1.2): portal page titles (30px wide, 25px phone), the Tap Card balance, feature titles, sheet and dialog titles (21px).
- **Title** (700 at 18px, 600 at 16px and 14px, line-height 1.25–1.3): section and panel titles (18px), route names in a RouteStrip (bumped to 700), list-row titles and the app-bar title.
- **Body** (400, 17px / 15px / 13px, line-height 1.5 / 1.45 / 1.4): 17px for landing lead copy (max 480–640px wide), 15px for general copy, 13px muted for captions, meta lines and table subtitles.
- **Label** (600, 15px / 13px / 12px, line-height 1.2; 12px tracked 0.2px): button text (15px), field labels, chip labels, quick-action captions and nav labels (12px, 700 when selected). Table column headers are 12px uppercase tracked 0.6px.
- **Figure** (800, 26px, or 32px on forest fields, line-height 1, tabular): dashboard numbers. Labels above sit at 13/600 muted.

### Named Rules
**The Road-Sign Rule.** One family for everything, from the 64px hero to a table cell. Hierarchy comes from weight and size, never from a second typeface.

**The Tabular Money Rule.** Fares, balances, counts, times and ticket codes use tabular figures. A fare on a row is the heaviest text on that row (800).

## Layout

The rider app and portal sit on the pale green ground with white cards; the landing page sits on white, with the ground used for a banded feature strip and the step tiles.

- **Containers:** landing content max 1240px with 32px gutters wide and 18px on phones; portal content max 1320px with 32px gutters wide and 16px on phones; rider pages max 1180px with 20px gutters; focused flows (ticket, forms) max 520px with 18px gutters.
- **Breakpoints:** 420px shows the chevron on route rows; 760px switches data lists from stacked cards to a table; 900px switches the rider app from a bottom bar to a 232px side rail; 980px puts the landing page into two columns; 1024px gives the portal its fixed 260px night-forest sidebar.
- **Grid:** dashboards lay figures and panels in equal-height responsive columns (minimum 240px per column, 14px gap, at most four), so a row of cards always shares one height. The landing hero splits copy and photograph roughly 10:13 with a 40px gap; the forest band splits intro and role tiles 9:13.
- **Rhythm:** a 4px base. Card internals run 14–20px padding (16px default), with 10–14px gaps between rows. Portal page titles sit 22px above the first row of content. Landing sections breathe at 84–96px vertical padding wide and 52–56px on phones.
- **Density:** comfortable for riders (42–56px icon tiles, 48px minimum touch targets, 50px buttons), compact for partners (36px minimum table rows, 13px meta lines).

## Elevation & Depth

Depth is a hybrid of hairlines and one soft, green-tinted shadow. White cards are lifted just enough to separate from the ground; forest fields are flat. A stronger raised shadow exists only for an element floating over a photograph.

### Shadow Vocabulary
- **Card** (`box-shadow: 0 6px 18px rgba(11,42,26,0.06), 0 1px 3px rgba(11,42,26,0.04)`): every panel by default, quick-action tiles, and the "Every vehicle verified" pill on the hero photograph.
- **Raised** (`box-shadow: 0 14px 32px rgba(11,42,26,0.12), 0 2px 6px rgba(11,42,26,0.06)`): the floating next-departure card over the hero photograph.

### Named Rules
**The Bordered Lift Rule.** A white card gets a 1px hairline border and the card shadow together. A card sitting inside another card, such as the route rows inside a landing step tile, drops the shadow and keeps the border.

**The Flat Field Rule.** Forest and night-forest fields never cast a shadow. Their weight comes from colour alone.

## Shapes

Corners are gently rounded on a four-step ladder with a pill for status. Small controls take 8px (chips, departure-time chips, tooltips). Buttons, inputs, navigation items, icon badges and snackbars take 12px. Cards and panels take 16px. Feature fields take 22px: the Tap Card, forest figure panels, tickets, step tiles, photo tiles, dialogs and the top of bottom sheets. Status pills and the demo badge are fully round. The hero photograph rounds to 28px. Circles are reserved for stops, avatars, step numbers, empty-state discs and role icons. Chart bars round only their top corners (5px).

## Components

### Buttons
Solid, square-shouldered and unmistakable.
- **Shape:** gently rounded (12px), 50px tall, 48px minimum width.
- **Primary:** forest fill, white 15px/600 label, 14px × 22px padding, no elevation. Landing hero and closing CTAs grow to 56px tall with a 16px bold label and a trailing arrow.
- **Hover / Focus:** fill steps to Forest Lift on hover; Material ink sparkle on press. Disabled is a strong-hairline fill with muted text.
- **Outlined (secondary):** white with a 1px strong-hairline stroke and ink label, same height and radius. Used for "Partner portal", "Share trip", "Top up card".
- **Text:** forest label, 44px tall, for "View all", "Log in" and section actions; it shares the section title's baseline.
- **Destructive:** in confirmation dialogs the confirming action fills Signal Red with a white label, beside a text-button "Keep it". The emergency action on a ticket is an outlined button with a red label and a red-wash stroke.
- **On a forest field:** a compact 40px pin-green button with a Night Forest label.
- **On a photo scrim:** the primary inverts to a white fill with a forest label.

### Chips
- **Choice chips:** white with a strong-hairline stroke, 8px radius, 8px × 10px padding, 13px/600 label; selected turns forest with a white label and white check.
- **Departure-time and amount chips:** choice chips whose label is a time or a naira amount, set at 700 with tabular figures. Departure times drop the checkmark; the forest fill alone marks the chosen departure.
- **Segmented controls:** forest when selected, white with soft-ink text otherwise, 46px tall.

### Cards / Containers
- **Corner Style:** 16px for panels, 22px for feature fields.
- **Background:** Card White on the Pale Green Ground.
- **Shadow Strategy:** the Card shadow plus a hairline border (see Elevation & Depth).
- **Border:** 1px Hairline.
- **Internal Padding:** 16px default; 14px for route and booking rows; 18px for figure cards and the departure card; 20px for forest fields and step tiles.
- **Tappable cards:** the whole card is the target, with an ink ripple clipped to its shape.

### Inputs / Fields
- **Style:** filled white, 1px strong-hairline stroke, 12px radius, 16px padding, 15px body text, muted hint and label, muted prefix and suffix icons.
- **Focus:** stroke becomes forest at 1.8px; the floating label becomes 13px/600 forest.
- **Error / Disabled:** stroke turns red (1.8px when focused), with 13px red helper text beneath.

### Navigation
- **Rider, phone:** a 68px white bottom bar with Home, Routes, My Trips and Profile. Unselected items are outlined icons and 12px/600 muted labels; the selected item swaps to a filled icon in forest on a mint pill indicator with a 12px/700 forest label.
- **Rider, wide (≥900px):** a 232px white rail with a hairline right edge, the brand lockup on top, 15px items with a mint selected fill and forest text, and the demo badge at the foot.
- **Portal, wide (≥1024px):** a 260px night-forest sidebar. White lockup, then the signed-in user on a faint white card with a pin-green avatar, then the role's sections as 15px items with Forest Mist icons. The selected item gets a white 12% fill, a white 700 label and a pin-green icon. The demo badge and sign-out sit at the foot.
- **Portal, phone:** a night-forest app bar with the white lockup, a bottom bar with the role's first three sections plus "More" (opens a bottom sheet list), and a night-forest drawer.
- **Landing:** lockup with descriptor at left, 15px/600 soft-ink text links, a "Log in" text button and a primary "Get Started". On phones the links collapse into a bottom-sheet menu.

### Status Pills
Fully round, 4px × 9px padding, 12px/700 text, optional 13px leading icon, colours per the Honest Tone Rule. The **Demo data** badge is an amber-wash pill with a flask icon (white 12% on dark fields); with a live backend it becomes a mint "live" pill.

### Route Line (signature)
The transit-map line that draws every trip. A 3px forest stroke with round caps joins a hollow origin stop (6px radius, white centre, 2.6px ring), small intermediate stops (3.6px radius, white centre, 2px ring) and a solid destination (6px radius disc with a white centre at 38%). In a **RouteStrip** it sits between the origin and destination names (64px wide, 40–56px dense, 2–4 stops), with names in 16px/700 (14px dense). Forest on light surfaces, pin green on forest fields, faint sage for closed bookings. It runs vertically down the route-details stop list, grows into bar lengths (4px stroke, 700ms) for the FCTA top routes, and becomes a 6px forest polyline with a white casing on the map, where the destination becomes a forest pin.

### Forest Field
The brand's dark green surface for the most important numbers and objects: portal headline figures, the Tap Card, the rider's upcoming-trip card, ticket headers and the landing "Everyone connected" band. It runs a diagonal Forest Lift to Night Forest gradient (or flat forest for bands and cards), at 22px radius, with white values, Forest Mist labels and pin-green accents. Figures inside are divided by 20% white vertical rules. No shadow.

### Ticket
A forest header holding the trip kind, status pill, a pin-green RouteStrip and facts (departs, seat, fare). It joins a white body through an 18px perforation: ground-coloured 11px notches at both edges and a 6px-on, 6px-off dashed strong-hairline line. The body shows a square-module ink QR code and the ticket code in 18px tabular type tracked 2px. Closed tickets swap the header to Soft Ink.

### Figures and Charts
- **Figure:** 13px/600 label (with an optional 16px forest icon), a 26px/800 tabular value (32px on forest fields), then a delta arrow in Readable Leaf or red at 13px/700 with a 12px caption.
- **Week bars:** seven Mint Bar columns with 5px top radii; today is forest with a bold ink day label; values sit above in 11px/700 tabular. Bars grow with a 50ms stagger.
- **Share bar:** a 10px rounded bar split by status colour, with circular legend dots and tabular values.

### Data List
At 760px and above, a table inside a panel: a Sunk White header row of uppercase 12px labels, hairline row dividers, 36px minimum rows and right-aligned numeric columns. Below 760px each record becomes its own 14px-padded card, with a 110px label column.

### Empty and Loading States
A 64px mint disc with a 30px forest icon, an 18px title, 15px body capped at 360px, and an optional primary action. Load failures use the same layout with a "Try again" action. Loading is a 28px forest circular indicator, centred.

### Photography
Real, openly licensed Abuja photographs (light rail, City Gate, BRT at Berger, painted taxis, expressways, EVs), each credited on the in-app credits page. Photos are cropped with `cover`, rounded at 22–28px, fade in over 320ms, and sit under night-forest scrims wherever text overlaps them. If an image fails to load, a mint field with a forest landscape icon takes its place.

### Brand Lockup
The client's car-and-pin mark beside the "TAP A RIDE" wordmark, both as supplied artwork. The wordmark is 56% of the mark's height, with a 600-weight "Abuja Smart Mobility Platform" descriptor on the landing header. White artwork is used on forest fields. The full stacked logo with "Ride • Connect • Go" appears only on the forest band.

## Do's and Don'ts

### Do:
- **Do** draw every origin-to-destination pair with the RouteStrip and its route line, with the hollow origin, small stops and solid destination.
- **Do** show the fare and the next departure on every route card, with the fare in 800-weight tabular figures.
- **Do** reserve forest (#0B5A3A) for actions, selections and focus, use Forest Lift (#0E6B45) for hover, and fill only destructive confirmations with Signal Red (#C0392B).
- **Do** put pin green (#4DB52A) on forest fields as the route line, accent and occasional compact button, and use Readable Leaf (#237A2E) whenever green has to be read on a light surface.
- **Do** pair the hairline border with the card shadow on every white card on the ground.
- **Do** flag every demo figure with the amber "Demo data" badge.
- **Do** lay night-forest scrims over photographs that carry text, and credit every photograph.
- **Do** keep touch targets at 48px or more and buttons at 50px tall.
- **Do** let the landing hero rise in on a 28px ease-out and settle instantly when the system asks for reduced motion.

### Don't:
- **Don't** set pin green as text on white or mint, or fill a button with it on a light surface.
- **Don't** introduce a second typeface; Fira Sans exists only for the ₦ glyph.
- **Don't** use pure greys, pure black, or black-based shadows and scrims; tint them with the forest hue.
- **Don't** use stock, illustrated or AI-generated imagery; the world is real, credited photographs of Abuja.
- **Don't** recolour status tones for decoration; amber, red and blue appear only when they carry their meaning.
- **Don't** re-typeset the "TAP A RIDE" wordmark; use the supplied artwork.
- **Don't** add a shadow to a forest field.
