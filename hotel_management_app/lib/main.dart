import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'data/local/hotel_local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

class LoginScreen extends ConsumerStatefulWidget { const LoginScreen({super.key}); @override ConsumerState<LoginScreen> createState() => _LoginScreenState(); }
class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _user = TextEditingController(text: 'admin');
  final _pass = TextEditingController(text: 'admin123');
  String? error;
  bool busy = false;
  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 430), child: Card(margin: const EdgeInsets.all(24), elevation: 2, child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [const BrandMark(size: 78, showLabel: true), const SizedBox(height: 18), Text('مرحباً بك في ${ref.watch(appControllerProvider).hotelName}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center), const SizedBox(height: 8), Text('نظام إدارة الفندق المحلي', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600])), const SizedBox(height: 28), TextField(controller: _user, decoration: const InputDecoration(labelText: 'اسم المستخدم', prefixIcon: Icon(Icons.person_outline), border: OutlineInputBorder())), const SizedBox(height: 14), TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور', prefixIcon: Icon(Icons.lock_outline), border: OutlineInputBorder())), if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.red))), const SizedBox(height: 22), SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: busy ? null : () { setState(() => busy = true); final auth = ref.read(appControllerProvider); final ok = auth.login(_user.text.trim(), _pass.text); if (ok) { context.go('/home'); } else { setState(() { error = auth.isLoginLocked ? 'تم إيقاف المحاولات مؤقتاً. حاول بعد 30 ثانية.' : 'بيانات الدخول غير صحيحة'; busy = false; }); } }, icon: const Icon(Icons.login), label: Padding(padding: const EdgeInsets.all(12), child: Text(busy ? 'جارٍ الدخول...' : 'تسجيل الدخول')))), const SizedBox(height: 16), Text('الحساب الافتراضي: admin / admin123', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]))]))))));
}

class MainShell extends ConsumerStatefulWidget { const MainShell({super.key}); @override ConsumerState<MainShell> createState() => _MainShellState(); }
class _MainShellState extends ConsumerState<MainShell> {
  int index = 0;
  final query = TextEditingController();
  final titles = ['لوحة التحكم', 'الغرف', 'الحجوزات', 'العملاء', 'التقارير', 'الإعدادات'];
  late final List<Widget> pages;
  @override
  void initState() {
    super.initState();
    final isAdmin = ref.read(appControllerProvider).currentUser?.role == 'admin';
    pages = [const DashboardPage(), const RoomsPage(), const BookingsPage(), const GuestsPage(), isAdmin ? const ReportsPage() : const RestrictedPage(message: 'التقارير متاحة لمدير النظام فقط'), SettingsPage(isAdmin: isAdmin)];
  }
  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appControllerProvider);
    final isAdmin = controller.currentUser?.role == 'admin';
    final canEdit = isAdmin || controller.currentUser?.role == 'receptionist';
    return Directionality(textDirection: TextDirection.rtl, child: LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 900;
      final nav = NavigationRail(selectedIndex: index, onDestinationSelected: (i) => setState(() => index = i), labelType: NavigationRailLabelType.all, backgroundColor: Colors.white, destinations: const [NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: Text('الرئيسية')), NavigationRailDestination(icon: Icon(Icons.meeting_room_outlined), selectedIcon: Icon(Icons.meeting_room), label: Text('الغرف')), NavigationRailDestination(icon: Icon(Icons.book_online_outlined), selectedIcon: Icon(Icons.book_online), label: Text('الحجوزات')), NavigationRailDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: Text('العملاء')), NavigationRailDestination(icon: Icon(Icons.analytics_outlined), selectedIcon: Icon(Icons.analytics), label: Text('التقارير')), NavigationRailDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: Text('الإعدادات'))]);
      return Scaffold(appBar: AppBar(title: Row(children: [const BrandMark(size: 34, showLabel: true), const SizedBox(width: 22), Text(titles[index], style: const TextStyle(fontWeight: FontWeight.bold))]), backgroundColor: Colors.white, actions: [if (wide) SizedBox(width: 260, child: TextField(controller: query, onChanged: (v) => setState(() {}), decoration: const InputDecoration(hintText: 'بحث سريع...', prefixIcon: Icon(Icons.search), border: InputBorder.none))), const SizedBox(width: 12), PopupMenuButton<String>(tooltip: 'الحساب', onSelected: (value) { if (value == 'logout') { controller.logout(); context.go('/login'); } }, itemBuilder: (_) => [PopupMenuItem(value: 'profile', child: Text('${controller.currentUser?.name ?? ''} (${roleLabel(controller.currentUser?.role)})')), const PopupMenuDivider(), const PopupMenuItem(value: 'logout', child: Text('تسجيل الخروج'))], child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: CircleAvatar(child: Text((controller.currentUser?.name ?? 'م')[0]))))]), body: Row(children: [if (wide) nav, Expanded(child: IndexedStack(index: index, children: pages))]), bottomNavigationBar: wide ? null : NavigationBar(selectedIndex: index, onDestinationSelected: (i) => setState(() => index = i), destinations: const [NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'الرئيسية'), NavigationDestination(icon: Icon(Icons.meeting_room_outlined), selectedIcon: Icon(Icons.meeting_room), label: 'الغرف'), NavigationDestination(icon: Icon(Icons.book_online_outlined), selectedIcon: Icon(Icons.book_online), label: 'الحجوزات'), NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'العملاء'), NavigationDestination(icon: Icon(Icons.more_horiz), label: 'المزيد')]), floatingActionButton: canEdit && index == 1 ? FloatingActionButton.extended(onPressed: () => showAddRoomDialog(context), icon: const Icon(Icons.add), label: const Text('غرفة جديدة')) : canEdit && index == 3 ? FloatingActionButton.extended(onPressed: () => showAddGuestDialog(context), icon: const Icon(Icons.person_add), label: const Text('عميل جديد')) : null);
    });
  }
}

class RestrictedPage extends StatelessWidget {
  const RestrictedPage({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Center(child: Card(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.lock_outline, size: 42, color: Colors.grey[600]), const SizedBox(height: 12), Text(message)]))));
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 64, this.showLabel = false});
  final double size;
  final bool showLabel;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [ClipRRect(borderRadius: BorderRadius.circular(size * .24), child: Image.asset('assets/brand/app_icon.png', width: size, height: size, fit: BoxFit.cover)), if (showLabel) ...[const SizedBox(width: 12), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('مفتاح', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: const Color(0xff0b2545))), Text('تشغيل الفندق', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xff168b8f)))])]]);
}

String roleLabel(String? role) => {'admin': 'مدير النظام', 'receptionist': 'موظف استقبال', 'nightShift': 'وردية ليلية', 'dayShift': 'وردية نهارية'}[role] ?? 'مستخدم';
String statusLabel(String status) => {'available': 'شاغرة', 'occupied': 'مشغولة', 'maintenance': 'صيانة', 'cleaning': 'تنظيف', 'pending': 'قيد الانتظار', 'checkedIn': 'تم الدخول', 'checkedOut': 'تم الخروج', 'cancelled': 'ملغى'}[status] ?? status;
Color statusColor(String status) => {'available': Colors.green, 'occupied': Colors.red, 'maintenance': Colors.amber.shade800, 'cleaning': Colors.blue, 'pending': Colors.orange, 'checkedIn': Colors.green, 'checkedOut': Colors.blueGrey, 'cancelled': Colors.red}[status] ?? Colors.grey;

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(appControllerProvider);
    final today = DateTime.now();
    final arrivalsToday = c.bookings.where((b) => b.checkIn.year == today.year && b.checkIn.month == today.month && b.checkIn.day == today.day).length;
    final departuresToday = c.bookings.where((b) => b.checkOut.year == today.year && b.checkOut.month == today.month && b.checkOut.day == today.day).length;
    return ListView(padding: const EdgeInsets.all(24), children: [Wrap(spacing: 16, runSpacing: 16, children: [StatCard(label: 'إجمالي الغرف', value: '${c.rooms.length}', icon: Icons.meeting_room, color: Colors.teal), StatCard(label: 'الغرف المشغولة', value: '${c.occupiedRooms}', icon: Icons.hotel, color: Colors.red), StatCard(label: 'الغرف الشاغرة', value: '${c.availableRooms}', icon: Icons.check_circle, color: Colors.green), StatCard(label: 'الإيرادات', value: '${_moneyFormat.format(c.revenue)} ر.س', icon: Icons.payments, color: Colors.indigo)]), const SizedBox(height: 16), Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), child: Wrap(spacing: 24, runSpacing: 12, children: [OperationalPill(icon: Icons.login, label: 'وصول اليوم', value: '$arrivalsToday', color: Colors.teal), OperationalPill(icon: Icons.logout, label: 'مغادرة اليوم', value: '$departuresToday', color: Colors.indigo), OperationalPill(icon: Icons.cleaning_services, label: 'بانتظار التنظيف', value: '${c.rooms.where((r) => r.status == 'cleaning').length}', color: Colors.blue), OperationalPill(icon: Icons.night_shelter, label: 'إقامات نشطة', value: '${c.bookings.where((b) => b.status == 'checkedIn').length}', color: Colors.deepOrange)]))), const SizedBox(height: 24), Wrap(spacing: 20, runSpacing: 20, children: [SizedBox(width: 360, child: Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('مؤشر الإشغال', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 18), Row(children: [SizedBox(width: 120, height: 120, child: Stack(alignment: Alignment.center, children: [CircularProgressIndicator(value: c.occupancy, strokeWidth: 12, backgroundColor: Colors.grey.shade200, color: Colors.teal), Text('${(c.occupancy * 100).round()}%', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))])), const SizedBox(width: 20), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Legend(color: Colors.red, label: 'مشغولة: ${c.occupiedRooms}'), Legend(color: Colors.green, label: 'شاغرة: ${c.availableRooms}'), Legend(color: Colors.amber, label: 'صيانة: ${c.maintenanceRooms}')])])]))), SizedBox(width: 500, child: Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('الحجوزات الأخيرة', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 10), ...c.bookings.take(4).map((b) => ListTile(contentPadding: EdgeInsets.zero, leading: CircleAvatar(backgroundColor: statusColor(b.status).withOpacity(.12), child: Icon(Icons.receipt_long, color: statusColor(b.status))), title: Text(b.number), subtitle: Text('${c.guestById(b.guestId)?.name ?? 'عميل'} • غرفة ${c.roomById(b.roomId)?.number ?? '-'}'), trailing: Chip(label: Text(statusLabel(b.status)), side: BorderSide.none, backgroundColor: statusColor(b.status).withOpacity(.12)))])]))))]), const SizedBox(height: 24), Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('حالة الغرف', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 16), Wrap(spacing: 12, runSpacing: 12, children: c.rooms.map((room) => RoomMiniCard(room: room)).toList())])))]);
  }
}

class StatCard extends StatelessWidget { const StatCard({super.key, required this.label, required this.value, required this.icon, required this.color}); final String label, value; final IconData icon; final Color color; @override Widget build(BuildContext context) => SizedBox(width: 230, child: Card(child: Padding(padding: const EdgeInsets.all(20), child: Row(children: [CircleAvatar(backgroundColor: color.withOpacity(.12), child: Icon(icon, color: color)), const SizedBox(width: 14), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(color: Colors.grey[600])), const SizedBox(height: 6), Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))])]))); }
class OperationalPill extends StatelessWidget {
  const OperationalPill({super.key, required this.icon, required this.label, required this.value, required this.color});
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(width: 190, child: Row(children: [CircleAvatar(radius: 19, backgroundColor: color.withOpacity(.12), child: Icon(icon, size: 19, color: color)), const SizedBox(width: 10), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)), Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))])]);
}

class Legend extends StatelessWidget { const Legend({super.key, required this.color, required this.label}); final Color color; final String label; @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 8), Text(label)])); }
class RoomMiniCard extends StatelessWidget { const RoomMiniCard({super.key, required this.room}); final RoomRecord room; @override Widget build(BuildContext context) => Container(width: 112, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: statusColor(room.status).withOpacity(.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: statusColor(room.status).withOpacity(.3))), child: Column(children: [Icon(Icons.bed, color: statusColor(room.status)), const SizedBox(height: 5), Text(room.number, style: const TextStyle(fontWeight: FontWeight.bold)), Text(statusLabel(room.status), style: TextStyle(fontSize: 12, color: statusColor(room.status)))])); }

class RoomsPage extends ConsumerStatefulWidget { const RoomsPage({super.key}); @override ConsumerState<RoomsPage> createState() => _RoomsPageState(); }
class _RoomsPageState extends ConsumerState<RoomsPage> {
  Timer? _searchDebounce;
  String search = '';
  String statusFilter = 'الكل';
  String typeFilter = 'الكل';
  String floorFilter = 'الكل';
  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final c = ref.watch(appControllerProvider);
    final floors = c.rooms.map((r) => r.floor).toSet().toList()..sort();
    final types = c.rooms.map((r) => r.type).toSet().toList()..sort();
    final list = c.queryRooms(query: search, status: statusFilter == 'الكل' ? null : statusFilter, type: typeFilter == 'الكل' ? null : typeFilter, floor: floorFilter == 'الكل' ? null : int.tryParse(floorFilter));
    return ListView(padding: const EdgeInsets.all(24), children: [
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [
        TextField(onChanged: (v) { _searchDebounce?.cancel(); _searchDebounce = Timer(const Duration(milliseconds: 150), () { if (mounted) setState(() => search = v); }); }, decoration: const InputDecoration(labelText: 'ابحث برقم الغرفة أو النوع أو اسم الضيف', prefixIcon: Icon(Icons.search), suffixIcon: Icon(Icons.tune), border: OutlineInputBorder())),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          FilterDropdown(label: 'الحالة', value: statusFilter, values: const ['الكل', 'available', 'occupied', 'maintenance', 'cleaning'], display: statusLabel, onChanged: (v) => setState(() => statusFilter = v)),
          FilterDropdown(label: 'النوع', value: typeFilter, values: ['الكل', ...types], onChanged: (v) => setState(() => typeFilter = v)),
          FilterDropdown(label: 'الطابق', value: floorFilter, values: ['الكل', ...floors.map((e) => e.toString())], onChanged: (v) => setState(() => floorFilter = v)),
          TextButton.icon(onPressed: () => setState(() { search = ''; statusFilter = 'الكل'; typeFilter = 'الكل'; floorFilter = 'الكل'; }), icon: const Icon(Icons.clear_all), label: const Text('مسح الفلاتر'))
        ])
      ]))),
      const SizedBox(height: 18),
      Row(children: [Text('${list.length} غرفة مطابقة', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)), const Spacer(), Wrap(spacing: 8, children: ['available', 'occupied', 'cleaning', 'maintenance'].map((s) => Chip(avatar: Icon(Icons.circle, size: 11, color: statusColor(s)), label: Text('${statusLabel(s)} ${c.roomCountByStatus(s)}'), side: BorderSide.none, backgroundColor: statusColor(s).withOpacity(.08))).toList())]),
      const SizedBox(height: 14),
      if (list.isEmpty) Card(child: Padding(padding: const EdgeInsets.all(44), child: Column(children: [Icon(Icons.search_off, size: 54, color: Colors.grey[400]), const SizedBox(height: 12), const Text('لا توجد غرف تطابق الفلاتر الحالية'), const SizedBox(height: 10), OutlinedButton(onPressed: () => setState(() { search = ''; statusFilter = 'الكل'; typeFilter = 'الكل'; floorFilter = 'الكل'; }), child: const Text('عرض كل الغرف'))]))) else GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 310, mainAxisExtent: 238, crossAxisSpacing: 16, mainAxisSpacing: 16), itemCount: list.length, itemBuilder: (_, i) => RoomCard(room: list[i]))
    ]);
  }
}

class FilterDropdown extends StatelessWidget {
  const FilterDropdown({super.key, required this.label, required this.value, required this.values, required this.onChanged, this.display});
  final String label;
  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;
  final String Function(String)? display;
  @override
  Widget build(BuildContext context) => SizedBox(width: 180, child: DropdownButtonFormField<String>(value: value, isExpanded: true, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()), items: values.map((v) => DropdownMenuItem(value: v, child: Text(display?.call(v) ?? v))).toList(), onChanged: (v) { if (v != null) onChanged(v); }));
}

class RoomCard extends ConsumerWidget {
  const RoomCard({super.key, required this.room});
  final RoomRecord room;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(appControllerProvider);
    final booking = c.activeBookingForRoom(room.id);
    final guest = booking == null ? null : c.guestById(booking.guestId);
    return Card(child: InkWell(borderRadius: BorderRadius.circular(12), onTap: () => showRoomDetails(context, room), child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [CircleAvatar(radius: 22, backgroundColor: statusColor(room.status).withOpacity(.12), child: Icon(Icons.bed, color: statusColor(room.status))), const SizedBox(width: 12), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('غرفة ${room.number}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text('${room.type} • طابق ${room.floor}', style: TextStyle(color: Colors.grey[600]))]), const Spacer(), Icon(Icons.circle, size: 12, color: statusColor(room.status))]),
      const SizedBox(height: 14),
      if (guest != null) Row(children: [const Icon(Icons.person_outline, size: 18), const SizedBox(width: 8), Expanded(child: Text(guest.name, overflow: TextOverflow.ellipsis)), Text(dateLabel(booking!.checkOut), style: TextStyle(color: Colors.grey[600], fontSize: 12))]) else Row(children: [Icon(room.status == 'available' ? Icons.check_circle_outline : Icons.info_outline, size: 18, color: statusColor(room.status)), const SizedBox(width: 8), Text(room.status == 'available' ? 'جاهزة للحجز' : statusLabel(room.status))]),
      const Spacer(),
      Row(children: [Chip(label: Text(statusLabel(room.status)), side: BorderSide.none, backgroundColor: statusColor(room.status).withOpacity(.12)), const Spacer(), Text('${_moneyFormat.format(room.price)} ر.س', style: const TextStyle(fontWeight: FontWeight.bold)), PopupMenuButton<String>(onSelected: (v) => ref.read(appControllerProvider).updateRoomStatus(room, v), itemBuilder: (_) => ['available', 'occupied', 'maintenance', 'cleaning'].map((v) => PopupMenuItem(value: v, child: Text(statusLabel(v)))).toList())])
    ]))));
  }
}

class BookingsPage extends ConsumerWidget { const BookingsPage({super.key}); @override Widget build(BuildContext context, WidgetRef ref) { final c = ref.watch(appControllerProvider); return ListView(padding: const EdgeInsets.all(24), children: [Row(children: [Text('${c.bookings.length} حجز', style: Theme.of(context).textTheme.titleMedium), const Spacer(), FilledButton.icon(onPressed: () => showAddBookingDialog(context), icon: const Icon(Icons.add), label: const Text('حجز جديد'))]), const SizedBox(height: 16), Card(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: const [DataColumn(label: Text('رقم الحجز')), DataColumn(label: Text('العميل')), DataColumn(label: Text('الغرفة')), DataColumn(label: Text('الوصول')), DataColumn(label: Text('المغادرة')), DataColumn(label: Text('الإجمالي')), DataColumn(label: Text('الحالة')), DataColumn(label: Text('إجراء'))], rows: c.bookings.map((b) => DataRow(cells: [DataCell(Text(b.number)), DataCell(Text(c.guestById(b.guestId)?.name ?? '-')), DataCell(Text(c.roomById(b.roomId)?.number ?? '-')), DataCell(Text(dateLabel(b.checkIn))), DataCell(Text(dateLabel(b.checkOut))), DataCell(Text('${_moneyFormat.format(b.total)} ر.س')), DataCell(Chip(label: Text(statusLabel(b.status)), side: BorderSide.none, backgroundColor: statusColor(b.status).withOpacity(.12))), DataCell(PopupMenuButton<String>(onSelected: (v) { if (v == 'invoice') ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تجهيز الفاتورة للطباعة'))); else ref.read(appControllerProvider).changeBookingStatus(b, v); }, itemBuilder: (_) => [const PopupMenuItem(value: 'checkedIn', child: Text('تأكيد Check-in')), const PopupMenuItem(value: 'checkedOut', child: Text('تأكيد Check-out')), const PopupMenuItem(value: 'cancelled', child: Text('إلغاء الحجز')), const PopupMenuItem(value: 'invoice', child: Text('طباعة الفاتورة'))]))])).toList()))]; } }

class GuestsPage extends ConsumerStatefulWidget { const GuestsPage({super.key}); @override ConsumerState<GuestsPage> createState() => _GuestsPageState(); }
class _GuestsPageState extends ConsumerState<GuestsPage> { Timer? _searchDebounce; String search = ''; @override void dispose() { _searchDebounce?.cancel(); super.dispose(); } @override Widget build(BuildContext context) { final c = ref.watch(appControllerProvider); final list = c.queryGuests(search); return ListView(padding: const EdgeInsets.all(24), children: [TextField(onChanged: (v) { _searchDebounce?.cancel(); _searchDebounce = Timer(const Duration(milliseconds: 150), () { if (mounted) setState(() => search = v); }); }, decoration: const InputDecoration(labelText: 'البحث بالاسم أو الهاتف أو رقم الهوية', prefixIcon: Icon(Icons.search), border: OutlineInputBorder())), const SizedBox(height: 16), Card(child: ListView.separated(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: list.length, separatorBuilder: (_, __) => const Divider(height: 1), itemBuilder: (_, i) { final g = list[i]; final history = c.stayCountForGuest(g.id); return ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), leading: CircleAvatar(child: Text(g.name.isEmpty ? '?' : g.name[0])), title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text('${g.phone} • ${g.nationality} • ${g.nationalId}'), trailing: Text('$history إقامة'); }))]; } }

class ReportsPage extends ConsumerWidget { const ReportsPage({super.key}); @override Widget build(BuildContext context, WidgetRef ref) { final c = ref.watch(appControllerProvider); final checkedIn = c.bookings.where((b) => b.status == 'checkedIn').length; final pending = c.bookings.where((b) => b.status == 'pending').length; return ListView(padding: const EdgeInsets.all(24), children: [Text('ملخص الأداء', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 18), Wrap(spacing: 16, runSpacing: 16, children: [StatCard(label: 'إيرادات الحجوزات', value: '${_moneyFormat.format(c.revenue)} ر.س', icon: Icons.payments, color: Colors.indigo), StatCard(label: 'إقامات نشطة', value: '$checkedIn', icon: Icons.nights_stay, color: Colors.teal), StatCard(label: 'حجوزات معلقة', value: '$pending', icon: Icons.pending_actions, color: Colors.orange)]), const SizedBox(height: 24), Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('تقرير الوردية', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 16), const ListTile(leading: Icon(Icons.nightlight_round), title: Text('الوردية الليلية'), subtitle: Text('تقرير الوصول والمغادرة والتسويات اليومية'), trailing: Icon(Icons.chevron_left)), const Divider(), const ListTile(leading: Icon(Icons.wb_sunny_outlined), title: Text('الوردية النهارية'), subtitle: Text('حالة الغرف والحجوزات الجديدة'), trailing: Icon(Icons.chevron_left))])))]); } }

class SettingsPage extends ConsumerStatefulWidget { const SettingsPage({super.key, required this.isAdmin}); final bool isAdmin; @override ConsumerState<SettingsPage> createState() => _SettingsPageState(); }
class _SettingsPageState extends ConsumerState<SettingsPage> { late final TextEditingController name; @override void initState() { super.initState(); name = TextEditingController(); } @override void dispose() { name.dispose(); super.dispose(); } @override Widget build(BuildContext context) { final c = ref.watch(appControllerProvider); if (name.text.isEmpty) name.text = c.hotelName; if (!widget.isAdmin) return const Center(child: Text('هذه الصفحة متاحة لمدير النظام فقط')); return ListView(padding: const EdgeInsets.all(24), children: [Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('إعدادات الفندق', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 18), TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الفندق', prefixIcon: Icon(Icons.hotel), border: OutlineInputBorder())), const SizedBox(height: 14), FilledButton(onPressed: () async { await c.updateHotelName(name.text); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الإعدادات'))); }, child: const Text('حفظ'))])), const SizedBox(height: 18), Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('المستخدمون والصلاحيات', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 12), ...c.users.map((u) => ListTile(leading: const Icon(Icons.account_circle_outlined), title: Text(u.name), subtitle: Text('${u.username} • ${roleLabel(u.role)}'), trailing: Switch(value: u.isActive, onChanged: null))), const SizedBox(height: 8), OutlinedButton.icon(onPressed: () => showAddUserDialog(context), icon: const Icon(Icons.person_add), label: const Text('إضافة مستخدم'))])), const SizedBox(height: 18), Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('حماية البيانات', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 8), const Text('أنشئ نسخة احتياطية دورية واحفظها خارج الجهاز. ملف النسخة يحتوي على بيانات تشغيلية حساسة.'), const SizedBox(height: 14), Wrap(spacing: 10, runSpacing: 10, children: [FilledButton.icon(onPressed: () => exportBackupToFile(context), icon: const Icon(Icons.download), label: const Text('تصدير نسخة')), OutlinedButton.icon(onPressed: () => restoreBackupFromFile(context), icon: const Icon(Icons.restore), label: const Text('استعادة نسخة'))])]))), const SizedBox(height: 18), Card(child: const ListTile(leading: Icon(Icons.cloud_outlined), title: Text('Firebase'), subtitle: Text('جاهز للتفعيل مستقبلاً — التخزين المحلي يعمل حالياً عبر Hive/IndexedDB'), trailing: Chip(label: Text('معطل'))))]); } }

Future<void> showRoomDetails(BuildContext context, RoomRecord room) async {
  final c = ProviderScope.containerOf(context).read(appControllerProvider);
  final booking = c.activeBookingForRoom(room.id);
  final guest = booking == null ? null : c.guestById(booking.guestId);
  await showDialog(context: context, builder: (_) => AlertDialog(title: Row(children: [CircleAvatar(backgroundColor: statusColor(room.status).withOpacity(.12), child: Icon(Icons.meeting_room, color: statusColor(room.status))), const SizedBox(width: 12), Text('غرفة ${room.number}')]), content: SizedBox(width: 430, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${room.type} • الطابق ${room.floor}', style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 16), DetailLine(icon: Icons.circle, label: 'الحالة', value: statusLabel(room.status), color: statusColor(room.status)), DetailLine(icon: Icons.payments_outlined, label: 'السعر', value: '${_moneyFormat.format(room.price)} ر.س / ليلة'), if (guest != null) ...[const Divider(height: 24), Text('الإقامة الحالية', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)), DetailLine(icon: Icons.person_outline, label: 'الضيف', value: guest.name), DetailLine(icon: Icons.calendar_today_outlined, label: 'الفترة', value: '${dateLabel(booking!.checkIn)} — ${dateLabel(booking!.checkOut)}'), DetailLine(icon: Icons.receipt_long_outlined, label: 'رقم الحجز', value: booking!.number)] else ...[const Divider(height: 24), Row(children: [Icon(room.status == 'available' ? Icons.check_circle : Icons.info_outline, color: statusColor(room.status)), const SizedBox(width: 8), Text(room.status == 'available' ? 'الغرفة جاهزة لاستقبال حجز جديد' : 'لا توجد إقامة نشطة حالياً')])]])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')), PopupMenuButton<String>(onSelected: (value) { c.updateRoomStatus(room, value); Navigator.pop(context); }, itemBuilder: (_) => ['available', 'occupied', 'maintenance', 'cleaning'].map((v) => PopupMenuItem(value: v, child: Text(statusLabel(v)))).toList(), child: const FilledButton(onPressed: null, child: Text('تغيير الحالة')))]));
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

Future<void> exportBackupToFile(BuildContext context) async {
  final c = ProviderScope.containerOf(context).read(appControllerProvider);
  try {
    final bytes = Uint8List.fromList(utf8.encode(JsonEncoder.withIndent('  ').convert(c.exportBackup())));
    await FileSaver.instance.saveFile(name: 'miftah-backup-${DateTime.now().toIso8601String().replaceAll(':', '-')}', bytes: bytes, fileExtension: 'json', mimeType: MimeType.other);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تصدير النسخة الاحتياطية. احفظها في مكان آمن.')));
  } catch (error) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تصدير النسخة: $error')));
  }
}

Future<void> restoreBackupFromFile(BuildContext context) async {
  final c = ProviderScope.containerOf(context).read(appControllerProvider);
  try {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['json'], withData: true);
    if (result == null || result.files.single.bytes == null) return;
    final decoded = jsonDecode(utf8.decode(result.files.single.bytes!));
    if (decoded is! Map) throw const FormatException('ملف النسخة غير صالح');
    await c.restoreBackup(Map<String, dynamic>.from(decoded));
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت استعادة البيانات بنجاح.')));
  } catch (error) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر استعادة النسخة: $error')));
  }
}

Future<void> showAddRoomDialog(BuildContext context) async { final number = TextEditingController(), floor = TextEditingController(text: '1'), price = TextEditingController(text: '200'); String type = 'مفردة'; await showDialog(context: context, builder: (_) => StatefulBuilder(builder: (context, set) => AlertDialog(title: const Text('إضافة غرفة'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: number, decoration: const InputDecoration(labelText: 'رقم الغرفة')), TextField(controller: floor, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الطابق')), TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر لليلة')), DropdownButtonFormField(value: type, decoration: const InputDecoration(labelText: 'النوع'), items: ['مفردة', 'مزدوجة', 'جناح', 'VIP'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => set(() => type = v!))]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')), FilledButton(onPressed: () { if (number.text.isNotEmpty) { final c = ProviderScope.containerOf(context).read(appControllerProvider); c.addRoom(number.text, type, int.tryParse(floor.text) ?? 1, double.tryParse(price.text) ?? 0); Navigator.pop(context); } }, child: const Text('إضافة'))])); }

Future<void> showAddGuestDialog(BuildContext context) async { final name = TextEditingController(), phone = TextEditingController(), id = TextEditingController(), nationality = TextEditingController(text: 'سعودي'), email = TextEditingController(); await showDialog(context: context, builder: (_) => AlertDialog(title: const Text('إضافة عميل'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم الكامل')), TextField(controller: phone, decoration: const InputDecoration(labelText: 'الهاتف')), TextField(controller: id, decoration: const InputDecoration(labelText: 'رقم الهوية')), TextField(controller: nationality, decoration: const InputDecoration(labelText: 'الجنسية')), TextField(controller: email, decoration: const InputDecoration(labelText: 'البريد الإلكتروني'))])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')), FilledButton(onPressed: () { if (name.text.isNotEmpty) { ProviderScope.containerOf(context).read(appControllerProvider).addGuest(name.text, phone.text, id.text, nationality.text, email.text); Navigator.pop(context); } }, child: const Text('حفظ'))])); }

Future<void> showAddBookingDialog(BuildContext context) async { final c = ProviderScope.containerOf(context).read(appControllerProvider); if (c.guests.isEmpty || c.rooms.where((r) => r.status == 'available').isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف عميلاً وغرفة شاغرة أولاً'))); return; } String guest = c.guests.first.id, room = c.rooms.firstWhere((r) => r.status == 'available').id; DateTime start = DateTime.now(), end = DateTime.now().add(const Duration(days: 1)); final notes = TextEditingController(); await showDialog(context: context, builder: (_) => StatefulBuilder(builder: (context, set) => AlertDialog(title: const Text('إنشاء حجز جديد'), content: Column(mainAxisSize: MainAxisSize.min, children: [DropdownButtonFormField(value: guest, decoration: const InputDecoration(labelText: 'العميل'), items: c.guests.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name))).toList(), onChanged: (v) => set(() => guest = v!)), DropdownButtonFormField(value: room, decoration: const InputDecoration(labelText: 'الغرفة'), items: c.rooms.where((r) => r.status == 'available').map((r) => DropdownMenuItem(value: r.id, child: Text('${r.number} — ${r.type}'))).toList(), onChanged: (v) => set(() => room = v!)), ListTile(title: Text('الوصول: ${dateLabel(start)}'), trailing: const Icon(Icons.calendar_today), onTap: () async { final d = await showDatePicker(context: context, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 365)), initialDate: start); if (d != null) set(() => start = d); }), ListTile(title: Text('المغادرة: ${dateLabel(end)}'), trailing: const Icon(Icons.calendar_today), onTap: () async { final d = await showDatePicker(context: context, firstDate: start.add(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 365)), initialDate: end); if (d != null) set(() => end = d); }), TextField(controller: notes, decoration: const InputDecoration(labelText: 'ملاحظات'))]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')), FilledButton(onPressed: () { c.addBooking(guest, room, start, end, notes.text); Navigator.pop(context); }, child: const Text('إنشاء الحجز'))]))); }

Future<void> showAddUserDialog(BuildContext context) async { final name = TextEditingController(), username = TextEditingController(), password = TextEditingController(); String role = 'receptionist'; await showDialog(context: context, builder: (_) => StatefulBuilder(builder: (context, set) => AlertDialog(title: const Text('إضافة مستخدم'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')), TextField(controller: username, decoration: const InputDecoration(labelText: 'اسم المستخدم')), TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور')), DropdownButtonFormField(value: role, decoration: const InputDecoration(labelText: 'الدور'), items: const [DropdownMenuItem(value: 'receptionist', child: Text('موظف استقبال')), DropdownMenuItem(value: 'nightShift', child: Text('وردية ليلية')), DropdownMenuItem(value: 'dayShift', child: Text('وردية نهارية'))], onChanged: (v) => set(() => role = v!))]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')), FilledButton(onPressed: () { if (name.text.isNotEmpty && username.text.isNotEmpty && password.text.isNotEmpty) { ProviderScope.containerOf(context).read(appControllerProvider).addUser(name.text, username.text, password.text, role); Navigator.pop(context); } }, child: const Text('إضافة'))])); }
