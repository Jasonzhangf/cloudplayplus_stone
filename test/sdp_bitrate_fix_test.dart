import 'package:cloudplayplus/entities/session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fixSdpBitrateForVideo only touches video section', () {
    const sdp = 'v=0\r\n'
        'o=- 0 0 IN IP4 127.0.0.1\r\n'
        's=-\r\n'
        't=0 0\r\n'
        'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
        'c=IN IP4 0.0.0.0\r\n'
        'a=fmtp:111 minptime=10;useinbandfec=1\r\n'
        'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
        'c=IN IP4 0.0.0.0\r\n'
        'a=fmtp:96 level-asymmetry-allowed=1;packetization-mode=1\r\n';

    final fixed = fixSdpBitrateForVideo(sdp, 2000);
    // Audio fmtp should remain unchanged.
    expect(fixed.contains('a=fmtp:111 minptime=10;useinbandfec=1\r\n'), isTrue);
    // Video fmtp should have google bitrate params.
    expect(fixed.contains('a=fmtp:96 level-asymmetry-allowed=1;packetization-mode=1;'
        'x-google-max-bitrate=2000;x-google-min-bitrate=2000;x-google-start-bitrate=2000\r\n'), isTrue);
    // b=AS should be inserted in video section (after its c=IN).
    expect(fixed.contains('m=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
        'c=IN IP4 0.0.0.0\r\n'
        'b=AS:2000\r\n'), isTrue);
    // b=AS should not be inserted for audio section.
    expect(fixed.contains('m=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
        'c=IN IP4 0.0.0.0\r\n'
        'b=AS:2000\r\n'), isFalse);
  });
}

