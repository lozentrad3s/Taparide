# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

Flutter renders one custom design language on web (desktop + mobile browsers) and Android; both are first-class targets (confirmed 2026-10-15). iOS builds from the same code but is not a launch target.

## Stack

Flutter (Dart). Backend: Supabase (Auth + Postgres with row-level security), confirmed 2026-10-15. Until a Supabase project URL and anon key are supplied, the app runs on an on-device demo backend behind the same service interfaces.

## Users

- **Riders / passengers** in Abuja (FCT) commuting on corridors like Wuse–Maitama, Central Area–Gwarinpa, Kubwa and Nyanya, often on a phone, often at peak hours or late at night. Job: find a route with a fixed fare and departure time, book a seat, pay by tap card or QR, and know the vehicle is verified.
- **Transport operators** (bus companies, shuttles, rail): manage routes, fares, schedules, drivers and see revenue.
- **Fleet owners / investors**: see what each vehicle earns and its status, ending under-remittance.
- **Government (FCTA)**: ridership data, a verified-vehicle register, route activity and safety oversight.
- **Platform admins**: approve or suspend providers and vehicles, manage roles, audit changes.

## Product Purpose

The software layer that runs Abuja's transport: one platform where riders book and pay cashless, and operators, fleet owners and government see every trip and every naira. Built for the ATDEW 2026 National Innovation Challenge ("Energising Smart Mobility: Powering Cities of the Future"). Success: a judge or stakeholder can complete a rider booking and then see it reflected in provider and FCTA views.

## Positioning

Not a ride-hailing app: it is the shared system for fixed-route public transport in Abuja. Fixed fares and departure times, tap-card/QR payment, a verified-vehicle register against "one chance" robberies, and per-vehicle revenue transparency, all in one multi-tenant platform. Tag Along (verified professionals sharing rides home) and electric-vehicle booking extend it.

## Operating Context

Terminals and parks such as Berger, Area 1, AYA, Nyanya, Wuse, Gwarinpa, Kubwa; the Abuja light rail; new government EV and CNG fleets. Payment by tap card at the terminal or QR shown to the conductor.

## Capabilities and Constraints

- Roles: passenger, operator, fleet owner, government (FCTA), platform admin. Role checks must be enforced server-side (Supabase RLS), not only by hiding UI.
- Rider flows: routes, route details with departure times, seat booking, payment (tap card balance or QR), trip ticket, trip history, EV booking, Tag Along join/offer.
- Provider/admin flows: routes and fares, vehicles and EVs, bookings, revenue, verification, audit log.
- Undecided: real payment provider, real map/geocoding provider, card hardware.

## Brand Commitments

- Name: **Tap A Ride**, with the descriptor "Abuja Smart Mobility Platform". Tagline: "Ride • Connect • Go".
- Logo: green gradient map pin over a black car silhouette with green speed lines; wordmark "TAP A RIDE" in heavy italic black with green A's. Source: `assets/brand/` (original from the user).
- The user's mockup (clean green-and-white, deep green actions, white cards, real Abuja imagery) is a binding visual reference.

## Evidence on Hand

- Mockup image of landing page, rider app, operator/fleet/FCTA dashboards, Tag Along (user-provided).
- Concept & strategy brief: `../project_brief_extracted.txt`.
- Real photos: openly licensed Abuja photography from Wikimedia Commons in `assets/photos/` (credits in `assets/photos/CREDITS.md`).
- No real ridership, revenue or customer data exists yet. All dashboard figures are demo data and must be labelled as such; no testimonials, partners or endorsements may be invented.

## Product Principles

1. Fixed and visible: fares, times and vehicle verification are always shown before a rider commits.
2. One booking, every view: a rider action must show up in the operator, fleet and FCTA views.
3. Cashless by default: tap card and QR are the primary payment paths.
4. Safety is a feature: verification status and trip sharing are never hidden.
5. Honest data: demo figures are labelled; nothing implies government endorsement that does not exist.

## Accessibility & Inclusion

Riders use mid-range Android phones outdoors in bright light: high contrast, 48dp touch targets, legible type at small sizes, works on slow or dropped connections with clear offline states.
