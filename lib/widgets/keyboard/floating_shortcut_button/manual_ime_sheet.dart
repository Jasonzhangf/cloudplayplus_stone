part of floating_shortcut_button;

class _ManualImeTextEditSheet extends StatefulWidget {
  final String title;
  final TextEditingController controller;
  final String hintText;
  final String okText;

  const _ManualImeTextEditSheet({
    required this.title,
    required this.controller,
    required this.hintText,
    required this.okText,
  });

  @override
  State<_ManualImeTextEditSheet> createState() =>
      _ManualImeTextEditSheetState();
}

class _ManualImeTextEditSheetState extends State<_ManualImeTextEditSheet> {
  final FocusNode _focusNode = FocusNode();
  bool _imeEnabled = false;
  bool _lastImeVisible = false;

  final _kb = KeyboardStateManager.instance;
  bool _prevLocalTextEditing = false;

  @override
  void initState() {
    super.initState();
    _prevLocalTextEditing = ScreenController.localTextEditing.value;
    ScreenController.setLocalTextEditing(true);
    ScreenController.setSystemImeActive(false);
    _kb.requestOwner();
    try {
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    } catch (_) {}
    _kb.releaseOwner();
    _focusNode.dispose();
    ScreenController.setLocalTextEditing(_prevLocalTextEditing);
    super.dispose();
  }

  void _toggleIme() {
    final want = !_imeEnabled;
    setState(() => _imeEnabled = want);
    if (!want) {
      try {
        FocusScope.of(context).unfocus();
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      } catch (_) {}
      _kb.releaseOwner();
      return;
    }
    _kb.requestOwner();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        FocusScope.of(context).requestFocus(_focusNode);
        SystemChannels.textInput.invokeMethod('TextInput.show');
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final imeVisible = bottomInset > 0;
      final prev = _lastImeVisible;
      _lastImeVisible = imeVisible;

      _kb.onImeVisibleChanged(imeVisible);

      if (_imeEnabled && prev && !imeVisible) {
        setState(() => _imeEnabled = false);
        try {
          FocusScope.of(context).unfocus();
        } catch (_) {}
        _kb.releaseOwner();
      }
    });
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _imeEnabled ? '隐藏输入法' : '唤起输入法',
                    icon: Icon(
                      _imeEnabled
                          ? Icons.keyboard_hide_outlined
                          : Icons.keyboard_alt_outlined,
                    ),
                    onPressed: _toggleIme,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                autofocus: false,
                readOnly: !_imeEnabled,
                showCursor: _imeEnabled,
                keyboardType: _imeEnabled ? TextInputType.text : TextInputType.none,
                enableSuggestions: _imeEnabled,
                autocorrect: _imeEnabled,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () =>
                          Navigator.pop(context, widget.controller.text.trim()),
                      child: Text(widget.okText),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
