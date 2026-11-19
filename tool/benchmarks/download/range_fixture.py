#!/usr/bin/env python3
"""Deterministic HTTP Range/ETag fault-injection fixture. Standard library only."""
import argparse
import hashlib
import http.server
import json
import time
from urllib.parse import parse_qs, urlsplit


def payload(size: int) -> bytes:
    block = bytes(range(256))
    return (block * (size // len(block) + 1))[:size]


class RangeFixture(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    data = payload(1024 * 1024)
    counters = {}

    def log_message(self, fmt, *args):
        pass

    def do_HEAD(self):
        self.respond(head_only=True)

    def do_GET(self):
        self.respond(head_only=False)

    def respond(self, head_only=False):
        query = parse_qs(urlsplit(self.path).query)
        mode = query.get('mode', ['normal'])[0]
        size = len(self.data)
        etag = '"' + hashlib.sha256(self.data).hexdigest()[:16] + '"'
        if mode == 'etag-change':
            etag = '"changed-' + etag[1:]
        request_range = self.headers.get('Range')
        if_range = self.headers.get('If-Range')
        if if_range and if_range != etag:
            request_range = None
        if mode == 'ignore-range':
            request_range = None
        status, start, end = 200, 0, size - 1
        if request_range:
            try:
                unit, value = request_range.split('=', 1)
                if unit != 'bytes' or ',' in value:
                    raise ValueError('invalid unit or multiple ranges')
                left, right = value.split('-', 1)
                if not left:
                    suffix = int(right)
                    if suffix <= 0:
                        raise ValueError('invalid suffix')
                    start = max(0, size - suffix)
                else:
                    start = int(left)
                end = int(right) if left and right else size - 1
                if start < 0 or start >= size or end < start:
                    raise ValueError('unsatisfiable')
                end = min(end, size - 1)
                status = 206
            except (ValueError, OverflowError):
                self.send_response(416)
                self.send_header('Content-Range', f'bytes */{size}')
                self.send_header('Content-Length', '0')
                self.end_headers()
                return
        body = self.data[start:end + 1]
        self.send_response(status)
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('ETag', etag)
        self.send_header('Content-Type', 'application/octet-stream')
        if status == 206:
            self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        if head_only:
            return
        delay_ms = min(int(query.get('delay_ms', ['0'])[0]), 3000)
        if delay_ms > 0:
            time.sleep(delay_ms / 1000)
        if mode == 'disconnect':
            self.wfile.write(body[:min(len(body), 8192)])
            self.wfile.flush()
            self.close_connection = True
            return
        if mode == 'throttle':
            for i in range(0, len(body), 4096):
                self.wfile.write(body[i:i + 4096])
                self.wfile.flush()
                time.sleep(0.004)
        else:
            self.wfile.write(body)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=0)
    parser.add_argument('--size', type=int, default=1048576)
    args = parser.parse_args()
    if not 1 <= args.size <= 64 * 1024 * 1024:
        parser.error('--size must be between 1 and 67108864')
    RangeFixture.data = payload(args.size)
    server = http.server.ThreadingHTTPServer((args.host, args.port), RangeFixture)
    print(json.dumps({'host': args.host, 'port': server.server_port, 'size': args.size}), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
