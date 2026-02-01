import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../intents/app_intent.dart';
import '../store/app_store.dart';

/// Bridges Flutter app lifecycle events into [AppStore] as intents.
///
/// This keeps lifecycle-driven reconnect logic out of pages/services.
class AppLifecycleBridge extends StatefulWidget {
  final Widget child;
  const AppLifecycleBridge({super.key, required this.child});

  @override
  State<AppLifecycleBridge> createState() => _AppLifecycleBridgeState();
}

class _AppLifecycleBridgeState extends State<AppLifecycleBridge>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Best-effort: the store may not be available during early boot.
    try {
      context
          .read<AppStore>()
          .dispatch(AppIntentAppLifecycleChanged(state: state));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

