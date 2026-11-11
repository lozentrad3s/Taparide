import 'package:flutter_test/flutter_test.dart';
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

  test('event rides: list an event, offer a ride to it, and only the organiser can remove it', () async {
    final (state, backend) = await freshState();
    await state.signIn(email: 'aisha@taparide.demo', password: _pw, portal: Portal.passenger);
    expect(state.events, isNotEmpty, reason: 'sample events are listed');

    final event = await state.createEvent(title: 'Graduation party', venue: 'Jabi Lake Park', area: 'Jabi', startsAt: state.now.add(const Duration(days: 2)), category: EventCategory.community);
    final ride = await state.offerSharedRide(origin: 'Wuse 2', destination: event.venue, departAt: event.startsAt.subtract(const Duration(hours: 1)), seats: 3, costShare: 700, vehicleLabel: 'Kia Rio', eventId: event.id);
    expect(state.ridesForEvent(event.id).single.id, ride.id);
    await expectLater(() => state.createEvent(title: 'Yesterday', venue: 'Somewhere', area: 'Abuja', startsAt: state.now.subtract(const Duration(days: 1)), category: EventCategory.other), throwsA(isA<BackendException>()));
    await state.signOut();

    await state.signIn(email: 'emeka@taparide.demo', password: _pw, portal: Portal.passenger);
    expect(state.eventById(event.id), isNotNull);
    await expectLater(() => backend.removeEvent(event.id), throwsA(isA<BackendException>()), reason: 'not the organiser');
    await state.signOut();

    await state.signIn(email: 'aisha@taparide.demo', password: _pw, portal: Portal.passenger);
    await state.removeEvent(state.eventById(event.id)!);
    expect(state.eventById(event.id), isNull);
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
