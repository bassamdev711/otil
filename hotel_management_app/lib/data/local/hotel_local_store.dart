import 'package:hive/hive.dart';

/// Stable data-source boundary shared by the offline implementation and the
/// future Firestore implementation. UI code should depend on this contract.
abstract interface class HotelDataSource {
  Future<void> migrate();
  List<Map<String, dynamic>> readCollection(String collection);
  dynamic readMeta(String key, {dynamic defaultValue});
  Future<void> putMeta(String key, dynamic value);
  Future<void> upsert(String collection, String id, Map<String, dynamic> value);
  Future<void> replaceCollection(String collection, Iterable<Map<String, dynamic>> values);
}

/// Local persistence boundary. The controller depends on this API instead of
/// knowing how records are laid out in Hive, so a Firestore implementation can
/// replace it later without changing the UI layer.
class HotelLocalStore implements HotelDataSource {
  HotelLocalStore(this.box);

  final Box box;
  static const int currentSchemaVersion = 2;
  Future<void> _writeChain = Future<void>.value();

  Future<void> migrate() async {
    final version = (box.get('schemaVersion') as num?)?.toInt() ?? 1;
    if (version >= currentSchemaVersion) return;

    await _enqueue(() async {
      for (final collection in const ['users', 'rooms', 'guests', 'bookings']) {
        final legacy = box.get(collection);
        if (legacy is List) {
          for (final item in legacy) {
            if (item is Map && item['id'] != null) {
              await box.put(_key(collection, item['id'].toString()), Map<String, dynamic>.from(item));
            }
          }
          await box.delete(collection);
        }
      }
      await box.put('schemaVersion', currentSchemaVersion);
    });
  }

  List<Map<String, dynamic>> readCollection(String collection) {
    final prefix = '$collection:';
    return box.keys.whereType<String>().where((key) => key.startsWith(prefix)).map((key) {
      final value = box.get(key);
      return value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
    }).where((value) => value.isNotEmpty).toList(growable: false);
  }

  dynamic readMeta(String key, {dynamic defaultValue}) => box.get(key, defaultValue: defaultValue);

  Future<void> putMeta(String key, dynamic value) => _enqueue(() => box.put(key, value));

  Future<void> upsert(String collection, String id, Map<String, dynamic> value) => _enqueue(() => box.put(_key(collection, id), value));

  Future<void> replaceCollection(String collection, Iterable<Map<String, dynamic>> values) => _enqueue(() async {
        for (final value in values) {
          final id = value['id']?.toString();
          if (id != null) await box.put(_key(collection, id), value);
        }
      });

  String _key(String collection, String id) => '$collection:$id';

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _writeChain.then((_) => operation());
    _writeChain = next.catchError((_) {});
    return next;
  }
}
