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
        data = await send(ws, "list_iterm2_panels", None, "panels")
        panels = data.get("panels", [])
        if not panels:
            raise RuntimeError("No panels")

        burst = panels[: min(5, len(panels))]
        for r in range(10):
            for p in burst:
                await send(
                    ws,
                    "set_capture_target",
                    {
                        "type": "iterm2",
                        "iterm2SessionId": p["id"],
                        "cgWindowId": p.get("cgWindowId"),
                    },
                )
                await asyncio.sleep(0.1)

        state = await send(ws, "get_state", None, "state")
        print("OK", json.dumps(state, ensure_ascii=False))


if __name__ == "__main__":
    asyncio.run(main())
