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
    if not resp.get('success', False):
        raise RuntimeError(resp)
    return resp.get('data')

async def main():
    async with websockets.connect(CTRL) as ws:
        await send(ws, 'connect', {'host': '127.0.0.1', 'port': 17999}, '1')
        await send(ws, 'refresh_targets', None, '2')
        data = await send(ws, 'list_iterm2_panels', None, '3')
        panels = data.get('panels', [])
        if not panels:
            raise RuntimeError('No panels available')

        # Pick 1.1.8 else first
        target = next((p for p in panels if p.get('title') == '1.1.8'), panels[0])
        await send(ws, 'set_capture_target', {
            'type': 'iterm2',
            'iterm2SessionId': target['id'],
            'cgWindowId': target.get('cgWindowId')
        }, '4')

        # Burst switching
        burst = panels[: min(5, len(panels))]
        for r in range(10):
            for p in burst:
                await send(ws, 'set_capture_target', {
                    'type': 'iterm2',
                    'iterm2SessionId': p['id'],
                    'cgWindowId': p.get('cgWindowId')
                })
                await asyncio.sleep(0.1)

        state = await send(ws, 'get_state', None, 'state')
        # Minimal assert: still has 1 session
        if state.get('sessions', 0) < 1:
            raise RuntimeError(f'No sessions after switching: {state}')

if __name__ == '__main__':
    asyncio.run(main())
