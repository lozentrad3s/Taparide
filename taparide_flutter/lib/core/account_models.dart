// Rider verification and refunds (migration 20261124000000_verification_refunds.sql).

int _int(Object? v) => v is int ? v : v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
DateTime? _time(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

enum RefundStatus { pending, approved, declined }

extension RefundStatusX on RefundStatus {
  String get wire => name;

  /// How a rider reads it on their booking.
  String get riderLabel => switch (this) {
        RefundStatus.pending => 'Refund requested',
        RefundStatus.approved => 'Refunded',
        RefundStatus.declined => 'Refund declined',
      };

  String get adminLabel => switch (this) {
        RefundStatus.pending => 'Waiting',
        RefundStatus.approved => 'Refunded',
        RefundStatus.declined => 'Declined',
      };

  static RefundStatus fromWire(Object? v) => RefundStatus.values.firstWhere((s) => s.name == '$v', orElse: () => RefundStatus.pending);
}

/// A rider's own refund request (their row of `refund_requests`).
class RefundRequest {
  const RefundRequest({
    required this.id,
    required this.bookingId,
    required this.amount,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.adminNote,
    this.reviewedAt,
  });

  final int id;
  final String bookingId;
  final int amount;
  final String reason;
  final RefundStatus status;
  final String? adminNote;
  final DateTime createdAt;
  final DateTime? reviewedAt;

  factory RefundRequest.fromJson(Map<String, dynamic> j) => RefundRequest(
        id: _int(j['id']),
        bookingId: '${j['booking_id'] ?? j['booking'] ?? ''}',
        amount: _int(j['amount']),
        reason: '${j['reason'] ?? ''}',
        status: RefundStatusX.fromWire(j['status']),
        adminNote: (j['admin_note'] ?? j['note']) as String?,
        createdAt: _time(j['created_at']) ?? DateTime.now(),
        reviewedAt: _time(j['reviewed_at']),
      );
}

/// A refund request as admins see it (with the rider and the booking).
class AdminRefund {
  const AdminRefund({
    required this.id,
    required this.bookingId,
    required this.amount,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.note,
    this.reviewedAt,
    this.rider,
    this.email,
    this.phone,
    this.title,
    this.kind,
    this.departureAt,
    this.bookingStatus,
    this.ticket,
    this.operator,
  });

  final int id;
  final String bookingId;
  final int amount;
  final String reason;
  final RefundStatus status;
  final String? note;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String? rider;
  final String? email;
  final String? phone;
  final String? title;
  final String? kind;
  final DateTime? departureAt;
  final String? bookingStatus;
  final String? ticket;
  final String? operator;

  factory AdminRefund.fromJson(Map<String, dynamic> j) => AdminRefund(
        id: _int(j['id']),
        bookingId: '${j['booking'] ?? ''}',
        amount: _int(j['amount']),
        reason: '${j['reason'] ?? ''}',
        status: RefundStatusX.fromWire(j['status']),
        note: j['note'] as String?,
        createdAt: _time(j['created_at']) ?? DateTime.now(),
        reviewedAt: _time(j['reviewed_at']),
        rider: j['rider'] as String?,
        email: j['email'] as String?,
        phone: j['phone'] as String?,
        title: j['title'] as String?,
        kind: j['kind'] as String?,
        departureAt: _time(j['departure_at']),
        bookingStatus: j['booking_status'] as String?,
        ticket: j['ticket'] as String?,
        operator: j['operator'] as String?,
      );
}

/// A rider's verification as admins review it.
class RiderVerification {
  const RiderVerification({
    required this.id,
    required this.name,
    required this.email,
    required this.status,
    this.phone,
    this.nin,
    this.dateOfBirth,
    this.homeArea,
    this.emergencyName,
    this.emergencyPhone,
    this.note,
    this.submittedAt,
    this.verifiedAt,
    this.createdAt,
    this.phoneShared = false,
  });

  final String id;
  final String name;
  final String email;
  final String status; // unverified | pending | verified | rejected
  final String? phone;
  final String? nin;
  final DateTime? dateOfBirth;
  final String? homeArea;
  final String? emergencyName;
  final String? emergencyPhone;
  final String? note;
  final DateTime? submittedAt;
  final DateTime? verifiedAt;
  final DateTime? createdAt;

  /// Another account uses the same phone number (possible duplicate).
  final bool phoneShared;

  int? get age {
    final d = dateOfBirth;
    if (d == null) return null;
    final now = DateTime.now();
    var a = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) a--;
    return a;
  }

  factory RiderVerification.fromJson(Map<String, dynamic> j) => RiderVerification(
        id: '${j['id']}',
        name: '${j['name'] ?? 'Rider'}',
        email: '${j['email'] ?? ''}',
        status: '${j['status'] ?? 'unverified'}',
        phone: j['phone'] as String?,
        nin: j['nin'] as String?,
        dateOfBirth: j['date_of_birth'] == null ? null : DateTime.tryParse('${j['date_of_birth']}'),
        homeArea: j['home_area'] as String?,
        emergencyName: j['emergency_name'] as String?,
        emergencyPhone: j['emergency_phone'] as String?,
        note: j['note'] as String?,
        submittedAt: _time(j['submitted_at']),
        verifiedAt: _time(j['verified_at']),
        createdAt: _time(j['created_at']),
        phoneShared: j['phone_shared'] == true,
      );
}
