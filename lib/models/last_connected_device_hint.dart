import 'dart:convert';

class LastConnectedDeviceHint {
  final int uid;
  final String nickname;
  final String devicename;
  final String devicetype;

  const LastConnectedDeviceHint({
    required this.uid,
    required this.nickname,
    required this.devicename,
    required this.devicetype,
  });

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'nickname': nickname,
        'devicename': devicename,
        'devicetype': devicetype,
      };

  static LastConnectedDeviceHint? tryParse(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final uidAny = decoded['uid'];
      final uid = uidAny is num ? uidAny.toInt() : int.tryParse('$uidAny');
      if (uid == null || uid <= 0) return null;
      final nickname = (decoded['nickname'] ?? '').toString();
      final devicename = (decoded['devicename'] ?? '').toString();
      final devicetype = (decoded['devicetype'] ?? '').toString();
      if (devicename.isEmpty || devicetype.isEmpty) return null;
      return LastConnectedDeviceHint(
        uid: uid,
        nickname: nickname,
        devicename: devicename,
        devicetype: devicetype,
      );
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode(toJson());
}

