class LanAddressService {
  LanAddressService._();
  static final LanAddressService instance = LanAddressService._();

  Future<List<String>> listLocalAddresses() async => const <String>[];

  List<String> rankHostsForConnect(List<String> addrs) =>
      addrs.toList(growable: false);
}
