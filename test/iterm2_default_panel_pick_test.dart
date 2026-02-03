import 'package:cloudplayplus/models/iterm2_panel.dart';
import 'package:cloudplayplus/utils/iterm2/iterm2_panel_sort.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pickDefaultIterm2Panel chooses the smallest win.tab.panel', () {
    final panels = [
      const ITerm2PanelInfo(
        id: 's3',
        title: '2.1.1',
        detail: '',
        index: 0,
        layoutFrame: {'x': 0, 'y': 100, 'w': 100, 'h': 100},
      ),
      const ITerm2PanelInfo(
        id: 's2',
        title: '1.2.1',
        detail: '',
        index: 1,
        layoutFrame: {'x': 100, 'y': 0, 'w': 100, 'h': 100},
      ),
      const ITerm2PanelInfo(
        id: 's1',
        title: '1.1.2',
        detail: '',
        index: 2,
        layoutFrame: {'x': 100, 'y': 0, 'w': 100, 'h': 100},
      ),
      const ITerm2PanelInfo(
        id: 's0',
        title: '1.1.1',
        detail: '',
        index: 3,
        layoutFrame: {'x': 0, 'y': 0, 'w': 100, 'h': 100},
      ),
    ];
    expect(pickDefaultIterm2Panel(panels)?.title, '1.1.1');
  });
}
