// POST /api/assistant  — one step of the Tap A Ride assistant's tool loop.
// Body: { persona: "rider"|"partner", history: [...provider-native...], input: {text, context} | {toolResults} }
// The tools run in the app (with the user's own permissions); this endpoint only talks to the model.
import { chatStep, handleError, readJson, send, AiError } from "./_lib/ai.js";
import { requireUser } from "./_lib/auth.js";

const RIDER_SYSTEM = `You are the Tap A Ride assistant inside the Tap A Ride app (Abuja Smart Mobility Platform, Nigeria's Federal Capital Territory).
You help riders get around Abuja on fixed-fare buses, the Abuja Metro Rail, the airport e-shuttle, electric cars and Tag Along shared rides.

How to work:
- Use the tools to look things up; never invent routes, fares, times, balances or bookings. Fares are in naira (₦).
- To plan a trip, call search_routes (and plan_road_trip for door-to-door travel time when both places are known), then suggest the best departure with a "leave by" time.
- Booking or cancelling spends the rider's money: call book_seat / book_electric_ride / cancel_trip only after the rider has clearly asked for it. The app will show the rider a confirmation before anything is charged, so you can call the tool once they've chosen.
- When a rider books, offer a reminder (set_reminder). Encourage booking popular peak departures early.
- For nearby places (pharmacy, ATM, fuel, hospital, police) or emergencies, call open_findme_map. In danger, tell them to press SOS or call 112.
- Keep answers short and practical: 1–4 sentences, plain words, no markdown tables. Use the rider's local time (West Africa Time).`;

const PARTNER_SYSTEM = `You are the Tap A Ride partner assistant for transport operators, fleet owners, FCTA officials and platform admins in Abuja.
Answer questions about their routes, vehicles, bookings, revenue, verification queue and partner applications using the tools; never invent numbers.
Point out what needs attention (vehicles in maintenance, pending verifications, low-performing routes) and suggest one concrete next step.
You cannot approve, suspend or change anything yourself — tell the user which screen does it. Keep answers short: 1–5 sentences, no markdown tables. Money is in naira (₦).`;

const str = (description) => ({ type: "string", description });

const RIDER_TOOLS = [
  {
    name: "search_routes",
    description: "Find bookable fixed-fare routes. Match on area or stop names (e.g. 'Gwarinpa', 'Wuse to Maitama'). Returns routes with id, stops, fare, duration and the next departures.",
    input_schema: { type: "object", properties: { from: str("Origin area or stop, optional"), to: str("Destination area or stop, optional"), query: str("Free-text search, optional") }, additionalProperties: false },
  },
  {
    name: "get_departures",
    description: "List upcoming departure times for a route, optionally after a given local time.",
    input_schema: { type: "object", properties: { route_id: str("Route id from search_routes"), after: str("ISO 8601 local date-time; default now"), count: { type: "integer", description: "How many departures (1-10)" } }, required: ["route_id"], additionalProperties: false },
  },
  {
    name: "plan_road_trip",
    description: "Door-to-door road travel time and directions between two places in Abuja (live map routing). Use for 'how long will it take' and to compute when to leave.",
    input_schema: { type: "object", properties: { from: str("Start place, or 'my location'"), to: str("Destination place"), mode: { type: "string", enum: ["driving", "walking"] } }, required: ["from", "to"], additionalProperties: false },
  },
  {
    name: "book_seat",
    description: "Book one seat on a route departure. The app asks the rider to confirm and pays from their Tap Card balance.",
    input_schema: { type: "object", properties: { route_id: str("Route id"), departure: str("ISO 8601 local date-time of the departure"), payment: { type: "string", enum: ["tap_card", "qr"] } }, required: ["route_id", "departure"], additionalProperties: false },
  },
  {
    name: "list_my_trips",
    description: "The rider's bookings (upcoming and recent) with ids, times, fares and status.",
    input_schema: { type: "object", properties: { upcoming_only: { type: "boolean" } }, additionalProperties: false },
  },
  {
    name: "cancel_trip",
    description: "Cancel one of the rider's open bookings (refunded to the Tap Card). The app asks the rider to confirm.",
    input_schema: { type: "object", properties: { booking_id: str("Booking id from list_my_trips") }, required: ["booking_id"], additionalProperties: false },
  },
  {
    name: "wallet_balance",
    description: "The rider's Tap Card balance in naira.",
    input_schema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "set_reminder",
    description: "Remind the rider before a booked trip (default: when to leave, based on travel time to the first stop).",
    input_schema: { type: "object", properties: { booking_id: str("Booking id"), minutes_before: { type: "integer", description: "Minutes before departure (5-120)" } }, required: ["booking_id"], additionalProperties: false },
  },
  {
    name: "list_electric_cars",
    description: "Verified electric cars available now, with battery, area and base fare.",
    input_schema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "book_electric_ride",
    description: "Book an electric car from a pickup area to a drop-off area in Abuja. The app shows the fare and asks the rider to confirm.",
    input_schema: { type: "object", properties: { vehicle_id: str("Vehicle id from list_electric_cars, optional"), pickup: str("Pickup area"), dropoff: str("Drop-off area") }, required: ["pickup", "dropoff"], additionalProperties: false },
  },
  {
    name: "list_tag_along_rides",
    description: "Shared rides home offered by verified colleagues (Tag Along), with seats and cost share.",
    input_schema: { type: "object", properties: { destination: str("Filter by destination area, optional") }, additionalProperties: false },
  },
  {
    name: "open_findme_map",
    description: "Open the FindMe safety map in the app: nearby services (pharmacy, hospital, ATM, fuel, police, bus parks), share location, SOS.",
    input_schema: { type: "object", properties: { category: { type: "string", enum: ["food", "fuel", "hospital", "pharmacy", "mechanic", "taxi", "bus_park", "atm", "hotel", "police", "sos"] } }, additionalProperties: false },
  },
];

const PARTNER_TOOLS = [
  { name: "dashboard_summary", description: "Headline figures for the signed-in partner's dashboard (trips, revenue, ridership, verified vehicles, routes).", input_schema: { type: "object", properties: {}, additionalProperties: false } },
  {
    name: "list_vehicles",
    description: "Vehicles the partner can see, optionally filtered by status or verification.",
    input_schema: { type: "object", properties: { status: { type: "string", enum: ["active", "on_trip", "charging", "maintenance", "inactive"] }, verification: { type: "string", enum: ["verified", "pending", "suspended"] } }, additionalProperties: false },
  },
  { name: "route_performance", description: "Routes with fare, trips in the last 30 days and bookings today, sorted by demand.", input_schema: { type: "object", properties: {}, additionalProperties: false } },
  { name: "recent_bookings", description: "The latest bookings the partner can see.", input_schema: { type: "object", properties: { limit: { type: "integer" } }, additionalProperties: false } },
  { name: "verification_queue", description: "Providers, vehicles and partner applications waiting for review (FCTA and admins).", input_schema: { type: "object", properties: {}, additionalProperties: false } },
];

export default async function handler(req, res) {
  if (req.method !== "POST") return send(res, 405, { error: "Use POST." });
  try {
    await requireUser(req, { perMinute: 30 });
    const body = await readJson(req, 2_000_000);
    const persona = body.persona === "partner" ? "partner" : "rider";
    const history = Array.isArray(body.history) ? body.history.slice(-60) : [];
    const input = body.input || {};
    if (!input.toolResults && !(typeof input.text === "string" && input.text.trim())) throw new AiError(400, "Say something to the assistant.");
    if (input.text && input.text.length > 2000) throw new AiError(400, "That message is too long.");

    // Volatile context (time, name, balance) rides in the user turn so the system prompt stays cacheable.
    if (input.text && input.context) input.text = `[App context: ${JSON.stringify(input.context).slice(0, 1500)}]\n${input.text}`;

    const result = await chatStep({
      system: persona === "partner" ? PARTNER_SYSTEM : RIDER_SYSTEM,
      tools: persona === "partner" ? PARTNER_TOOLS : RIDER_TOOLS,
      history,
      input,
    });
    send(res, 200, result);
  } catch (error) {
    handleError(res, error);
  }
}
