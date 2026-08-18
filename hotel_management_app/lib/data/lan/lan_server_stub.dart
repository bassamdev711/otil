import '../local/hotel_local_store.dart';

class LanServerController {
  bool get running => false;
  String? get token => null;
  String? get address => null;
  String? get url => null;
  Future<void> start(HotelDataSource store, {int port = 8787}) async {}
  Future<void> stop() async {}
}
