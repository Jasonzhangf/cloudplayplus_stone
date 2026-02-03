import asyncio
import json
import sys

try:
    import websockets
except ImportError:
    print('Please install websockets: pip install websockets', file=sys.stderr)
    sys.exit(2)


async def main():
    if len(sys.argv) < 3:
        print('Usage: python3 scripts/cli_send.py <ws_url> <json>', file=sys.stderr)
        sys.exit(2)

    url = sys.argv[1]
    payload = json.loads(sys.argv[2])

    async with websockets.connect(url) as ws:
        await ws.send(json.dumps(payload))
        resp = await ws.recv()
        print(resp)


if __name__ == '__main__':
    asyncio.run(main())
