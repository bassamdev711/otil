import 'dart:convert';

import 'package:http/http.dart' as http;

import '../local/hotel_local_store.dart';

class RemoteHotelStore implements HotelDataSource {
  RemoteHotelStore({required String baseUrl, required this.token}) : baseUrl = baseUrl.replaceFirst(RegExp(r'/$'), '');

  final String baseUrl;
  final String token;
  final Map<String, List<Map<String, dynamic>>> _collections = {};
  final Map<String, dynamic> _meta = {};
  Future<void> _writeChain = Future<void>.value();

  Uri _uri(String path) => Uri.parse('$baseUrl$path').replace(queryParameters: {'token': token});

  Future<void> refresh() => migrate();

  Future<void> migrate() async {
    final response = await http.get(_uri('/api/v1/state')).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw StateError('تعذر الاتصال بقاعدة الهاتف (${response.statusCode})');
    }
    final payload = jsonDecode(response.body);
    if (payload is! Map) throw const FormatException('استجابة قاعدة الهاتف غير صالحة');
    for (final collection in const ['users', 'rooms', 'guests', 'bookings']) {
      final raw = payload[collection];
      _collections[collection] = raw is List ? raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList() : <Map<String, dynamic>>[];
    }
    _meta['hotelName'] = payload['hotelName'];
    _meta['seeded'] = true;
    _meta['schemaVersion'] = HotelLocalStore.currentSchemaVersion;
  }

  List<Map<String, dynamic>> readCollection(String collection) => List<Map<String, dynamic>>.unmodifiable(_collections[collection] ?? const []);

  dynamic readMeta(String key, {dynamic defaultValue}) => _meta[key] ?? defaultValue;

  Future<void> putMeta(String key, dynamic value) => _enqueue(() async {
        final response = await http.put(_uri('/api/v1/meta/${Uri.encodeComponent(key)}'), headers: {'content-type': 'application/json'}, body: jsonEncode({'value': value})).timeout(const Duration(seconds: 8));
        _check(response);
        _meta[key] = value;
      });

  Future<void> upsert(String collection, String id, Map<String, dynamic> value) => _enqueue(() async {
        final next = <Map<String, dynamic>>[...(_collections[collection] ?? const <Map<String, dynamic>>[])];
        final index = next.indexWhere((item) => item['id']?.toString() == id);
        if (index == -1) {
          next.add(Map<String, dynamic>.from(value));
        } else {
          next[index] = Map<String, dynamic>.from(value);
        }
        await _replace(collection, next);
      });

  Future<void> replaceCollection(String collection, Iterable<Map<String, dynamic>> values) => _enqueue(() => _replace(collection, values.toList()));

  Future<void> _replace(String collection, List<Map<String, dynamic>> values) async {
    final response = await http.put(_uri('/api/v1/collection/${Uri.encodeComponent(collection)}'), headers: {'content-type': 'application/json'}, body: jsonEncode({'values': values})).timeout(const Duration(seconds: 8));
    _check(response);
    _collections[collection] = values.map(Map<String, dynamic>.from).toList();
  }

  void _check(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('تعذر حفظ البيانات على الهاتف (${response.statusCode})');
    }
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _writeChain.then((_) => operation());
    _writeChain = next.catchError((_) {});
    return next;
  }
}
