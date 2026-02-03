import asyncio
import json
import websockets

CTRL = 'ws://127.0.0.1:19002'

async def send(ws, cmd, params=None, _id=None):
    payload = {'cmd': cmd}
    if _id is not None:
        payload['id'] = _id
    if params is not None:
        payload['params'] = params
    await ws.send(json.dumps(payload))
    resp = json.loads(await ws.recv())
    print(json.dumps(resp, ensure_ascii=False))
    if not resp.get('success', False):
        raise RuntimeError(resp)
    return resp.get('data')

async def main():
    async with websockets.connect(CTRL) as ws:
        # Minimal preflight to catch "controller not up" quickly.
        await send(ws, 'ping', None, 'ping')
        await send(ws, 'connect', {'host': '127.0.0.1', 'port': 17999}, '1')
        await send(ws, 'refresh_targets', None, '2')
        panels = (await send(ws, 'list_iterm2_panels', None, '3')).get('panels', [])
        # pick 1.1.8 else first
        target = None
        for p in panels:
            if p.get('title') == '1.1.8':
                target = p
                break
        if target is None and panels:
            target = panels[0]
        if not target:
            raise RuntimeError('No panels available')

        sid = target['id']
        await send(ws, 'set_capture_target', {
            'type': 'iterm2',
            'iterm2SessionId': sid,
            'cgWindowId': target.get('cgWindowId')
        }, '4')

        # rapid switching among first 5 panels (10 times)
        n = min(5, len(panels))
        for i in range(10):
            p = panels[i % n]
            await send(ws, 'set_capture_target', {
                'type': 'iterm2',
                'iterm2SessionId': p['id'],
                'cgWindowId': p.get('cgWindowId')
            }, f'sw{i}')
            await asyncio.sleep(0.15)

        await send(ws, 'get_state', None, 'state')

asyncio.run(main())
