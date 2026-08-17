import 'package:flutter_test/flutter_test.dart';

import 'package:hotel_management_app/data/local/backup_codec.dart';
import 'package:hotel_management_app/main.dart';

void main() {
  test('password hashing is deterministic and salt-aware', () {
    expect(hashPassword('admin123'), hashPassword('admin123'));
    expect(hashPassword('admin123'), isNot(hashPassword('wrong')));
    expect(hashPassword('admin123', salt: 'salt-a'), isNot(hashPassword('admin123', salt: 'salt-b')));
    expect(hashPassword('admin123', salt: 'salt-a'), isNot(hashPassword('admin123')));
  });

  test('encrypted backups round-trip and reject wrong passwords', () async {
    final payload = <String, dynamic>{'format': 'miftah-backup', 'version': 1, 'rooms': []};
    final encrypted = await BackupCodec.encrypt(payload, 'strong-pass');
    final restored = await BackupCodec.decrypt(encrypted, 'strong-pass');
    expect(restored['format'], 'miftah-backup');
    await expectLater(BackupCodec.decrypt(encrypted, 'wrong-pass'), throwsA(anything));
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

  test('first-run password change flag survives serialization', () {
    final user = UserRecord(id: 'u1', name: 'مدير', username: 'admin', passwordHash: 'hash', passwordSalt: 'salt', role: 'admin', mustChangePassword: true);
    final restored = UserRecord.fromMap(user.toMap());
    expect(restored.mustChangePassword, isTrue);
  });
}
