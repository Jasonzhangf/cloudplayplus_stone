import 'package:cloudplayplus/entities/device.dart';
import 'package:cloudplayplus/services/lan/lan_device_hint_codec.dart';

typedef DeviceFallbackResolver = Device? Function(String connectionId);

/// Merges an incoming device list payload into an existing [Device] list while
/// preserving object identity whenever possible.
///
/// Why: pages may hold a reference to a [Device] instance; if the list refresh
/// replaces that object, connection state updates (ValueNotifier) land on a
/// different instance and UI becomes stale.
List<Device> mergeDeviceList({
  required List<Device> previous,
  required List<dynamic> incoming,
  required String selfConnectionId,
  DeviceFallbackResolver? fallbackByConnectionId,
}) {
  final prevByConnId = <String, Device>{};
  for (final d in previous) {
    final id = d.websocketSessionid;
    if (id.isNotEmpty) prevByConnId[id] = d;
  }

  final next = <Device>[];

  for (final item in incoming) {
    if (item is! Map) continue;
    final device = item.map((k, v) => MapEntry(k.toString(), v));

    final connId = (device['connection_id'] ?? '').toString();
    if (connId.isEmpty) continue;

    final connectiveAny = device['connective'];
    final connective = (connectiveAny is bool) ? connectiveAny : false;
    if (!connective && connId != selfConnectionId) {
      continue;
    }

    Device? instance = prevByConnId[connId];
    instance ??= fallbackByConnectionId?.call(connId);

    if (instance == null) {
      next.add(Device.fromJson(device));
      continue;
    }

    final decoded = LanDeviceNameCodec.decode((device['device_name'] ?? '').toString());
    final hints = decoded.hints;
    instance.devicename = decoded.name;
    instance.connective = connective;
    instance.screencount = (device['screen_count'] is num)
        ? (device['screen_count'] as num).toInt()
        : instance.screencount;
    instance.websocketSessionid = connId;

    final lanAddrsFromPayload = (device['lanAddrs'] is List)
        ? (device['lanAddrs'] as List)
            .map((e) => e?.toString() ?? '')
            .where((e) => e.isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    instance.lanAddrs =
        lanAddrsFromPayload.isNotEmpty ? lanAddrsFromPayload : (hints?.lanAddrs ?? const <String>[]);

    final lanPortFromPayload =
        (device['lanPort'] is num) ? (device['lanPort'] as num).toInt() : null;
    instance.lanPort = lanPortFromPayload ?? hints?.lanPort;

    final lanEnabledAny = device['lanEnabled'];
    final lanEnabledFromPayload = (lanEnabledAny is bool) ? lanEnabledAny : false;
    instance.lanEnabled = lanEnabledFromPayload || (hints?.lanEnabled ?? false);

    next.add(instance);
  }

  return next;
}

