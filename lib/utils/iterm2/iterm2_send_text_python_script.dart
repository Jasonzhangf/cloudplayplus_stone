/// Python script used by the macOS host to send UTF-8 text into an iTerm2 session.
///
/// Args:
///   argv[1] = session_id
///   argv[2] = text base64 (UTF-8)
///
/// Kept as a standalone constant so we can unit test it for syntax/indentation.
const String iterm2SendTextPythonScript = r'''
import base64
import json
import sys

try:
    import iterm2
except Exception as e:
    print(json.dumps({"ok": False, "error": f"iterm2 module not available: {e}"}, ensure_ascii=False))
    raise SystemExit(0)

SESSION_ID = sys.argv[1] if len(sys.argv) > 1 else ""
TEXT_B64 = sys.argv[2] if len(sys.argv) > 2 else ""

def decode_text(b64: str) -> str:
    try:
        raw = base64.b64decode(b64.encode("ascii"), validate=False)
        return raw.decode("utf-8", errors="replace")
    except Exception:
        return ""

text = decode_text(TEXT_B64)
if not text:
    raise SystemExit(0)

# TTY compatibility:
# - Enter is usually carriage return.
# - Backspace is usually DEL (0x7f).
text = text.replace("\r\n", "\r").replace("\n", "\r")
text = text.replace("\b", "\x7f")

async def main(connection):
    app = await iterm2.async_get_app(connection)
    target = None
    for win in app.terminal_windows:
        for tab in win.tabs:
            for sess in tab.sessions:
                if sess.session_id == SESSION_ID:
                    target = sess
                    break
            if target:
                break
        if target:
            break
    if not target:
        print(json.dumps({"ok": False, "error": f"session not found: {SESSION_ID}"}, ensure_ascii=False))
        return
    try:
        await target.async_send_text(text)
        print(json.dumps({"ok": True}, ensure_ascii=False))
    except Exception as e:
        print(json.dumps({"ok": False, "error": str(e)}, ensure_ascii=False))

iterm2.run_until_complete(main)
''';

