import 'package:flutter_test/flutter_test.dart';

import 'package:hotel_management_app/main.dart';

void main() {
  test('password hashing is deterministic', () {
    expect(hashPassword('admin123'), hashPassword('admin123'));
    expect(hashPassword('admin123'), isNot(hashPassword('wrong')));
  });

  test('status labels are localized', () {
    expect(statusLabel('available'), 'شاغرة');
    expect(statusLabel('occupied'), 'مشغولة');
    expect(statusLabel('maintenance'), 'صيانة');
  });

  test('room and guest records serialize correctly', () {
    final room = RoomRecord(id: 'r1', number: '101', type: 'مفردة', floor: 1, price: 180, status: 'available');
    final guest = GuestRecord(id: 'g1', name: 'أحمد', phone: '0500', nationalId: '1', nationality: 'سعودي');
    expect(RoomRecord.fromMap(room.toMap()).number, '101');
    expect(GuestRecord.fromMap(guest.toMap()).name, 'أحمد');
  });
}
