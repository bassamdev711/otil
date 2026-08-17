import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'data/local/backup_codec.dart';
import 'data/local/hotel_local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart' as pp;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();
final _dateFormat = DateFormat('dd/MM/yyyy');
final _moneyFormat = NumberFormat('#,##0.00', 'en_US');

const _secureStorage = FlutterSecureStorage();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final encryptionKey = await _loadHiveKey();
  final secureBox = await Hive.openBox('hotel_data_secure', encryptionCipher: HiveAesCipher(encryptionKey));
  if (await Hive.boxExists('hotel_data')) {
    final legacyBox = await Hive.openBox('hotel_data');
    if (secureBox.isEmpty && legacyBox.isNotEmpty) {
      for (final key in legacyBox.keys) {
        await secureBox.put(key, legacyBox.get(key));
      }
    }
    await legacyBox.close();
    await Hive.deleteBoxFromDisk('hotel_data');
  }
  runApp(const ProviderScope(child: HotelApp()));
}

Future<List<int>> _loadHiveKey() async {
  const keyName = 'hotel_hive_encryption_key';
  try {
    final stored = await _secureStorage.read(key: keyName);
    if (stored != null && stored.length >= 32) return base64Url.decode(stored);
    final random = Random.secure();
    final generated = base64UrlEncode(List<int>.generate(32, (_) => random.nextInt(256)));
    await _secureStorage.write(key: keyName, value: generated);
    return base64Url.decode(generated);
  } catch (_) {
    // WebCrypto requires HTTPS or localhost. The LAN HTTP mode uses a stable
    // fallback key so the app remains usable; production should use HTTPS.
    final fallback = await Hive.openBox('hotel_key_fallback');
    try {
      var stored = fallback.get(keyName) as String?;
      if (stored == null || stored.length < 32) {
        final random = Random.secure();
        stored = base64UrlEncode(List<int>.generate(32, (_) => random.nextInt(256)));
        await fallback.put(keyName, stored);
      }
      return base64Url.decode(stored);
    } finally {
      await fallback.close();
    }
  }
}

final appControllerProvider = ChangeNotifierProvider<AppController>((ref) {
  return AppController()..initialize();
});

String hashPassword(String value, {String salt = ''}) => sha256.convert(utf8.encode(salt.isEmpty ? value : '$salt:$value')).toString();
String dateLabel(DateTime value) => _dateFormat.format(value);

String statusLabel(String status) => {'available': 'شاغرة', 'occupied': 'مشغولة', 'cleaning': 'تنظيف', 'maintenance': 'صيانة', 'pending': 'معلقة', 'checkedIn': 'داخل الفندق', 'checkedOut': 'مغادر', 'cancelled': 'ملغاة'}[status] ?? status;
Color statusColor(String status) => {'available': Colors.green, 'occupied': Colors.orange, 'cleaning': Colors.teal, 'maintenance': Colors.red, 'pending': Colors.blue, 'checkedIn': Colors.green, 'checkedOut': Colors.grey, 'cancelled': Colors.red}[status] ?? Colors.grey;
String roleLabel(String? role) => {'admin': 'مدير النظام', 'receptionist': 'موظف استقبال', 'nightShift': 'وردية ليلية', 'dayShift': 'وردية نهارية'}[role] ?? 'مستخدم';

class UserRecord {
  UserRecord({required this.id, required this.name, required this.username, required this.passwordHash, required this.role, this.passwordSalt = '', this.isActive = true});
  final String id;
  final String name;
  final String username;
  String passwordHash;
  final String role;
  final String passwordSalt;
  final bool isActive;

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'username': username, 'passwordHash': passwordHash, 'passwordSalt': passwordSalt, 'role': role, 'isActive': isActive};
  factory UserRecord.fromMap(Map map) => UserRecord(id: map['id'], name: map['name'], username: map['username'], passwordHash: map['passwordHash'], passwordSalt: map['passwordSalt'] ?? '', role: map['role'], isActive: map['isActive'] ?? true);
}

class RoomRecord {
  RoomRecord({required this.id, required this.number, required this.type, required this.floor, required this.price, required this.status, this.notes = ''});
  final String id;
  final String number;
  final String type;
  final int floor;
  final double price;
  String status;
  final String notes;

  Map<String, dynamic> toMap() => {'id': id, 'number': number, 'type': type, 'floor': floor, 'price': price, 'status': status, 'notes': notes};
  factory RoomRecord.fromMap(Map map) => RoomRecord(id: map['id'], number: map['number'], type: map['type'], floor: map['floor'], price: (map['price'] as num).toDouble(), status: map['status'], notes: map['notes'] ?? '');
}

class GuestRecord {
  GuestRecord({required this.id, required this.name, required this.phone, required this.nationalId, required this.nationality, this.email = ''});
  final String id;
  final String name;
  final String phone;
  final String nationalId;
  final String nationality;
  final String email;

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'phone': phone, 'nationalId': nationalId, 'nationality': nationality, 'email': email};
  factory GuestRecord.fromMap(Map map) => GuestRecord(id: map['id'], name: map['name'], phone: map['phone'], nationalId: map['nationalId'], nationality: map['nationality'], email: map['email'] ?? '');
}

class BookingRecord {
  BookingRecord({required this.id, required this.number, required this.guestId, required this.roomId, required this.checkIn, required this.checkOut, required this.status, required this.total, this.notes = ''});
  final String id;
  final String number;
  final String guestId;
  final String roomId;
  final DateTime checkIn;
  final DateTime checkOut;
  String status;
  final double total;
  final String notes;

  Map<String, dynamic> toMap() => {'id': id, 'number': number, 'guestId': guestId, 'roomId': roomId, 'checkIn': checkIn.toIso8601String(), 'checkOut': checkOut.toIso8601String(), 'status': status, 'total': total, 'notes': notes};
  factory BookingRecord.fromMap(Map map) => BookingRecord(id: map['id'], number: map['number'], guestId: map['guestId'], roomId: map['roomId'], checkIn: DateTime.parse(map['checkIn']), checkOut: DateTime.parse(map['checkOut']), status: map['status'], total: (map['total'] as num).toDouble(), notes: map['notes'] ?? '');
}

class AppController extends ChangeNotifier {
  final Box _box = Hive.box('hotel_data_secure');
  late final HotelDataSource _store = HotelLocalStore(_box);
  bool initialized = false;
  UserRecord? currentUser;
  List<UserRecord> users = [];
  List<RoomRecord> rooms = [];
  List<GuestRecord> guests = [];
  List<BookingRecord> bookings = [];
  String hotelName = 'مفتاح لإدارة الفندق';
  final Map<String, GuestRecord> _guestIndex = {};
  final Map<String, RoomRecord> _roomIndex = {};
  final Map<String, BookingRecord> _activeBookingByRoom = {};
  final Map<String, int> _statusCounts = {};
  final Map<String, int> _bookingCountByGuest = {};

  void _rebuildIndexes() {
    _guestIndex
      ..clear()
      ..addEntries(guests.map((guest) => MapEntry(guest.id, guest)));
    _roomIndex
      ..clear()
      ..addEntries(rooms.map((room) => MapEntry(room.id, room)));
    _activeBookingByRoom.clear();
    _statusCounts.clear();
    for (final room in rooms) {
      _statusCounts[room.status] = (_statusCounts[room.status] ?? 0) + 1;
    }
    _bookingCountByGuest.clear();
    for (final booking in bookings) {
      _bookingCountByGuest[booking.guestId] = (_bookingCountByGuest[booking.guestId] ?? 0) + 1;
      if (booking.status == 'checkedIn' || booking.status == 'pending') _activeBookingByRoom[booking.roomId] = booking;
    }
  }

  Future<void> initialize() async {
    await _store.migrate();
    final raw = _store.readMeta('seeded');
    if (raw != true) {
      final adminSalt = _uuid.v4();
      users = [UserRecord(id: _uuid.v4(), name: 'مدير النظام', username: 'admin', passwordHash: hashPassword('admin123', salt: adminSalt), passwordSalt: adminSalt, role: 'admin')];
      rooms = [
        RoomRecord(id: _uuid.v4(), number: '101', type: 'مفردة', floor: 1, price: 180, status: 'available'),
        RoomRecord(id: _uuid.v4(), number: '102', type: 'مزدوجة', floor: 1, price: 260, status: 'occupied'),
        RoomRecord(id: _uuid.v4(), number: '201', type: 'جناح', floor: 2, price: 520, status: 'available'),
        RoomRecord(id: _uuid.v4(), number: '202', type: 'VIP', floor: 2, price: 780, status: 'cleaning'),
        RoomRecord(id: _uuid.v4(), number: '301', type: 'مزدوجة', floor: 3, price: 310, status: 'maintenance'),
        RoomRecord(id: _uuid.v4(), number: '302', type: 'مفردة', floor: 3, price: 180, status: 'available'),
      ];
      guests = [
        GuestRecord(id: _uuid.v4(), name: 'أحمد محمد', phone: '0501234567', nationalId: '1020304050', nationality: 'سعودي'),
        GuestRecord(id: _uuid.v4(), name: 'سارة علي', phone: '0507654321', nationalId: '2030405060', nationality: 'سعودية'),
      ];
      bookings = [BookingRecord(id: _uuid.v4(), number: 'BK-1001', guestId: guests[0].id, roomId: rooms[1].id, checkIn: DateTime.now().subtract(const Duration(days: 1)), checkOut: DateTime.now().add(const Duration(days: 2)), status: 'checkedIn', total: 780)];
      await _save();
      await _store.putMeta('seeded', true);
    } else {
      users = _readList('users', UserRecord.fromMap);
      rooms = _readList('rooms', RoomRecord.fromMap);
      guests = _readList('guests', GuestRecord.fromMap);
      bookings = _readList('bookings', BookingRecord.fromMap);
      hotelName = _store.readMeta('hotelName', defaultValue: hotelName);
      if (hotelName == 'فندق النخبة' || hotelName == 'النخبة') {
        hotelName = 'مفتاح لإدارة الفندق';
        await _store.putMeta('hotelName', hotelName);
      }
    }
    _rebuildIndexes();
    initialized = true;
    notifyListeners();
  }

  List<T> _readList<T>(String key, T Function(Map) parser) => _store.readCollection(key).map(parser).toList();

  Future<void> _save() async {
    await Future.wait([
      _store.replaceCollection('users', users.map((e) => e.toMap())),
      _store.replaceCollection('rooms', rooms.map((e) => e.toMap())),
      _store.replaceCollection('guests', guests.map((e) => e.toMap())),
      _store.replaceCollection('bookings', bookings.map((e) => e.toMap())),
      _store.putMeta('hotelName', hotelName),
      _store.putMeta('schemaVersion', HotelLocalStore.currentSchemaVersion),
    ]);
  }

  int failedLoginAttempts = 0;
  DateTime? loginLockedUntil;
  bool get isLoginLocked => loginLockedUntil != null && DateTime.now().isBefore(loginLockedUntil!);

  bool login(String username, String password) {
    if (isLoginLocked) return false;
    final normalizedUsername = username.trim().toLowerCase();
    UserRecord? match;
    for (final user in users) {
      final validHash = user.passwordSalt.isEmpty ? hashPassword(password) : hashPassword(password, salt: user.passwordSalt);
      if (user.username.toLowerCase() == normalizedUsername && user.passwordHash == validHash && user.isActive) {
        match = user;
        break;
      }
    }
    if (match == null) {
      failedLoginAttempts += 1;
      if (failedLoginAttempts >= 5) {
        loginLockedUntil = DateTime.now().add(const Duration(seconds: 30));
        failedLoginAttempts = 0;
      }
      notifyListeners();
      return false;
    }
    failedLoginAttempts = 0;
    loginLockedUntil = null;
    currentUser = match;
    notifyListeners();
    return true;
  }

  void logout() { currentUser = null; notifyListeners(); }
  GuestRecord? guestById(String id) => _guestIndex[id];
  RoomRecord? roomById(String id) => _roomIndex[id];
  BookingRecord? activeBookingForRoom(String roomId) => _activeBookingByRoom[roomId];

  List<RoomRecord> queryRooms({String query = '', String? status, String? type, int? floor}) {
    final q = query.trim().toLowerCase();
    return rooms.where((room) {
      final activeBooking = activeBookingForRoom(room.id);
      final guest = activeBooking == null ? null : guestById(activeBooking.guestId);
      final matchesQuery = q.isEmpty || room.number.toLowerCase().contains(q) || room.type.toLowerCase().contains(q) || (guest?.name.toLowerCase().contains(q) ?? false);
      return matchesQuery && (status == null || room.status == status) && (type == null || room.type == type) && (floor == null || room.floor == floor);
    }).toList(growable: false);
  }

  List<GuestRecord> queryGuests(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return List<GuestRecord>.unmodifiable(guests);
    return guests.where((guest) => '${guest.name} ${guest.phone} ${guest.nationalId} ${guest.nationality}'.toLowerCase().contains(q)).toList(growable: false);
  }

  bool get isAdmin => currentUser?.role == 'admin';
  bool get canManageFrontDesk => isAdmin || currentUser?.role == 'receptionist';
  bool get canOperateStay => canManageFrontDesk || currentUser?.role == 'nightShift' || currentUser?.role == 'dayShift';
  int roomCountByStatus(String status) => _statusCounts[status] ?? 0;
  int stayCountForGuest(String guestId) => _bookingCountByGuest[guestId] ?? 0;
  int get occupiedRooms => roomCountByStatus('occupied');
  int get availableRooms => roomCountByStatus('available');
  int get maintenanceRooms => roomCountByStatus('maintenance');
  double get occupancy => rooms.isEmpty ? 0 : occupiedRooms / rooms.length;
  double get revenue => bookings.where((e) => e.status != 'cancelled').fold(0, (sum, e) => sum + e.total);

  Future<void> addRoom(String number, String type, int floor, double price) async { final normalized = number.trim(); if (!canManageFrontDesk || normalized.isEmpty || floor < 1 || price <= 0 || rooms.any((room) => room.number.toLowerCase() == normalized.toLowerCase())) return; rooms.add(RoomRecord(id: _uuid.v4(), number: normalized, type: type, floor: floor, price: price, status: 'available')); _rebuildIndexes(); await _save(); notifyListeners(); }
  Future<void> updateRoomStatus(RoomRecord room, String status) async { if (!canManageFrontDesk) return; room.status = status; _rebuildIndexes(); await _save(); notifyListeners(); }
  Future<void> addGuest(String name, String phone, String nationalId, String nationality, String email) async { if (!canManageFrontDesk) return; guests.add(GuestRecord(id: _uuid.v4(), name: name, phone: phone, nationalId: nationalId, nationality: nationality, email: email)); _rebuildIndexes(); await _save(); notifyListeners(); }
  Future<void> addBooking(String guestId, String roomId, DateTime start, DateTime end, String notes) async {
    if (!canManageFrontDesk || !guests.any((guest) => guest.id == guestId) || end.isBefore(start) || !rooms.any((room) => room.id == roomId && room.status == 'available')) return;
    final room = roomById(roomId)!;
    final nights = end.difference(start).inDays.clamp(1, 365).toDouble();
    bookings.insert(0, BookingRecord(id: _uuid.v4(), number: 'BK-${1000 + bookings.length + 1}', guestId: guestId, roomId: roomId, checkIn: start, checkOut: end, status: 'pending', total: room.price * nights, notes: notes));
    await _save();
    _rebuildIndexes();
    notifyListeners();
  }
  Future<void> changeBookingStatus(BookingRecord booking, String status) async { if (!canOperateStay) return; booking.status = status; final room = roomById(booking.roomId); if (room != null && status == 'checkedIn') room.status = 'occupied'; if (room != null && status == 'checkedOut') room.status = 'cleaning'; _rebuildIndexes(); await _save(); notifyListeners(); }
  Future<void> addUser(String name, String username, String password, String role) async { if (!isAdmin || name.trim().isEmpty || username.trim().length < 3 || password.length < 8 || users.any((user) => user.username == username.trim().toLowerCase())) return; final salt = _uuid.v4(); users.add(UserRecord(id: _uuid.v4(), name: name, username: username.trim().toLowerCase(), passwordHash: hashPassword(password, salt: salt), passwordSalt: salt, role: role)); await _save(); notifyListeners(); }
  Future<void> updateHotelName(String value) async { if (!isAdmin) return; hotelName = value.trim().isEmpty ? 'مفتاح لإدارة الفندق' : value.trim(); await _save(); notifyListeners(); }

  Map<String, dynamic> exportBackup() {
    if (!isAdmin) throw StateError('Admin access required');
    return {'format': 'miftah-backup', 'version': 1, 'createdAt': DateTime.now().toUtc().toIso8601String(), 'hotelName': hotelName, 'users': users.map((e) => e.toMap()).toList(), 'rooms': rooms.map((e) => e.toMap()).toList(), 'guests': guests.map((e) => e.toMap()).toList(), 'bookings': bookings.map((e) => e.toMap()).toList()};
  }

  Future<void> restoreBackup(Map<String, dynamic> payload) async {
    if (!isAdmin) throw StateError('Admin access required');
    if (payload['format'] != 'miftah-backup' || payload['version'] != 1) throw const FormatException('صيغة النسخة الاحتياطية غير مدعومة');
    final nextUsers = _backupList(payload['users'], UserRecord.fromMap);
    final nextRooms = _backupList(payload['rooms'], RoomRecord.fromMap);
    final nextGuests = _backupList(payload['guests'], GuestRecord.fromMap);
    final nextBookings = _backupList(payload['bookings'], BookingRecord.fromMap);
    if (nextUsers.isEmpty || nextRooms.isEmpty) throw const FormatException('النسخة لا تحتوي على مستخدمين وغرف صالحة');
    final guestIds = nextGuests.map((guest) => guest.id).toSet();
    final roomIds = nextRooms.map((room) => room.id).toSet();
    if (nextBookings.any((booking) => !guestIds.contains(booking.guestId) || !roomIds.contains(booking.roomId))) throw const FormatException('توجد حجوزات مرتبطة ببيانات مفقودة');
    users = nextUsers;
    rooms = nextRooms;
    guests = nextGuests;
    bookings = nextBookings;
    hotelName = (payload['hotelName'] as String?)?.trim().isNotEmpty == true ? (payload['hotelName'] as String).trim() : hotelName;
    currentUser = null;
    _rebuildIndexes();
    await _save();
    notifyListeners();
  }

  List<T> _backupList<T>(dynamic raw, T Function(Map) parser) {
    if (raw is! List) throw const FormatException('بيانات النسخة غير مكتملة');
    return raw.whereType<Map>().map((item) => parser(Map<String, dynamic>.from(item))).toList();
  }
}

class HotelApp extends ConsumerWidget {
  const HotelApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appControllerProvider);
    if (!controller.initialized) return const MaterialApp(home: Scaffold(body: Center(child: CircularProgressIndicator())));
    final router = GoRouter(initialLocation: controller.currentUser == null ? '/login' : '/home', routes: [GoRoute(path: '/login', builder: (_, __) => const LoginScreen()), GoRoute(path: '/home', builder: (_, __) => const MainShell())]);
    return MaterialApp.router(title: controller.hotelName, debugShowCheckedModeBanner: false, routerConfig: router, theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff0b7285), brightness: Brightness.light), scaffoldBackgroundColor: const Color(0xfff6f8fa), fontFamily: 'Arial'));
  }
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _user = TextEditingController(text: 'admin');
  final _pass = TextEditingController(text: 'admin123');
  String? error;
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appControllerProvider);
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandMark(size: 78, showLabel: true),
                    const SizedBox(height: 18),
                    Text('مرحباً بك في ${controller.hotelName}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text('نظام إدارة الفندق المحلي', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
                    const SizedBox(height: 28),
                    TextField(controller: _user, decoration: const InputDecoration(labelText: 'اسم المستخدم', prefixIcon: Icon(Icons.person_outline), border: OutlineInputBorder())),
                    const SizedBox(height: 14),
                    TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور', prefixIcon: Icon(Icons.lock_outline), border: OutlineInputBorder())),
                    if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.red))),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: busy ? null : () {
                          setState(() => busy = true);
                          final auth = ref.read(appControllerProvider);
                          final ok = auth.login(_user.text.trim(), _pass.text);
                          if (ok) {
                            context.go('/home');
                          } else {
                            setState(() {
                              error = auth.isLoginLocked ? 'تم إيقاف المحاولات مؤقتاً. حاول بعد 30 ثانية.' : 'بيانات الدخول غير صحيحة';
                              busy = false;
                            });
                          }
                        },
                        icon: const Icon(Icons.login),
                        label: Padding(padding: const EdgeInsets.all(12), child: Text(busy ? 'جارٍ الدخول...' : 'تسجيل الدخول')),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('الحساب الافتراضي: admin / admin123', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});
  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int index = 0;
  final query = TextEditingController();
  final titles = const ['لوحة التحكم', 'الغرف', 'الحجوزات', 'العملاء', 'التقارير', 'الإعدادات'];
  late final List<Widget> pages;

  @override
  void initState() {
    super.initState();
    final isAdmin = ref.read(appControllerProvider).currentUser?.role == 'admin';
    pages = [
      const DashboardPage(),
      const RoomsPage(),
      const BookingsPage(),
      const GuestsPage(),
      isAdmin ? const ReportsPage() : const RestrictedPage(message: 'التقارير متاحة لمدير النظام فقط'),
      SettingsPage(isAdmin: isAdmin),
    ];
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appControllerProvider);
    final isAdmin = controller.currentUser?.role == 'admin';
    final canEdit = isAdmin || controller.currentUser?.role == 'receptionist';
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final destinations = const [
            NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: Text('الرئيسية')),
            NavigationRailDestination(icon: Icon(Icons.meeting_room_outlined), selectedIcon: Icon(Icons.meeting_room), label: Text('الغرف')),
            NavigationRailDestination(icon: Icon(Icons.book_online_outlined), selectedIcon: Icon(Icons.book_online), label: Text('الحجوزات')),
            NavigationRailDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: Text('العملاء')),
            NavigationRailDestination(icon: Icon(Icons.analytics_outlined), selectedIcon: Icon(Icons.analytics), label: Text('التقارير')),
            NavigationRailDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: Text('الإعدادات')),
          ];
          final rail = NavigationRail(selectedIndex: index, onDestinationSelected: (value) => setState(() => index = value), labelType: NavigationRailLabelType.all, destinations: destinations);
          return Scaffold(
            appBar: AppBar(
              title: Row(children: [const BrandMark(size: 34, showLabel: true), const SizedBox(width: 16), Text(titles[index], style: const TextStyle(fontWeight: FontWeight.bold))]),
              actions: [
                if (wide) SizedBox(width: 250, child: TextField(controller: query, decoration: const InputDecoration(hintText: 'بحث سريع...', prefixIcon: Icon(Icons.search), border: InputBorder.none))),
                PopupMenuButton<String>(
                  tooltip: 'الحساب',
                  onSelected: (value) {
                    if (value == 'logout') {
                      controller.logout();
                      context.go('/login');
                    }
                  },
                  itemBuilder: (_) => [PopupMenuItem(value: 'profile', child: Text('${controller.currentUser?.name ?? ''} (${roleLabel(controller.currentUser?.role)})')), const PopupMenuDivider(), const PopupMenuItem(value: 'logout', child: Text('تسجيل الخروج'))],
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: CircleAvatar(child: Text((controller.currentUser?.name ?? 'م')[0]))),
                ),
              ],
            ),
            body: Row(children: [if (wide) rail, Expanded(child: IndexedStack(index: index, children: pages))]),
            bottomNavigationBar: wide ? null : NavigationBar(selectedIndex: index, onDestinationSelected: (value) => setState(() => index = value), destinations: const [
              NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'الرئيسية'),
              NavigationDestination(icon: Icon(Icons.meeting_room_outlined), selectedIcon: Icon(Icons.meeting_room), label: 'الغرف'),
              NavigationDestination(icon: Icon(Icons.book_online_outlined), selectedIcon: Icon(Icons.book_online), label: 'الحجوزات'),
              NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'العملاء'),
              NavigationDestination(icon: Icon(Icons.analytics_outlined), selectedIcon: Icon(Icons.analytics), label: 'التقارير'),
              NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'الإعدادات'),
            ]),
            floatingActionButton: canEdit && index == 1 ? FloatingActionButton.extended(onPressed: () => showAddRoomDialog(context), icon: const Icon(Icons.add), label: const Text('غرفة جديدة')) : canEdit && index == 3 ? FloatingActionButton.extended(onPressed: () => showAddGuestDialog(context), icon: const Icon(Icons.person_add), label: const Text('عميل جديد')) : null,
          );
        },
      ),
    );
  }
}

class RestrictedPage extends StatelessWidget {
  const RestrictedPage({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Center(child: Text(message));
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 42, this.showLabel = false});
  final double size;
  final bool showLabel;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [Image.asset('assets/brand/app_icon.png', width: size, height: size), if (showLabel) ...[const SizedBox(width: 10), const Text('مِفتاح', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .4))]]);
}

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(appControllerProvider);
    final arrivals = c.bookings.where((booking) => booking.status == 'pending' && dateLabel(booking.checkIn) == dateLabel(DateTime.now())).length;
    final departures = c.bookings.where((booking) => booking.status == 'checkedIn' && dateLabel(booking.checkOut) == dateLabel(DateTime.now())).length;
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text('نظرة عامة', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 18),
      Wrap(spacing: 16, runSpacing: 16, children: [
        StatCard(label: 'إجمالي الغرف', value: '${c.rooms.length}', icon: Icons.meeting_room, color: Colors.indigo),
        StatCard(label: 'الغرف المشغولة', value: '${c.occupiedRooms}', icon: Icons.hotel, color: Colors.orange),
        StatCard(label: 'نسبة الإشغال', value: '${(c.occupancy * 100).round()}%', icon: Icons.pie_chart, color: Colors.teal),
        StatCard(label: 'الإيرادات', value: '${_moneyFormat.format(c.revenue)} ر.س', icon: Icons.payments, color: Colors.green),
      ]),
      const SizedBox(height: 22),
      Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('عمليات اليوم', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 12), Wrap(spacing: 12, runSpacing: 12, children: [OperationalPill(label: 'الوصول اليوم', value: '$arrivals', icon: Icons.login, color: Colors.indigo), OperationalPill(label: 'المغادرة اليوم', value: '$departures', icon: Icons.logout, color: Colors.orange), OperationalPill(label: 'التنظيف', value: '${c.maintenanceRooms + c.roomCountByStatus('cleaning')}', icon: Icons.cleaning_services, color: Colors.teal), OperationalPill(label: 'إقامات نشطة', value: '${c.bookings.where((booking) => booking.status == 'checkedIn').length}', icon: Icons.nights_stay, color: Colors.green)])]))),
      const SizedBox(height: 22),
      Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('حالة الغرف', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 14), Wrap(spacing: 18, runSpacing: 8, children: [Legend(color: statusColor('available'), label: 'شاغرة ${c.roomCountByStatus('available')}'), Legend(color: statusColor('occupied'), label: 'مشغولة ${c.roomCountByStatus('occupied')}'), Legend(color: statusColor('cleaning'), label: 'تنظيف ${c.roomCountByStatus('cleaning')}'), Legend(color: statusColor('maintenance'), label: 'صيانة ${c.roomCountByStatus('maintenance')}')]), const SizedBox(height: 18), Wrap(spacing: 12, runSpacing: 12, children: c.rooms.take(12).map((room) => RoomMiniCard(room: room)).toList())]))),
    ]);
  }
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, required this.icon, required this.color});
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(width: 230, child: Card(child: Padding(padding: const EdgeInsets.all(20), child: Row(children: [CircleAvatar(backgroundColor: color.withOpacity(.12), child: Icon(icon, color: color)), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(color: Colors.grey[600])), const SizedBox(height: 6), Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))]))])));
}

class OperationalPill extends StatelessWidget {
  const OperationalPill({super.key, required this.label, required this.value, required this.icon, required this.color});
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(width: 170, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: color.withOpacity(.08), borderRadius: BorderRadius.circular(12)), child: Row(children: [Icon(icon, color: color), const SizedBox(width: 10), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(color: Colors.grey[700])), Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color))])]);
}

class Legend extends StatelessWidget {
  const Legend({super.key, required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 8), Text(label)]);
}

class RoomMiniCard extends StatelessWidget {
  const RoomMiniCard({super.key, required this.room});
  final RoomRecord room;
  @override
  Widget build(BuildContext context) => Container(width: 112, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: statusColor(room.status).withOpacity(.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: statusColor(room.status).withOpacity(.3))), child: Column(children: [Icon(Icons.bed, color: statusColor(room.status)), const SizedBox(height: 5), Text(room.number, style: const TextStyle(fontWeight: FontWeight.bold)), Text(statusLabel(room.status), style: TextStyle(fontSize: 12, color: statusColor(room.status)))]));
}

class RoomsPage extends ConsumerStatefulWidget {
  const RoomsPage({super.key});
  @override
  ConsumerState<RoomsPage> createState() => _RoomsPageState();
}

class _RoomsPageState extends ConsumerState<RoomsPage> {
  Timer? _searchDebounce;
  String search = '';
  String? status;
  String? type;
  int? floor;
  @override
  void dispose() { _searchDebounce?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final c = ref.watch(appControllerProvider);
    final rooms = c.queryRooms(query: search, status: status, type: type, floor: floor);
    final types = c.rooms.map((room) => room.type).toSet().toList()..sort();
    final floors = c.rooms.map((room) => room.floor).toSet().toList()..sort();
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text('الغرف', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      TextField(onChanged: (value) { _searchDebounce?.cancel(); _searchDebounce = Timer(const Duration(milliseconds: 180), () { if (mounted) setState(() => search = value); }); }, decoration: const InputDecoration(labelText: 'بحث برقم الغرفة أو النوع أو اسم الضيف', prefixIcon: Icon(Icons.search), border: OutlineInputBorder())),
      const SizedBox(height: 14),
      Wrap(spacing: 10, runSpacing: 10, children: [
        FilterDropdown(label: 'الحالة', value: status, items: const {'available': 'شاغرة', 'occupied': 'مشغولة', 'cleaning': 'تنظيف', 'maintenance': 'صيانة'}, onChanged: (value) => setState(() => status = value)),
        FilterDropdown(label: 'النوع', value: type, items: {for (final item in types) item: item}, onChanged: (value) => setState(() => type = value)),
        DropdownButton<int>(value: floor, hint: const Text('كل الطوابق'), items: floors.map((item) => DropdownMenuItem(value: item, child: Text('الطابق $item'))).toList(), onChanged: (value) => setState(() => floor = value)),
        OutlinedButton.icon(onPressed: () => setState(() { search = ''; status = null; type = null; floor = null; }), icon: const Icon(Icons.clear), label: const Text('مسح الفلاتر')),
      ]),
      const SizedBox(height: 16),
      Wrap(spacing: 10, runSpacing: 10, children: [StatCard(label: 'النتائج', value: '${rooms.length}', icon: Icons.filter_list, color: Colors.indigo), StatCard(label: 'الشاغرة', value: '${c.roomCountByStatus('available')}', icon: Icons.check_circle_outline, color: Colors.green), StatCard(label: 'المشغولة', value: '${c.roomCountByStatus('occupied')}', icon: Icons.hotel, color: Colors.orange)]),
      const SizedBox(height: 16),
      if (rooms.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(32), child: Center(child: Text('لا توجد غرف مطابقة للفلاتر الحالية')))) else GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 340, mainAxisExtent: 205, crossAxisSpacing: 14, mainAxisSpacing: 14), itemCount: rooms.length, itemBuilder: (_, index) => RoomCard(room: rooms[index])),
    ]);
  }
}

class FilterDropdown extends StatelessWidget {
  const FilterDropdown({super.key, required this.label, required this.value, required this.items, required this.onChanged});
  final String label;
  final String? value;
  final Map<String, String> items;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButton<String>(value: value, hint: Text(label), items: [DropdownMenuItem<String>(value: null, child: Text('كل $label')), ...items.entries.map((entry) => DropdownMenuItem<String>(value: entry.key, child: Text(entry.value)))], onChanged: onChanged);
}

class RoomCard extends ConsumerWidget {
  const RoomCard({super.key, required this.room});
  final RoomRecord room;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(appControllerProvider);
    final booking = c.activeBookingForRoom(room.id);
    final guest = booking == null ? null : c.guestById(booking.guestId);
    return Card(child: InkWell(borderRadius: BorderRadius.circular(12), onTap: () => showRoomDetails(context, room), child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [CircleAvatar(backgroundColor: statusColor(room.status).withOpacity(.12), child: Icon(Icons.bed, color: statusColor(room.status))), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('غرفة ${room.number}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text('${room.type} • طابق ${room.floor}', style: TextStyle(color: Colors.grey[600]))])), Icon(Icons.circle, size: 12, color: statusColor(room.status))]), const SizedBox(height: 14), if (guest != null) Row(children: [const Icon(Icons.person_outline, size: 18), const SizedBox(width: 8), Expanded(child: Text(guest.name, overflow: TextOverflow.ellipsis)), Text(dateLabel(booking!.checkOut), style: TextStyle(color: Colors.grey[600], fontSize: 12))]) else Row(children: [Icon(room.status == 'available' ? Icons.check_circle_outline : Icons.info_outline, size: 18, color: statusColor(room.status)), const SizedBox(width: 8), Text(room.status == 'available' ? 'جاهزة للحجز' : statusLabel(room.status))]), const Spacer(), Row(children: [Chip(label: Text(statusLabel(room.status)), side: BorderSide.none, backgroundColor: statusColor(room.status).withOpacity(.12)), const Spacer(), Text('${_moneyFormat.format(room.price)} ر.س', style: const TextStyle(fontWeight: FontWeight.bold)), PopupMenuButton<String>(onSelected: (value) => ref.read(appControllerProvider).updateRoomStatus(room, value), itemBuilder: (_) => ['available', 'occupied', 'maintenance', 'cleaning'].map((value) => PopupMenuItem<String>(value: value, child: Text(statusLabel(value)))).toList())])])));
  }
}

class BookingsPage extends ConsumerWidget {
  const BookingsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(appControllerProvider);
    return ListView(padding: const EdgeInsets.all(24), children: [Row(children: [Text('${c.bookings.length} حجز', style: Theme.of(context).textTheme.titleMedium), const Spacer(), FilledButton.icon(onPressed: () => showAddBookingDialog(context), icon: const Icon(Icons.add), label: const Text('حجز جديد'))]), const SizedBox(height: 16), if (c.bookings.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(32), child: Center(child: Text('لا توجد حجوزات بعد')))) else ...c.bookings.map((booking) { final guest = c.guestById(booking.guestId); final room = c.roomById(booking.roomId); return Card(child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), leading: CircleAvatar(child: Text(room?.number ?? '?')), title: Text('${booking.number} — ${guest?.name ?? 'ضيف غير معروف'}', style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text('الغرفة ${room?.number ?? '-'} • ${dateLabel(booking.checkIn)} → ${dateLabel(booking.checkOut)} • ${_moneyFormat.format(booking.total)} ر.س'), trailing: PopupMenuButton<String>(onSelected: (value) { if (value == 'invoice') { printInvoice(context, booking); } else { ref.read(appControllerProvider).changeBookingStatus(booking, value); } }, itemBuilder: (_) => const [PopupMenuItem(value: 'checkedIn', child: Text('تأكيد Check-in')), PopupMenuItem(value: 'checkedOut', child: Text('تأكيد Check-out')), PopupMenuItem(value: 'cancelled', child: Text('إلغاء الحجز')), PopupMenuItem(value: 'invoice', child: Text('طباعة الفاتورة'))]))); })]);
  }
}

class GuestsPage extends ConsumerStatefulWidget {
  const GuestsPage({super.key});
  @override
  ConsumerState<GuestsPage> createState() => _GuestsPageState();
}

class _GuestsPageState extends ConsumerState<GuestsPage> {
  Timer? _searchDebounce;
  String search = '';
  @override
  void dispose() { _searchDebounce?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final c = ref.watch(appControllerProvider);
    final guests = c.queryGuests(search);
    return ListView(padding: const EdgeInsets.all(24), children: [Text('العملاء', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 16), TextField(onChanged: (value) { _searchDebounce?.cancel(); _searchDebounce = Timer(const Duration(milliseconds: 180), () { if (mounted) setState(() => search = value); }); }, decoration: const InputDecoration(labelText: 'البحث بالاسم أو الهاتف أو رقم الهوية', prefixIcon: Icon(Icons.search), border: OutlineInputBorder())), const SizedBox(height: 16), Card(child: ListView.separated(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: guests.length, separatorBuilder: (_, __) => const Divider(height: 1), itemBuilder: (_, index) { final guest = guests[index]; return ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), leading: CircleAvatar(child: Text(guest.name.isEmpty ? '?' : guest.name[0])), title: Text(guest.name, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text('${guest.phone} • ${guest.nationality} • ${guest.nationalId}'), trailing: Text('${c.stayCountForGuest(guest.id)} إقامة'); })), if (guests.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لا يوجد عملاء مطابقون')))]);
  }
}

class ReportsPage extends ConsumerWidget {
  const ReportsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(appControllerProvider);
    final checkedIn = c.bookings.where((booking) => booking.status == 'checkedIn').length;
    final pending = c.bookings.where((booking) => booking.status == 'pending').length;
    return ListView(padding: const EdgeInsets.all(24), children: [Text('ملخص الأداء', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 18), Wrap(spacing: 16, runSpacing: 16, children: [StatCard(label: 'إيرادات الحجوزات', value: '${_moneyFormat.format(c.revenue)} ر.س', icon: Icons.payments, color: Colors.indigo), StatCard(label: 'إقامات نشطة', value: '$checkedIn', icon: Icons.nights_stay, color: Colors.teal), StatCard(label: 'حجوزات معلقة', value: '$pending', icon: Icons.pending_actions, color: Colors.orange)]), const SizedBox(height: 24), Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('تقرير الوردية', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 16), const ListTile(leading: Icon(Icons.nightlight_round), title: Text('الوردية الليلية'), subtitle: Text('تقرير الوصول والمغادرة والتسويات اليومية')), const Divider(), const ListTile(leading: Icon(Icons.wb_sunny_outlined), title: Text('الوردية النهارية'), subtitle: Text('حالة الغرف والحجوزات الجديدة'))])))]);
  }
}

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, required this.isAdmin});
  final bool isAdmin;
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final TextEditingController name;
  @override
  void initState() { super.initState(); name = TextEditingController(); }
  @override
  void dispose() { name.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final c = ref.watch(appControllerProvider);
    if (name.text.isEmpty) name.text = c.hotelName;
    if (!widget.isAdmin) return const Center(child: Text('هذه الصفحة متاحة لمدير النظام فقط'));
    return ListView(padding: const EdgeInsets.all(24), children: [
      Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('إعدادات الفندق', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 18), TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الفندق', prefixIcon: Icon(Icons.hotel), border: OutlineInputBorder())), const SizedBox(height: 14), FilledButton(onPressed: () async { await c.updateHotelName(name.text); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الإعدادات'))); }, child: const Text('حفظ'))]))),
      const SizedBox(height: 18),
      Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('المستخدمون والصلاحيات', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 12), ...c.users.map((user) => ListTile(leading: const Icon(Icons.account_circle_outlined), title: Text(user.name), subtitle: Text('${user.username} • ${roleLabel(user.role)}'), trailing: Switch(value: user.isActive, onChanged: null))), const SizedBox(height: 8), OutlinedButton.icon(onPressed: () => showAddUserDialog(context), icon: const Icon(Icons.person_add), label: const Text('إضافة مستخدم'))]))),
      const SizedBox(height: 18),
      Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('حماية البيانات', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 8), const Text('صدّر نسخة مشفرة دورياً واحفظها خارج الجهاز.'), const SizedBox(height: 14), Wrap(spacing: 10, runSpacing: 10, children: [FilledButton.icon(onPressed: () => exportBackupToFile(context), icon: const Icon(Icons.download), label: const Text('تصدير نسخة')), OutlinedButton.icon(onPressed: () => restoreBackupFromFile(context), icon: const Icon(Icons.restore), label: const Text('استعادة نسخة'))])]))),
      const SizedBox(height: 18),
      const Card(child: ListTile(leading: Icon(Icons.cloud_outlined), title: Text('Firebase'), subtitle: Text('جاهز للتفعيل مستقبلاً — التخزين المحلي يعمل حالياً'), trailing: Chip(label: Text('معطل')))),
    ]);
  }
}

Future<void> showRoomDetails(BuildContext context, RoomRecord room) async {
  final c = ProviderScope.containerOf(context).read(appControllerProvider);
  final booking = c.activeBookingForRoom(room.id);
  final guest = booking == null ? null : c.guestById(booking.guestId);
  await showDialog<void>(context: context, builder: (_) => AlertDialog(title: Row(children: [CircleAvatar(backgroundColor: statusColor(room.status).withOpacity(.12), child: Icon(Icons.meeting_room, color: statusColor(room.status))), const SizedBox(width: 12), Text('غرفة ${room.number}')]), content: SizedBox(width: 430, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${room.type} • الطابق ${room.floor}', style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 16), DetailLine(icon: Icons.circle, label: 'الحالة', value: statusLabel(room.status), color: statusColor(room.status)), DetailLine(icon: Icons.payments_outlined, label: 'السعر', value: '${_moneyFormat.format(room.price)} ر.س / ليلة'), if (guest != null) ...[const Divider(height: 24), Text('الإقامة الحالية', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)), DetailLine(icon: Icons.person_outline, label: 'الضيف', value: guest.name), DetailLine(icon: Icons.calendar_today_outlined, label: 'الفترة', value: '${dateLabel(booking!.checkIn)} — ${dateLabel(booking!.checkOut)}'), DetailLine(icon: Icons.receipt_long_outlined, label: 'رقم الحجز', value: booking!.number)] else ...[const Divider(height: 24), Row(children: [Icon(room.status == 'available' ? Icons.check_circle : Icons.info_outline, color: statusColor(room.status)), const SizedBox(width: 8), Text(room.status == 'available' ? 'الغرفة جاهزة لاستقبال حجز جديد' : 'لا توجد إقامة نشطة حالياً')])]])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')), PopupMenuButton<String>(onSelected: (value) { c.updateRoomStatus(room, value); Navigator.pop(context); }, itemBuilder: (_) => ['available', 'occupied', 'maintenance', 'cleaning'].map((value) => PopupMenuItem<String>(value: value, child: Text(statusLabel(value)))).toList(), child: const FilledButton(onPressed: null, child: Text('تغيير الحالة')))]));
}

class DetailLine extends StatelessWidget {
  const DetailLine({super.key, required this.icon, required this.label, required this.value, this.color});
  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [Icon(icon, size: 18, color: color ?? Colors.grey[700]), const SizedBox(width: 10), Text('$label: ', style: TextStyle(color: Colors.grey[700])), Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)))]));
}

Future<void> printInvoice(BuildContext context, BookingRecord booking) async {
  final c = ProviderScope.containerOf(context).read(appControllerProvider);
  final guest = c.guestById(booking.guestId);
  final room = c.roomById(booking.roomId);
  try {
    final fontData = await rootBundle.load('assets/fonts/DejaVuSans.ttf');
    final font = pw.Font.ttf(fontData);
    final boldFont = pw.Font.ttf(fontData);
    final document = pw.Document();
    document.addPage(pw.Page(pageFormat: pp.PdfPageFormat.a4, margin: const pw.EdgeInsets.all(32), theme: pw.ThemeData.withFont(base: font, bold: boldFont), build: (_) => pw.Directionality(textDirection: pw.TextDirection.rtl, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [pw.Text('مفتاح لإدارة الفندق', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)), pw.SizedBox(height: 6), pw.Text('فاتورة حجز رقم ${booking.number}'), pw.Divider(), pw.SizedBox(height: 12), pw.Text('الضيف: ${guest?.name ?? '-'}'), pw.Text('الهاتف: ${guest?.phone ?? '-'}'), pw.Text('الغرفة: ${room?.number ?? '-'} — ${room?.type ?? '-'}'), pw.Text('الوصول: ${dateLabel(booking.checkIn)}'), pw.Text('المغادرة: ${dateLabel(booking.checkOut)}'), pw.SizedBox(height: 18), pw.Table(border: pw.TableBorder.all(color: pp.PdfColors.grey400), children: [pw.TableRow(children: [pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('الوصف')), pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('الإجمالي'))]), pw.TableRow(children: [pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('إقامة فندقية')), pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('${_moneyFormat.format(booking.total)} ر.س'))])]), pw.Spacer(), pw.Align(alignment: pw.Alignment.center, child: pw.Text('شكراً لاختياركم مفتاح لإدارة الفندق'))])));
    await Printing.layoutPdf(onLayout: (_) async => document.save());
  } catch (error) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تجهيز الفاتورة: $error')));
  }
}

Future<String?> requestBackupPassword(BuildContext context, {required bool confirm}) async {
  final password = TextEditingController();
  final confirmation = TextEditingController();
  final result = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: Text(confirm ? 'حماية النسخة الاحتياطية' : 'كلمة مرور النسخة'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور', helperText: '8 أحرف على الأقل')), if (confirm) ...[const SizedBox(height: 12), TextField(controller: confirmation, obscureText: true, decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور'))]]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')), FilledButton(onPressed: () { if (password.text.length < 8 || (confirm && password.text != confirmation.text)) return; Navigator.pop(context, password.text); }, child: const Text('متابعة'))]));
  password.dispose();
  confirmation.dispose();
  return result;
}

Future<void> exportBackupToFile(BuildContext context) async {
  final c = ProviderScope.containerOf(context).read(appControllerProvider);
  final password = await requestBackupPassword(context, confirm: true);
  if (password == null) return;
  try {
    final bytes = await BackupCodec.encrypt(c.exportBackup(), password);
    await FileSaver.instance.saveFile(name: 'miftah-backup-${DateTime.now().toIso8601String().replaceAll(':', '-')}', bytes: bytes, fileExtension: 'miftah', mimeType: MimeType.other);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تصدير نسخة مشفرة. احفظها في مكان آمن.')));
  } catch (error) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تصدير النسخة: $error')));
  }
}

Future<void> restoreBackupFromFile(BuildContext context) async {
  final c = ProviderScope.containerOf(context).read(appControllerProvider);
  try {
    final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['miftah'], withData: true);
    if (result == null || result.files.single.bytes == null) return;
    final password = await requestBackupPassword(context, confirm: false);
    if (password == null) return;
    final decoded = await BackupCodec.decrypt(result.files.single.bytes!, password);
    await c.restoreBackup(decoded);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت استعادة البيانات بنجاح. سيتم تسجيل الدخول من جديد.')));
  } catch (error) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر استعادة النسخة: $error')));
  }
}

Future<void> showAddRoomDialog(BuildContext context) async {
  final number = TextEditingController();
  final floor = TextEditingController(text: '1');
  final price = TextEditingController(text: '200');
  String type = 'مفردة';
  await showDialog<void>(context: context, builder: (_) => StatefulBuilder(builder: (dialogContext, setState) => AlertDialog(title: const Text('إضافة غرفة'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: number, decoration: const InputDecoration(labelText: 'رقم الغرفة')), TextField(controller: floor, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الطابق')), TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر لليلة')), DropdownButtonFormField<String>(initialValue: type, decoration: const InputDecoration(labelText: 'النوع'), items: const ['مفردة', 'مزدوجة', 'جناح', 'VIP'].map((value) => DropdownMenuItem<String>(value: value, child: Text(value))).toList(), onChanged: (value) { if (value != null) setState(() => type = value); })])), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')), FilledButton(onPressed: () { final floorValue = int.tryParse(floor.text); final priceValue = double.tryParse(price.text); if (number.text.trim().isEmpty || floorValue == null || floorValue < 1 || priceValue == null || priceValue <= 0) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل رقم الغرفة والطابق والسعر بشكل صحيح'))); return; } ProviderScope.containerOf(context).read(appControllerProvider).addRoom(number.text, type, floorValue, priceValue); Navigator.pop(dialogContext); }, child: const Text('إضافة'))]));
  number.dispose();
  floor.dispose();
  price.dispose();
}

Future<void> showAddGuestDialog(BuildContext context) async {
  final name = TextEditingController();
  final phone = TextEditingController();
  final id = TextEditingController();
  final nationality = TextEditingController(text: 'سعودي');
  final email = TextEditingController();
  await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(title: const Text('إضافة عميل'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم الكامل')), TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'الهاتف')), TextField(controller: id, decoration: const InputDecoration(labelText: 'رقم الهوية')), TextField(controller: nationality, decoration: const InputDecoration(labelText: 'الجنسية')), TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'البريد الإلكتروني'))])), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')), FilledButton(onPressed: () { if (name.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل اسم العميل'))); return; } ProviderScope.containerOf(context).read(appControllerProvider).addGuest(name.text.trim(), phone.text.trim(), id.text.trim(), nationality.text.trim(), email.text.trim()); Navigator.pop(dialogContext); }, child: const Text('حفظ'))]));
  name.dispose();
  phone.dispose();
  id.dispose();
  nationality.dispose();
  email.dispose();
}

Future<void> showAddBookingDialog(BuildContext context) async {
  final c = ProviderScope.containerOf(context).read(appControllerProvider);
  final availableRooms = c.rooms.where((room) => room.status == 'available').toList();
  if (c.guests.isEmpty || availableRooms.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف عميلاً وغرفة شاغرة أولاً'))); return; }
  String guest = c.guests.first.id;
  String room = availableRooms.first.id;
  DateTime start = DateTime.now();
  DateTime end = DateTime.now().add(const Duration(days: 1));
  final notes = TextEditingController();
  await showDialog<void>(context: context, builder: (_) => StatefulBuilder(builder: (dialogContext, setState) => AlertDialog(title: const Text('إنشاء حجز جديد'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [DropdownButtonFormField<String>(initialValue: guest, decoration: const InputDecoration(labelText: 'العميل'), items: c.guests.map((item) => DropdownMenuItem<String>(value: item.id, child: Text(item.name))).toList(), onChanged: (value) { if (value != null) setState(() => guest = value); }), DropdownButtonFormField<String>(initialValue: room, decoration: const InputDecoration(labelText: 'الغرفة'), items: availableRooms.map((item) => DropdownMenuItem<String>(value: item.id, child: Text('${item.number} — ${item.type}'))).toList(), onChanged: (value) { if (value != null) setState(() => room = value); }), ListTile(title: Text('الوصول: ${dateLabel(start)}'), trailing: const Icon(Icons.calendar_today), onTap: () async { final date = await showDatePicker(context: dialogContext, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 365)), initialDate: start); if (date != null) setState(() => start = date); }), ListTile(title: Text('المغادرة: ${dateLabel(end)}'), trailing: const Icon(Icons.calendar_today), onTap: () async { final date = await showDatePicker(context: dialogContext, firstDate: start.add(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 365)), initialDate: end); if (date != null) setState(() => end = date); }), TextField(controller: notes, decoration: const InputDecoration(labelText: 'ملاحظات'))])), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')), FilledButton(onPressed: () { c.addBooking(guest, room, start, end, notes.text.trim()); Navigator.pop(dialogContext); }, child: const Text('إنشاء الحجز'))]));
  notes.dispose();
}

Future<void> showAddUserDialog(BuildContext context) async {
  final name = TextEditingController();
  final username = TextEditingController();
  final password = TextEditingController();
  String role = 'receptionist';
  await showDialog<void>(context: context, builder: (_) => StatefulBuilder(builder: (dialogContext, setState) => AlertDialog(title: const Text('إضافة مستخدم'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')), TextField(controller: username, decoration: const InputDecoration(labelText: 'اسم المستخدم')), TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور', helperText: '8 أحرف على الأقل')), DropdownButtonFormField<String>(initialValue: role, decoration: const InputDecoration(labelText: 'الدور'), items: const [DropdownMenuItem<String>(value: 'receptionist', child: Text('موظف استقبال')), DropdownMenuItem<String>(value: 'nightShift', child: Text('وردية ليلية')), DropdownMenuItem<String>(value: 'dayShift', child: Text('وردية نهارية'))], onChanged: (value) { if (value != null) setState(() => role = value); })])), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')), FilledButton(onPressed: () { if (name.text.trim().isEmpty || username.text.trim().length < 3 || password.text.length < 8) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تحقق من الاسم واسم المستخدم وكلمة المرور'))); return; } ProviderScope.containerOf(context).read(appControllerProvider).addUser(name.text.trim(), username.text.trim(), password.text, role); Navigator.pop(dialogContext); }, child: const Text('إضافة'))]));
  name.dispose();
  username.dispose();
  password.dispose();
}
