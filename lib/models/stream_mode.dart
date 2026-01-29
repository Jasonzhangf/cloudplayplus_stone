enum StreamMode {
  desktop,
  window,
  iterm2,
}

String streamModeLabel(StreamMode mode) {
  switch (mode) {
    case StreamMode.desktop:
      return '桌面模式';
    case StreamMode.window:
      return '窗口模式';
    case StreamMode.iterm2:
      return 'iTerm2 模式';
  }
}

