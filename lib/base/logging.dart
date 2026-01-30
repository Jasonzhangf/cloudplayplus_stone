import '../dev_settings.dart/develop_settings.dart';
import 'package:flutter/foundation.dart';

// ignore: non_constant_identifier_names
void VLOG0(Object? s) {
  if (kDebugMode || DevelopSettings.isDebugging) {
    print(s);
  }
}
