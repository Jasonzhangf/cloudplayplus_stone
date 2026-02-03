import asyncio
import json
import time

import websockets


CTRL = "ws://127.0.0.1:19002"


async def send(ws, cmd, params=None, _id=None):
    payload = {"cmd": cmd}
    if _id is not None:
        payload["id"] = _id
    if params is not None:
        payload["params"] = params
    await ws.send(json.dumps(payload))
    resp = json.loads(await ws.recv())
    print(json.dumps(resp, ensure_ascii=False))
    if not resp.get("success", False):
        raise RuntimeError(resp)
    return resp.get("data")


async def wait_for_ctrl(timeout_s=10.0):
    start = time.time()
    while time.time() - start < timeout_s:
        try:
            async with websockets.connect(CTRL) as ws:
                await send(ws, "ping", None, "ping")
                return True
        except Exception:
            await asyncio.sleep(0.2)
    return False


async def main():
    if not await wait_for_ctrl():
        raise RuntimeError("controller CLI not ready on 19002")
    async with websockets.connect(CTRL) as ws:
        await send(ws, "connect", {"host": "127.0.0.1", "port": 17999}, "1")
        await send(ws, "refresh_targets", None, "2")
        data = await send(ws, "list_iterm2_panels", None, "3")
        panels = data.get("panels", [])
        if not panels:
            raise RuntimeError("No panels")
        target = next((p for p in panels if p.get("title") == "1.1.8"), panels[0])
        if not target.get("cgWindowId"):
            raise RuntimeError(f"Missing cgWindowId for {target.get('id')}")
        await send(
            ws,
            "set_capture_target",
            {
                "type": "iterm2",
                "iterm2SessionId": target["id"],
                "cgWindowId": target.get("cgWindowId"),
            },
            "4",
        )
        await send(ws, "get_state", None, "state")


if __name__ == "__main__":
    asyncio.run(main())
