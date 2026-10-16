import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'models.dart';

T _byWire<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw is! String) return fallback;
  for (final v in values) {
    if (v.wire == raw || v.name == raw) return v;
  }
  return fallback;
}

enum PartnerType { privateDriver, fleetOwner, busOperator, evOperator, governmentAgency }

extension PartnerTypeX on PartnerType {
  String get label => switch (this) {
        PartnerType.privateDriver => 'Private driver',
        PartnerType.fleetOwner => 'Fleet owner',
        PartnerType.busOperator => 'Bus / shuttle operator',
        PartnerType.evOperator => 'Electric vehicle operator',
        PartnerType.governmentAgency => 'Government agency',
      };

  String get blurb => switch (this) {
        PartnerType.privateDriver => 'You own and drive your own car or minibus.',
        PartnerType.fleetOwner => 'You own vehicles that operators run on Tap A Ride.',
        PartnerType.busOperator => 'Your company runs buses or shuttles on fixed routes.',
        PartnerType.evOperator => 'You run electric cars, shuttles or keke.',
        PartnerType.governmentAgency => 'A public transport or EV bus scheme run by government.',
      };

  IconData get icon => switch (this) {
        PartnerType.privateDriver => Icons.drive_eta_rounded,
        PartnerType.fleetOwner => Icons.local_shipping_rounded,
        PartnerType.busOperator => Icons.directions_bus_rounded,
        PartnerType.evOperator => Icons.electric_car_rounded,
        PartnerType.governmentAgency => Icons.account_balance_rounded,
      };

  /// Companies and agencies register a business; private drivers register themselves and one vehicle.
  bool get isOrganisation => this != PartnerType.privateDriver;

  /// Documents this kind of partner must upload.
  List<DocSlot> get requiredDocs => isOrganisation
      ? const [DocSlot.cacCertificate, DocSlot.operatingPermit, DocSlot.insurance]
      : const [DocSlot.licenceFront, DocSlot.proofOfOwnership, DocSlot.vehiclePhoto];

  List<DocSlot> get optionalDocs => isOrganisation
      ? const [DocSlot.taxClearance, DocSlot.fleetList]
      : const [DocSlot.licenceBack, DocSlot.roadworthiness, DocSlot.insurance];

  ProviderKind get providerKind => switch (this) {
        PartnerType.privateDriver => ProviderKind.privateDriver,
        PartnerType.fleetOwner => ProviderKind.fleetOwner,
        PartnerType.busOperator => ProviderKind.busOperator,
        PartnerType.evOperator => ProviderKind.electric,
        PartnerType.governmentAgency => ProviderKind.busOperator,
      };
}

enum ApplicationStatus { submitted, underReview, approved, rejected, needsChanges }

extension ApplicationStatusX on ApplicationStatus {
  String get label => switch (this) {
        ApplicationStatus.submitted => 'Submitted',
        ApplicationStatus.underReview => 'Under review',
        ApplicationStatus.approved => 'Approved',
        ApplicationStatus.rejected => 'Not approved',
        ApplicationStatus.needsChanges => 'Changes needed',
      };

  bool get isOpen => this == ApplicationStatus.submitted || this == ApplicationStatus.underReview;
}

/// The documents a private partner must upload.
enum DocSlot { licenceFront, licenceBack, proofOfOwnership, roadworthiness, insurance, vehiclePhoto, cacCertificate, operatingPermit, taxClearance, fleetList }

extension DocSlotX on DocSlot {
  String get label => switch (this) {
        DocSlot.licenceFront => "Driver's licence (front)",
        DocSlot.licenceBack => "Driver's licence (back)",
        DocSlot.proofOfOwnership => 'Vehicle licence / proof of ownership',
        DocSlot.roadworthiness => 'Roadworthiness certificate',
        DocSlot.insurance => 'Insurance certificate',
        DocSlot.vehiclePhoto => 'Vehicle photo showing the plate',
        DocSlot.cacCertificate => 'CAC certificate of incorporation',
        DocSlot.operatingPermit => 'FCT transport operating permit',
        DocSlot.taxClearance => 'Tax clearance certificate',
        DocSlot.fleetList => 'Fleet list (plates and chassis numbers)',
      };

  IconData get icon => switch (this) {
        DocSlot.licenceFront || DocSlot.licenceBack => Icons.badge_rounded,
        DocSlot.proofOfOwnership => Icons.description_rounded,
        DocSlot.roadworthiness => Icons.verified_rounded,
        DocSlot.insurance => Icons.shield_rounded,
        DocSlot.vehiclePhoto => Icons.photo_camera_rounded,
        DocSlot.cacCertificate => Icons.apartment_rounded,
        DocSlot.operatingPermit => Icons.assignment_turned_in_rounded,
        DocSlot.taxClearance => Icons.receipt_long_rounded,
        DocSlot.fleetList => Icons.list_alt_rounded,
      };
}

/// A picked or uploaded document. [bytes] is only present on the device that picked it.
class DocumentFile {
  const DocumentFile({required this.slot, required this.fileName, required this.mimeType, this.bytes, this.path, this.url});
  final DocSlot slot;
  final String fileName;
  final String mimeType;
  final Uint8List? bytes;

  /// Storage path once uploaded (Supabase Storage or demo store key).
  final String? path;

  /// A short-lived URL for viewing (reviewers).
  final String? url;

  bool get isImage => mimeType.startsWith('image/');

  DocumentFile copyWith({String? path, String? url}) =>
      DocumentFile(slot: slot, fileName: fileName, mimeType: mimeType, bytes: bytes, path: path ?? this.path, url: url ?? this.url);

  Map<String, Object?> toJson() => {'slot': slot.wire, 'file_name': fileName, 'mime_type': mimeType, 'path': path};

  factory DocumentFile.fromJson(Map<String, dynamic> json) => DocumentFile(
        slot: _byWire(DocSlot.values, json['slot'], DocSlot.vehiclePhoto),
        fileName: (json['file_name'] as String?) ?? 'document',
        mimeType: (json['mime_type'] as String?) ?? 'image/jpeg',
        path: json['path'] as String?,
      );
}

/// One check from the AI document review (see deploy/api/verify-documents.js).
class AiFieldCheck {
  const AiFieldCheck({required this.field, required this.result, required this.note, this.entered, this.found});
  final String field;
  final String result; // match | partial | mismatch | not_found | expired
  final String note;
  final String? entered;
  final String? found;

  String get label => switch (field) {
        'full_name' => 'Full name',
        'licence_number' => 'Licence number',
        'licence_expiry' => 'Licence expiry',
        'plate_number' => 'Plate number',
        'chassis_number' => 'Chassis number (VIN)',
        'vehicle' => 'Vehicle',
        'photo' => 'Vehicle photo',
        _ => field,
      };

  factory AiFieldCheck.fromJson(Map<String, dynamic> json) => AiFieldCheck(
        field: '${json['field']}',
        result: '${json['result'] ?? 'not_found'}',
        note: '${json['note'] ?? ''}',
        entered: json['entered'] as String?,
        found: json['found'] as String?,
      );
}

class AiDocumentCheck {
  const AiDocumentCheck({required this.overall, required this.summary, required this.checks, required this.raw, this.checkedAt, this.model});
  final String overall; // pass | review | fail
  final String summary;
  final List<AiFieldCheck> checks;
  final Map<String, dynamic> raw;
  final DateTime? checkedAt;
  final String? model;

  factory AiDocumentCheck.fromJson(Map<String, dynamic> json) => AiDocumentCheck(
        overall: '${json['overall'] ?? 'review'}',
        summary: '${json['summary'] ?? ''}',
        checks: [for (final c in (json['checks'] as List? ?? const [])) AiFieldCheck.fromJson(Map<String, dynamic>.from(c as Map))],
        raw: json,
        checkedAt: DateTime.tryParse('${json['checkedAt'] ?? ''}')?.toLocal(),
        model: json['model'] as String?,
      );
}

class PartnerApplication {
  const PartnerApplication({
    required this.id,
    required this.userId,
    required this.type,
    required this.status,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.dateOfBirth,
    required this.address,
    required this.area,
    required this.licenceNumber,
    required this.licenceClass,
    required this.licenceExpiry,
    required this.vehicleMake,
    required this.vehicleModel,
    required this.vehicleYear,
    required this.vehicleColour,
    required this.plateNumber,
    required this.chassisNumber,
    required this.seats,
    required this.documents,
    required this.createdAt,
    this.companyName,
    this.rcNumber,
    this.tin,
    this.fleetSize,
    this.contactRole,
    this.nin,
    this.nextOfKinName,
    this.nextOfKinPhone,
    this.engineNumber,
    this.aiCheck,
    this.reviewerNote,
    this.reviewedBy,
    this.reviewedAt,
    this.providerId,
    this.vehicleId,
  });

  final String id;
  final String userId;
  final PartnerType type;
  final ApplicationStatus status;
  final String fullName;
  final String email;
  final String phone;
  final DateTime dateOfBirth;
  final String address;
  final String area;
  final String? companyName;
  /// Organisations: CAC registration (RC) number, tax ID, number of vehicles, contact person's role.
  final String? rcNumber;
  final String? tin;
  final int? fleetSize;
  final String? contactRole;
  final String? nin;
  final String? nextOfKinName;
  final String? nextOfKinPhone;
  final String licenceNumber;
  final String licenceClass;
  final DateTime licenceExpiry;
  final String vehicleMake;
  final String vehicleModel;
  final int vehicleYear;
  final String vehicleColour;
  final String plateNumber;
  final String chassisNumber;
  final String? engineNumber;
  final int seats;
  final List<DocumentFile> documents;
  final DateTime createdAt;
  final AiDocumentCheck? aiCheck;
  final String? reviewerNote;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? providerId;
  final String? vehicleId;

  String get displayName => (companyName?.trim().isNotEmpty ?? false) ? companyName!.trim() : fullName;

  String get vehicleLabel => '$vehicleYear $vehicleMake $vehicleModel · $vehicleColour';

  PartnerApplication copyWith({ApplicationStatus? status, String? reviewerNote, String? reviewedBy, DateTime? reviewedAt, String? providerId, String? vehicleId, List<DocumentFile>? documents, AiDocumentCheck? aiCheck}) =>
      PartnerApplication(
        id: id,
        userId: userId,
        type: type,
        status: status ?? this.status,
        fullName: fullName,
        email: email,
        phone: phone,
        dateOfBirth: dateOfBirth,
        address: address,
        area: area,
        companyName: companyName,
        rcNumber: rcNumber,
        tin: tin,
        fleetSize: fleetSize,
        contactRole: contactRole,
        nin: nin,
        nextOfKinName: nextOfKinName,
        nextOfKinPhone: nextOfKinPhone,
        licenceNumber: licenceNumber,
        licenceClass: licenceClass,
        licenceExpiry: licenceExpiry,
        vehicleMake: vehicleMake,
        vehicleModel: vehicleModel,
        vehicleYear: vehicleYear,
        vehicleColour: vehicleColour,
        plateNumber: plateNumber,
        chassisNumber: chassisNumber,
        engineNumber: engineNumber,
        seats: seats,
        documents: documents ?? this.documents,
        createdAt: createdAt,
        aiCheck: aiCheck ?? this.aiCheck,
        reviewerNote: reviewerNote ?? this.reviewerNote,
        reviewedBy: reviewedBy ?? this.reviewedBy,
        reviewedAt: reviewedAt ?? this.reviewedAt,
        providerId: providerId ?? this.providerId,
        vehicleId: vehicleId ?? this.vehicleId,
      );

  static String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Fields the applicant typed (used for submission and for the AI comparison).
  Map<String, Object?> toJson() => {
        'id': id,
        'user_id': userId,
        'partner_type': type.wire,
        'status': status.wire,
        'full_name': fullName,
        'email': email,
        'phone': phone,
        'date_of_birth': _date(dateOfBirth),
        'address': address,
        'area': area,
        'company_name': companyName,
        'rc_number': rcNumber,
        'tin': tin,
        'fleet_size': fleetSize,
        'contact_role': contactRole,
        'nin': nin,
        'next_of_kin_name': nextOfKinName,
        'next_of_kin_phone': nextOfKinPhone,
        'licence_number': licenceNumber,
        'licence_class': licenceClass,
        'licence_expiry': _date(licenceExpiry),
        'vehicle_make': vehicleMake,
        'vehicle_model': vehicleModel,
        'vehicle_year': vehicleYear,
        'vehicle_colour': vehicleColour,
        'plate_number': plateNumber,
        'chassis_number': chassisNumber,
        'engine_number': engineNumber,
        'seats': seats,
        'documents': [for (final d in documents) d.toJson()],
        'created_at': createdAt.toUtc().toIso8601String(),
        'ai_check': aiCheck?.raw,
        'reviewer_note': reviewerNote,
        'reviewed_by': reviewedBy,
        'reviewed_at': reviewedAt?.toUtc().toIso8601String(),
        'provider_id': providerId,
        'vehicle_id': vehicleId,
      };

  factory PartnerApplication.fromJson(Map<String, dynamic> json) => PartnerApplication(
        id: '${json['id']}',
        userId: '${json['user_id']}',
        type: _byWire(PartnerType.values, json['partner_type'], PartnerType.privateDriver),
        status: _byWire(ApplicationStatus.values, json['status'], ApplicationStatus.submitted),
        fullName: '${json['full_name'] ?? ''}',
        email: '${json['email'] ?? ''}',
        phone: '${json['phone'] ?? ''}',
        dateOfBirth: DateTime.tryParse('${json['date_of_birth']}') ?? DateTime(1990),
        address: '${json['address'] ?? ''}',
        area: '${json['area'] ?? ''}',
        companyName: json['company_name'] as String?,
        rcNumber: json['rc_number'] as String?,
        tin: json['tin'] as String?,
        fleetSize: (json['fleet_size'] as num?)?.toInt(),
        contactRole: json['contact_role'] as String?,
        nin: json['nin'] as String?,
        nextOfKinName: json['next_of_kin_name'] as String?,
        nextOfKinPhone: json['next_of_kin_phone'] as String?,
        licenceNumber: '${json['licence_number'] ?? ''}',
        licenceClass: '${json['licence_class'] ?? ''}',
        licenceExpiry: DateTime.tryParse('${json['licence_expiry']}') ?? DateTime(2000),
        vehicleMake: '${json['vehicle_make'] ?? ''}',
        vehicleModel: '${json['vehicle_model'] ?? ''}',
        vehicleYear: (json['vehicle_year'] as num?)?.toInt() ?? 0,
        vehicleColour: '${json['vehicle_colour'] ?? ''}',
        plateNumber: '${json['plate_number'] ?? ''}',
        chassisNumber: '${json['chassis_number'] ?? ''}',
        engineNumber: json['engine_number'] as String?,
        seats: (json['seats'] as num?)?.toInt() ?? 4,
        documents: [for (final d in (json['documents'] as List? ?? const [])) DocumentFile.fromJson(Map<String, dynamic>.from(d as Map))],
        createdAt: DateTime.tryParse('${json['created_at']}')?.toLocal() ?? DateTime.now(),
        aiCheck: json['ai_check'] is Map ? AiDocumentCheck.fromJson(Map<String, dynamic>.from(json['ai_check'] as Map)) : null,
        reviewerNote: json['reviewer_note'] as String?,
        reviewedBy: json['reviewed_by'] as String?,
        reviewedAt: DateTime.tryParse('${json['reviewed_at'] ?? ''}')?.toLocal(),
        providerId: json['provider_id'] as String?,
        vehicleId: json['vehicle_id'] as String?,
      );
}

/// Format checks run before submission (the backend repeats them).
abstract final class PartnerRules {
  /// 17 characters, letters and digits, never I, O or Q (ISO 3779).
  static String? chassis(String? value) {
    final v = (value ?? '').replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (v.isEmpty) return 'Enter the chassis number (VIN) printed on the vehicle papers.';
    if (v.length != 17) return 'A chassis number (VIN) has exactly 17 characters; this one has ${v.length}.';
    if (RegExp('[IOQ]').hasMatch(v)) return 'A VIN never contains the letters I, O or Q. Check for 1, 0 or 9.';
    if (!RegExp(r'^[A-HJ-NPR-Z0-9]{17}$').hasMatch(v)) return 'Use only letters and numbers.';
    return null;
  }

  /// Nigerian plates, e.g. ABJ 123 AB / ABC-123DE, plus older and fleet formats.
  static String? plate(String? value) {
    final v = (value ?? '').replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (v.isEmpty) return 'Enter the plate number.';
    if (!RegExp(r'^[A-Z]{2,3}\d{2,4}[A-Z]{0,3}$').hasMatch(v)) return 'Use the format on the plate, e.g. ABJ 123 AB.';
    return null;
  }

  static String? licence(String? value) {
    final v = (value ?? '').replaceAll(RegExp(r'\s'), '').toUpperCase();
    if (v.length < 8) return "Enter the full driver's licence number.";
    if (!RegExp(r'^[A-Z0-9-]+$').hasMatch(v)) return 'Use only letters, numbers and dashes.';
    return null;
  }

  static String normalise(String value) => value.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
}

/// Organisation checks (Corporate Affairs Commission and FIRS formats).
abstract final class OrgRules {
  /// CAC numbers: RC 1234567 (companies), BN 1234567 (business names) or IT 12345 (trustees).
  static String? rcNumber(String? value) {
    final v = (value ?? '').replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (v.isEmpty) return 'Enter the CAC registration number, e.g. RC 1234567.';
    if (!RegExp(r'^(RC|BN|IT)?\d{4,8}$').hasMatch(v)) return 'Use the number on the CAC certificate, e.g. RC 1234567.';
    return null;
  }

  /// Nigerian TIN: 8–14 digits (legacy FIRS TIN is 12 digits written 12345678-0001).
  static String? tin(String? value) {
    final v = (value ?? '').replaceAll(RegExp(r'[\s-]'), '');
    if (v.isEmpty) return null; // optional for government agencies
    if (!RegExp(r'^\d{8,14}$').hasMatch(v)) return 'A TIN has 8 to 14 digits.';
    return null;
  }
}
