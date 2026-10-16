import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:taparide_flutter/core/backend/backend.dart';
import 'package:taparide_flutter/core/backend/demo_seed.dart';
import 'package:taparide_flutter/core/models.dart';
import 'package:taparide_flutter/core/partner_models.dart';

import 'test_support.dart';

PartnerApplication driverDraft({String plate = 'KUB 731 XA', String chassis = '1HGCM82633A004352'}) => PartnerApplication(
      id: '',
      userId: '',
      type: PartnerType.privateDriver,
      status: ApplicationStatus.submitted,
      fullName: 'Emeka Nwosu',
      email: 'emeka@taparide.demo',
      phone: '+234 803 111 2222',
      dateOfBirth: DateTime(1991, 2, 3),
      address: '3 Banex Road',
      area: 'Wuse 2',
      licenceNumber: 'ABJ77120BB31',
      licenceClass: 'B',
      licenceExpiry: DateTime(2030, 1, 1),
      vehicleMake: 'Honda',
      vehicleModel: 'Accord',
      vehicleYear: 2018,
      vehicleColour: 'Black',
      plateNumber: plate,
      chassisNumber: chassis,
      seats: 4,
      documents: const [],
      createdAt: DateTime(2026, 10, 16),
    );

List<DocumentFile> docs(PartnerType type) => [
      for (final s in type.requiredDocs) DocumentFile(slot: s, fileName: '${s.wire}.jpg', mimeType: 'image/jpeg'),
    ];

void main() {
  test('partner rules catch bad chassis, plate and licence numbers', () {
    expect(PartnerRules.chassis('1HGCM82633A004352'), isNull);
    expect(PartnerRules.chassis('1HGCM82633A00435'), isNotNull, reason: '16 characters');
    expect(PartnerRules.chassis('1HGCM82633AO04352'), isNotNull, reason: 'contains the letter O');
    expect(PartnerRules.plate('ABJ 123 AB'), isNull);
    expect(PartnerRules.plate('123'), isNotNull);
    expect(PartnerRules.licence('ABC'), isNotNull);
  });

  test('a private driver applies, the FCTA approves, and the driver gets a dashboard and a bookable car', () async {
    final (state, backend) = await freshState();
    await state.signIn(email: 'emeka@taparide.demo', password: DemoSeed.password, portal: Portal.passenger);

    await expectLater(
      () => state.submitApplication(driverDraft(), const []),
      throwsA(isA<BackendException>()),
      reason: 'documents are required',
    );
    await expectLater(
      () => state.submitApplication(driverDraft(plate: 'GWA 482 KD'), docs(PartnerType.privateDriver)),
      throwsA(isA<BackendException>()),
      reason: 'that plate is already in a pending application',
    );
    final app = await state.submitApplication(driverDraft(), docs(PartnerType.privateDriver));
    expect(app.status, ApplicationStatus.submitted);
    expect(state.myApplications.first.id, app.id);
    await expectLater(() => backend.reviewPartnerApplication(app.id, ApplicationStatus.approved, ''), throwsA(isA<BackendException>()), reason: 'riders cannot approve');
    await state.signOut();

    await state.signIn(email: 'transport@fcta.demo', password: DemoSeed.password, portal: Portal.partner);
    expect(state.partnerApplications.where((a) => a.status.isOpen).length, 3, reason: 'two seeded applications plus the new one');
    await state.reviewApplication(state.partnerApplications.firstWhere((a) => a.id == app.id), ApplicationStatus.approved, '');
    await state.signOut();

    await state.signIn(email: 'emeka@taparide.demo', password: DemoSeed.password, portal: Portal.partner);
    expect(state.user!.role, UserRole.operator);
    expect(state.user!.providerId, isNotNull);
    final car = state.vehicles.firstWhere((v) => v.plate == 'KUB 731 XA');
    expect(car.kind, VehicleKind.car);
    expect(car.verification, Verification.verified);
    await state.signOut();

    await state.signIn(email: 'aisha@taparide.demo', password: DemoSeed.password, portal: Portal.passenger);
    expect(state.availableEvs.map((v) => v.plate), contains('KUB 731 XA'), reason: 'approved private cars can be booked by riders');
  });

  test('declining or requesting changes needs a note', () async {
    final (state, _) = await freshState();
    await state.signIn(email: 'admin@taparide.demo', password: DemoSeed.password, portal: Portal.partner);
    final company = state.partnerApplications.firstWhere((a) => a.companyName == 'Capital City Cabs Ltd');
    await expectLater(() => state.reviewApplication(company, ApplicationStatus.needsChanges, ' '), throwsA(isA<BackendException>()));
    await state.reviewApplication(company, ApplicationStatus.approved, 'Welcome aboard');
    final provider = state.providers.firstWhere((p) => p.name == 'Capital City Cabs Ltd');
    expect(provider.kind, ProviderKind.fleetOwner);
    expect(provider.status, Verification.verified);
  });

  test('AI insights figures come from platform data, per organisation', () async {
    final (state, _) = await freshState();
    await state.signIn(email: 'admin@taparide.demo', password: DemoSeed.password, portal: Portal.partner);
    final metro = state.insightsFor(DemoSeed.pMetro);
    expect(metro.routes, isNotEmpty);
    expect(metro.routes.every((r) => r.providerId == DemoSeed.pMetro), isTrue);
    expect(metro.monthlyRevenue, greaterThan(0));
    expect(metro.areas.first.trips, greaterThanOrEqualTo(metro.areas.last.trips));
    final platform = state.insightsFor(null);
    expect(platform.routes.length, greaterThan(metro.routes.length));
    expect(platform.toAiJson()['scope'], isNotEmpty);
  });

  test('riders get a book-early suggestion from their habits', () async {
    final (state, _) = await freshState();
    await state.signIn(email: 'aisha@taparide.demo', password: DemoSeed.password, portal: Portal.passenger);
    expect(state.suggestions, isNotEmpty);
    expect(state.suggestions.first.title, contains('Wuse – Maitama'));
  });

  testWidgets('admin opens AI insights for any organisation and the application queue', (tester) async {
    final state = await pumpApp(tester, size: const Size(1440, 1000));
    await tester.runAsync(() => state.signIn(email: 'admin@taparide.demo', password: DemoSeed.password, portal: Portal.partner));
    await tester.pumpAndSettle();

    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/portal/insights?provider=${DemoSeed.pMetro}');
    await tester.pumpAndSettle();
    expect(find.text('AI insights'), findsWidgets);
    expect(find.textContaining('Abuja Metro Bus Co.'), findsWidgets);
    expect(find.text('Income by route'), findsOneWidget);
    expect(find.text('High-demand areas'), findsOneWidget);

    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/portal/applications');
    await tester.pumpAndSettle();
    expect(find.text('Capital City Cabs Ltd'), findsOneWidget);
    expect(find.text('Musa Abdullahi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
