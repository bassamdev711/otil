import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

import '../local/hotel_local_store.dart';

class LanServerController {
  HttpServer? _server;
  HotelDataSource? _store;
  String? _token;
  int? _port;
  String? _address;

  bool get running => _server != null;
  String? get token => _token;
  String? get address => _address;
  String? get url => _address == null ? null : 'http://$_address:$_port';

  Future<void> start(HotelDataSource store, {int port = 8787}) async {
    if (running) return;
    _store = store;
    _token = _newToken();
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
    } on SocketException {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0, shared: true);
    }
    _port = _server!.port;
    _address = await _findLanAddress();
    unawaited(_serve(_server!));
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _store = null;
    if (server != null) await server.close(force: true);
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handle(request));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      request.response.headers
        ..set('Access-Control-Allow-Origin', '*')
        ..set('Access-Control-Allow-Headers', 'Content-Type, X-Miftah-Token')
        ..set('Access-Control-Allow-Methods', 'GET, PUT, OPTIONS')
        ..contentType = ContentType.json;
      if (request.method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      }
      final store = _store;
      if (store == null) {
        await _write(request, HttpStatus.serviceUnavailable, {'error': 'server_not_ready'});
        return;
      }
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/' && !_authorized(request)) {
        final webUrl = 'http://${_address ?? '127.0.0.1'}:$_port/';
        final redirect = Uri.parse(webUrl).replace(queryParameters: {
          'miftahApi': 'http://${_address ?? '127.0.0.1'}:$_port',
          'miftahToken': _token!,
        });
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, redirect.toString());
        await request.response.close();
        return;
      }
      if (request.method == 'GET' && path.startsWith('/api/')) {
        if (!_authorized(request)) {
          await _write(request, HttpStatus.unauthorized, {'error': 'unauthorized'});
          return;
        }
      } else if (request.method == 'GET') {
        await _serveWebAsset(request, path);
        return;
      } else if (!_authorized(request)) {
        await _write(request, HttpStatus.unauthorized, {'error': 'unauthorized'});
        return;
      }
      if (request.method == 'GET' && path == '/api/v1/ping') {
        await _write(request, HttpStatus.ok, {'ok': true, 'service': 'miftah-lan'});
      } else if (request.method == 'GET' && path == '/api/v1/state') {
        await _write(request, HttpStatus.ok, {
          'hotelName': store.readMeta('hotelName', defaultValue: 'مفتاح لإدارة الفندق'),
          'users': store.readCollection('users'),
          'rooms': store.readCollection('rooms'),
          'guests': store.readCollection('guests'),
          'bookings': store.readCollection('bookings'),
        });
      } else if (request.method == 'PUT' && path.startsWith('/api/v1/collection/')) {
        final collection = Uri.decodeComponent(path.substring('/api/v1/collection/'.length));
        if (!const ['users', 'rooms', 'guests', 'bookings'].contains(collection)) {
          await _write(request, HttpStatus.badRequest, {'error': 'invalid_collection'});
          return;
        }
        final body = await utf8.decoder.bind(request).join();
        final payload = jsonDecode(body);
        final values = payload is Map && payload['values'] is List ? (payload['values'] as List).whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList() : null;
        if (values == null) {
          await _write(request, HttpStatus.badRequest, {'error': 'values_required'});
          return;
        }
        await store.replaceCollection(collection, values);
        await _write(request, HttpStatus.ok, {'ok': true});
      } else if (request.method == 'PUT' && path.startsWith('/api/v1/meta/')) {
        final key = Uri.decodeComponent(path.substring('/api/v1/meta/'.length));
        final body = await utf8.decoder.bind(request).join();
        final payload = jsonDecode(body);
        await store.putMeta(key, payload is Map ? payload['value'] : payload);
        await _write(request, HttpStatus.ok, {'ok': true});
      } else {
        await _write(request, HttpStatus.notFound, {'error': 'not_found'});
      }
    } catch (error) {
      await _write(request, HttpStatus.internalServerError, {'error': error.toString()});
    }
  }

  bool _authorized(HttpRequest request) => request.uri.queryParameters['token'] == _token || request.uri.queryParameters['miftahToken'] == _token || request.headers.value('x-miftah-token') == _token;

  Future<void> _serveWebAsset(HttpRequest request, String requestedPath) async {
    var relative = requestedPath == '/' || requestedPath.isEmpty ? 'index.html' : requestedPath.substring(1);
    relative = Uri.decodeComponent(relative);
    if (relative.contains('..') || relative.contains('\\')) {
      await _write(request, HttpStatus.badRequest, {'error': 'invalid_path'});
      return;
    }
    try {
      final data = await rootBundle.load('assets/lan_web/$relative');
      final type = _contentType(relative);
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = type
        ..headers.set(HttpHeaders.cacheControlHeader, relative == 'index.html' ? 'no-cache' : 'public, max-age=3600')
        ..add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      await request.response.close();
    } catch (_) {
      if (relative.contains('.')) {
        await _write(request, HttpStatus.notFound, {'error': 'asset_not_found'});
      } else {
        final data = await rootBundle.load('assets/lan_web/index.html');
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
        await request.response.close();
      }
    }
  }

  ContentType _contentType(String path) {
    final extension = path.split('.').last.toLowerCase();
    return switch (extension) {
      'html' => ContentType.html,
      'js' => ContentType('application', 'javascript', charset: 'utf-8'),
      'json' => ContentType.json,
      'css' => ContentType('text', 'css', charset: 'utf-8'),
      'png' => ContentType('image', 'png'),
      'jpg' || 'jpeg' => ContentType('image', 'jpeg'),
      'svg' => ContentType('image', 'svg+xml'),
      'wasm' => ContentType('application', 'wasm'),
      'woff' || 'woff2' => ContentType('font', 'woff'),
      'ttf' => ContentType('font', 'ttf'),
      'ico' => ContentType('image', 'x-icon'),
      _ => ContentType.binary,
    };
  }

  Future<void> _write(HttpRequest request, int status, Map<String, dynamic> payload) async {
    request.response.statusCode = status;
    request.response.write(jsonEncode(payload));
    await request.response.close();
  }

  String _newToken() {
    final random = Random.secure();
    return base64UrlEncode(List<int>.generate(24, (_) => random.nextInt(256))).replaceAll('=', '');
  }

  Future<String> _findLanAddress() async {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLinkLocal: false);
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback && address.address != '0.0.0.0') return address.address;
      }
    }
    return '127.0.0.1';
  }
}
