import 'package:flutter_test/flutter_test.dart';
import 'package:taparide_flutter/core/account_models.dart';
import 'package:taparide_flutter/core/backend/backend.dart';
import 'package:taparide_flutter/core/backend/demo_seed.dart';
import 'package:taparide_flutter/core/models.dart';

import 'test_support.dart';

const _pw = DemoSeed.password;

void main() {
  test('a rider edits their details, gets verified by an admin, and renaming sends them back for review', () async {
    final (state, _) = await freshState();
    await state.signIn(email: 'zainab@taparide.demo', password: _pw, portal: Portal.passenger);
    expect(state.user!.verificationStatus, VerificationStatus.unverified);

    await state.updateMyProfile(fullName: 'Zainab  Yusuf', phone: '0803 555 7777', homeArea: 'Jabi', emergencyName: 'Amina Yusuf', emergencyPhone: '0803 555 8888');
    expect(state.user!.fullName, 'Zainab Yusuf');
    expect(state.user!.homeArea, 'Jabi');
    await expectLater(state.updateMyProfile(fullName: 'Zainab'), throwsA(isA<BackendException>()));

    await expectLater(state.submitVerification(nin: '123', dateOfBirth: DateTime(1995), phone: '08035557777'), throwsA(isA<BackendException>()));
    await expectLater(state.submitVerification(nin: '12345678901', dateOfBirth: DateTime(1995), phone: '08035557777'), throwsA(isA<BackendException>()),
        reason: "Aisha's NIN is already on another account");
    await state.submitVerification(nin: '52345678909', dateOfBirth: DateTime(1995, 3, 1), phone: '08035557777');
    expect(state.user!.verificationStatus, VerificationStatus.pending);
    await expectLater(state.submitVerification(nin: '52345678909', dateOfBirth: DateTime(1995, 3, 1), phone: '08035557777'), throwsA(isA<BackendException>()));

    await state.signOut();
    await state.signIn(email: DemoSeed.demoAdminEmail, password: _pw, portal: Portal.partner);
    final queue = await state.fetchRiderVerifications('pending');
    expect(queue.map((r) => r.name), contains('Zainab Yusuf'));
    expect(state.pendingVerifications, greaterThanOrEqualTo(1));
    final zainab = queue.firstWhere((r) => r.name == 'Zainab Yusuf');
    await state.reviewVerification(zainab.id, approve: true);
    expect((await state.fetchRiderVerifications('verified')).map((r) => r.name), contains('Zainab Yusuf'));

    await state.signOut();
    await state.signIn(email: 'zainab@taparide.demo', password: _pw, portal: Portal.passenger);
    expect(state.user!.isVerified, isTrue);
    await state.updateMyProfile(fullName: 'Zainab Bello', phone: '08035557777');
    expect(state.user!.verificationStatus, VerificationStatus.pending, reason: 'a verified name change needs review again');
  });

  test('a rider asks for a refund; the admin approves it and the money is back in the wallet', () async {
    final (state, _) = await freshState();
    await state.signIn(email: 'aisha@taparide.demo', password: _pw, portal: Portal.passenger);
    final route = state.bookableRoutes.firstWhere(state.canBook);
    final departure = route.upcomingDepartures(state.now, count: 1).first;
    final before = state.wallet!.balance;
    final booking = await state.bookTransit(route, departure, PaymentMethod.tapCard);
    expect(state.wallet!.balance, before - booking.fare);

    await expectLater(state.requestRefund(booking.id, 'no'), throwsA(isA<BackendException>()));
    final request = await state.requestRefund(booking.id, 'The bus never came');
    expect(request.status, RefundStatus.pending);
    expect(state.refundFor(booking.id)?.status, RefundStatus.pending);
    await expectLater(state.requestRefund(booking.id, 'Asking again'), throwsA(isA<BackendException>()));

    await state.signOut();
    await state.signIn(email: DemoSeed.demoAdminEmail, password: _pw, portal: Portal.partner);
    final waiting = await state.fetchRefundRequests('pending');
    final mine = waiting.firstWhere((r) => r.bookingId == booking.id);
    expect(mine.rider, 'Aisha Bello');
    final amount = await state.reviewRefund(mine.id, approve: true, note: 'Sorry about that');
    expect(amount, booking.fare);
    expect((await state.fetchRefundRequests('approved')).any((r) => r.bookingId == booking.id), isTrue);
    await expectLater(state.refundBooking(booking.id, 'again'), throwsA(isA<BackendException>()), reason: 'no double refunds');

    await state.signOut();
    await state.signIn(email: 'aisha@taparide.demo', password: _pw, portal: Portal.passenger);
    expect(state.wallet!.balance, before);
    final refunded = state.myBookings.firstWhere((b) => b.id == booking.id);
    expect(refunded.refundedAt, isNotNull);
    expect(state.refundFor(booking.id)?.status, RefundStatus.approved);
  });

  test('admins can decline a refund with a note, and refund a booking directly', () async {
    final (state, _) = await freshState();
    await state.signIn(email: 'aisha@taparide.demo', password: _pw, portal: Portal.passenger);
    final route = state.bookableRoutes.firstWhere(state.canBook);
    final times = route.upcomingDepartures(state.now, count: 2);
    final a = await state.bookTransit(route, times[0], PaymentMethod.tapCard);
    final b = await state.bookTransit(route, times[1], PaymentMethod.tapCard);
    final req = await state.requestRefund(a.id, 'Changed my mind');
    await state.signOut();

    await state.signIn(email: DemoSeed.demoAdminEmail, password: _pw, portal: Portal.partner);
    await state.reviewRefund(req.id, approve: false, note: 'You can cancel before departure for a full refund instead.');
    expect(await state.refundBooking(b.id, 'The bus broke down'), b.fare);
    await state.signOut();

    await state.signIn(email: 'aisha@taparide.demo', password: _pw, portal: Portal.passenger);
    expect(state.refundFor(a.id)?.status, RefundStatus.declined);
    expect(state.refundFor(a.id)?.adminNote, contains('cancel before departure'));
    expect(state.myBookings.firstWhere((x) => x.id == b.id).refundedAt, isNotNull);
  });

  test('riders cannot use the admin review queues', () async {
    final (state, _) = await freshState();
    await state.signIn(email: 'aisha@taparide.demo', password: _pw, portal: Portal.passenger);
    await expectLater(state.fetchRiderVerifications('pending'), throwsA(isA<BackendException>()));
    await expectLater(state.fetchRefundRequests('pending'), throwsA(isA<BackendException>()));
  });
}
