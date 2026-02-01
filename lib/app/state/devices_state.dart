import 'package:cloudplayplus/entities/device.dart';
import 'package:flutter/foundation.dart';

@immutable
class DevicesState {
  final List<Device> devices;
  final int onlineUsers;

  const DevicesState({
    this.devices = const <Device>[],
    this.onlineUsers = 0,
  });

  DevicesState copyWith({
    List<Device>? devices,
    int? onlineUsers,
  }) {
    return DevicesState(
      devices: devices ?? this.devices,
      onlineUsers: onlineUsers ?? this.onlineUsers,
    );
  }
}

