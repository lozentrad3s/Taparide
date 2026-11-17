import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taparide_flutter/core/app_state.dart';
import 'package:taparide_flutter/core/backend/demo_backend.dart';
import 'package:taparide_flutter/core/backend/backend.dart';
import 'package:taparide_flutter/core/backend/demo_seed.dart';
import 'package:taparide_flutter/core/live_models.dart';
import 'package:taparide_flutter/core/models.dart';

import 'test_support.dart';

const _pw = DemoSeed.password;

void main() {
  test('Tag Along: the host accepts, the share is held, and withdrawing the ride refunds the rider', () async {
    final (state, backend) = await freshState();

    // Zainab offers a ride.
    await state.signIn(email: 'zainab@taparide.demo', password: _pw, portal: Portal.passenger);
    final ride = await state.offerSharedRide(origin: 'Jabi', destination: 'Kubwa', departAt: state.now.add(const Duration(hours: 3)), seats: 2, costShare: 1200, vehicleLabel: 'Toyota Sienna');
    await state.signOut();

    // Emeka asks to join; nothing is charged until the host accepts.
    await state.signIn(email: 'emeka@taparide.demo', password: _pw, portal: Portal.passenger);
    final before = state.wallet!.balance;
    final request = await state.requestSharedRide(ride);
    expect(request.status, BookingStatus.requested);
    expect((await backend.fetchWallet()).balance, before);
    await expectLater(() => backend.respondToRideRequest(request.id, accept: true), throwsA(isA<BackendException>()), reason: 'a rider cannot accept their own request');
    await state.signOut();

    // Zainab sees the request and accepts: the seat is taken and the share leaves the rider's card.
    await state.signIn(email: 'zainab@taparide.demo', password: _pw, portal: Portal.passenger);
    expect(state.pendingRideRequests.map((b) => b.id), contains(request.id));
    await state.respondToRideRequest(state.pendingRideRequests.single, accept: true);
    expect(state.rideById(ride.id)!.seatsTaken, 1);
    expect(state.pendingRideRequests, isEmpty);
    await state.signOut();

    await state.signIn(email: 'emeka@taparide.demo', password: _pw, portal: Portal.passenger);
    expect(state.wallet!.balance, before - 1200);
    expect(state.bookingForRide(ride.id)!.status, BookingStatus.accepted);
    await state.signOut();

    // The host withdraws the ride: the rider is refunded and the ride leaves the list.
    await state.signIn(email: 'zainab@taparide.demo', password: _pw, portal: Portal.passenger);
    await state.cancelSharedRide(state.rideById(ride.id)!);
    expect(state.rideById(ride.id), isNull);
    await state.signOut();

    await state.signIn(email: 'emeka@taparide.demo', password: _pw, portal: Portal.passenger);
    expect(state.wallet!.balance, before);
    expect(state.myBookings.firstWhere((b) => b.id == request.id).status, BookingStatus.cancelled);
  });

  test('events: only partners list them, operators run buses, riders pick a time and get refunds', () async {
    final (state, backend) = await freshState();
    await state.signIn(email: 'aisha@taparide.demo', password: _pw, portal: Portal.passenger);
    expect(state.events, isNotEmpty, reason: 'sample partner events are listed');
    await expectLater(
      () => state.createEvent(title: 'Graduation party', venue: 'Jabi Lake Park', area: 'Jabi', startsAt: state.now.add(const Duration(days: 2)), category: EventCategory.community),
      throwsA(isA<BackendException>()),
      reason: 'riders cannot list events',
    );
    await state.signOut();

    // The event partner posts an event with tickets.
    await state.signIn(email: 'events@taparide.demo', password: _pw, portal: Portal.partner);
    final starts = state.now.add(const Duration(days: 3));
    final event = await state.createEvent(title: 'Tech Meetup', venue: 'International Conference Centre', area: 'Central Area', startsAt: starts, category: EventCategory.conference, ticketPrice: 500, ticketsTotal: 100);
    await state.signOut();

    // A registered bus operator puts a bus on it with two departure times.
    await state.signIn(email: 'ops@abujametro.demo', password: _pw, portal: Portal.partner);
    final early = starts.subtract(const Duration(hours: 2)), late = starts.subtract(const Duration(hours: 1));
    final bus = await state.offerEventBus(event: state.eventById(event.id)!, origin: 'Kubwa', fare: 1200, capacity: 30, minRiders: 2, slots: [early, late]);
    await expectLater(() => backend.offerEventBus(eventId: event.id, origin: 'Kubwa', fare: 1200, capacity: 30, minRiders: 2, slots: [starts.add(const Duration(hours: 1))]), throwsA(isA<BackendException>()), reason: 'departures must be before the event');
    await state.signOut();

    // Riders buy a ticket and book seats, each picking a time.
    await state.signIn(email: 'aisha@taparide.demo', password: _pw, portal: Portal.passenger);
    await expectLater(() => backend.offerEventBus(eventId: event.id, origin: 'Wuse', fare: 900, capacity: 14, minRiders: 4, slots: [early]), throwsA(isA<BackendException>()), reason: 'riders cannot run buses');
    final ticket = await state.buyEventTicket(state.eventById(event.id)!, PaymentMethod.tapCard);
    expect(ticket.kind, BookingKind.eventTicket);
    expect(state.wallet!.balance, 2000);
    final seat = await state.bookEventBus(state.eventBusById(bus.id)!, late, PaymentMethod.tapCard);
    expect(seat.status, BookingStatus.requested, reason: 'held until the operator confirms a time');
    expect(state.wallet!.balance, 800);
    expect(state.eventBusById(bus.id)!.seatsAt(late), 1);
    await expectLater(() => state.bookEventBus(state.eventBusById(bus.id)!, early, PaymentMethod.tapCard), throwsA(isA<BackendException>()), reason: 'one seat per rider');
    await state.signOut();

    await state.signIn(email: 'emeka@taparide.demo', password: _pw, portal: Portal.passenger);
    await state.bookEventBus(state.eventBusById(bus.id)!, early, PaymentMethod.tapCard);
    await state.signOut();

    // The operator confirms the later time; everyone moves to it.
    await state.signIn(email: 'ops@abujametro.demo', password: _pw, portal: Portal.partner);
    await state.confirmEventBus(state.eventBusById(bus.id)!, late);
    expect(state.eventBusById(bus.id)!.status, EventBusStatus.confirmed);
    await state.signOut();

    await state.signIn(email: 'aisha@taparide.demo', password: _pw, portal: Portal.passenger);
    final mine = state.myBookings.firstWhere((b) => b.id == seat.id);
    expect(mine.status, BookingStatus.confirmed);
    expect(mine.departureAt, late);
    await state.cancelBooking(mine);
    await state.refresh();
    expect(state.wallet!.balance, 2000, reason: 'bus fare refunded on cancelling');
    await state.signOut();

    // The event partner sees the ticket and seats for their event, nobody else's.
    await state.signIn(email: 'events@taparide.demo', password: _pw, portal: Portal.partner);
    expect(state.partnerBookings.where((b) => b.eventId == event.id && b.kind == BookingKind.eventTicket), hasLength(1));
    expect(state.partnerBookings.every((b) => b.eventId != null), isTrue);
    await state.removeEvent(state.eventById(event.id)!);
    expect(state.eventById(event.id), isNull);
  });

  test('ads: the reward is paid only after the full ad, at most three times a day', () async {
    var now = DateTime(2026, 11, 17, 9);
    SharedPreferences.setMockInitialValues({});
    final backend = await DemoBackend.create(latency: Duration.zero, clock: () => now);
    final state = AppState(backend, clock: () => now);
    await state.init();
    await state.signIn(email: 'aisha@taparide.demo', password: _pw, portal: Portal.passenger);
    expect(state.ads, isNotEmpty);
    final ad = state.ads.first;

    final view = await state.startAdView(ad);
    await expectLater(() => state.claimAdReward(view), throwsA(isA<BackendException>()), reason: 'too early');
    now = now.add(Duration(seconds: ad.seconds));
    final first = await state.claimAdReward(view);
    expect(first.reward, ad.reward);
    expect(state.wallet!.balance, 2500 + ad.reward);
    await expectLater(() => state.claimAdReward(view), throwsA(isA<BackendException>()), reason: 'one reward per view');

    for (var i = 0; i < 3; i++) {
      final v = await state.startAdView(ad);
      now = now.add(Duration(seconds: ad.seconds));
      final r = await state.claimAdReward(v);
      expect(r.reward, i < 2 ? ad.reward : 0, reason: 'three rewards a day');
    }
    expect(state.wallet!.balance, 2500 + 3 * ad.reward);
  });

  test('share my ride: the link shows the trip without an account and stops working when sharing stops', () async {
    final (state, backend) = await freshState();
    await state.signIn(email: 'aisha@taparide.demo', password: _pw, portal: Portal.passenger);
    final route = state.bookableRoutes.first;
    final booking = await state.bookTransit(route, state.now.add(const Duration(hours: 2)), PaymentMethod.tapCard);

    final share = await backend.shareTrip(booking.id);
    expect((await backend.shareTrip(booking.id)).token, share.token, reason: 'the same link while it is valid');
    await backend.updateTripLocation(booking.id, 9.06, 7.49);
    await state.signOut();

    // Signed out, like the trusted contact.
    final trip = await backend.fetchSharedTrip(share.token);
    expect(trip, isNotNull);
    expect(trip!.passenger, 'Aisha', reason: 'first name only');
    expect(trip.destination, booking.destination);
    expect(trip.stops, isNotEmpty);
    expect(trip.rider, isNotNull);
    expect(await backend.fetchSharedTrip('not-a-token'), isNull);

    await state.signIn(email: 'aisha@taparide.demo', password: _pw, portal: Portal.passenger);
    await backend.stopSharingTrip(booking.id);
    expect(await backend.fetchSharedTrip(share.token), isNull);
  });

  test('live positions: only the vehicle\'s own operator can report GPS, and riders see fresh fixes', () async {
    final (state, backend) = await freshState();
    await state.signIn(email: 'grace@taparide.demo', password: _pw, portal: Portal.partner);
    await backend.reportVehiclePosition('v_grace_car', 9.0765, 7.4698);
    await expectLater(() => backend.reportVehiclePosition('v_abj021', 9.07, 7.47), throwsA(isA<BackendException>()), reason: 'another operator\'s bus');
    await state.refreshPositions();
    expect(state.livePosition('v_grace_car')!.point.latitude, closeTo(9.0765, 1e-6));
    expect(state.livePosition('v_abj021'), isNull);
    await backend.stopVehicleTracking('v_grace_car');
    await state.refreshPositions();
    expect(state.livePosition('v_grace_car'), isNull);
  });
}
