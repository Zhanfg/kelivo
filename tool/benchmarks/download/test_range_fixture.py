"""Standard-library contract tests for deterministic download fixture."""
import http.client
import threading
import unittest
from range_fixture import RangeFixture
from http.server import ThreadingHTTPServer


class FixtureTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), RangeFixture)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def request(self, path='/', headers=None, method='GET', incomplete=False):
        conn = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=8)
        conn.request(method, path, headers=headers or {})
        response = conn.getresponse()
        meta = response.status, dict(response.getheaders())
        if incomplete:
            conn.close()
            return meta
        body = response.read()
        conn.close()
        return (*meta, body)

    def test_full_and_head(self):
        status, headers, body = self.request()
        self.assertEqual(status, 200)
        self.assertEqual(len(body), len(RangeFixture.data))
        self.assertEqual(body, RangeFixture.data)
        status, headers, body = self.request(method='HEAD')
        self.assertEqual(status, 200)
        self.assertEqual(body, b'')

    def test_partial_and_suffix(self):
        status, headers, body = self.request(headers={'Range': 'bytes=10-19'})
        self.assertEqual((status, len(body)), (206, 10))
        self.assertEqual(headers['Content-Range'], f'bytes 10-19/{len(RangeFixture.data)}')
        status, _, body = self.request(headers={'Range': 'bytes=-4'})
        self.assertEqual((status, body), (206, RangeFixture.data[-4:]))

    def test_416(self):
        status, headers, body = self.request(headers={'Range': 'bytes=99999999-'})
        self.assertEqual((status, body), (416, b''))
        self.assertEqual(headers['Content-Range'], f'bytes */{len(RangeFixture.data)}')

    def test_ignore_range_and_if_range(self):
        status, _, body = self.request('/?mode=ignore-range', {'Range': 'bytes=0-1'})
        self.assertEqual((status, len(body)), (200, len(RangeFixture.data)))
        status, _, body = self.request('/', {'Range': 'bytes=0-1', 'If-Range': '"obsolete"'})
        self.assertEqual((status, len(body)), (200, len(RangeFixture.data)))

    def test_etag_change(self):
        _, original, _ = self.request(headers={'Range': 'bytes=0-1'})
        _, changed, _ = self.request('/?mode=etag-change', {'Range': 'bytes=0-1'})
        self.assertNotEqual(original['ETag'], changed['ETag'])

    def test_disconnect_and_throttle(self):
        status, headers = self.request('/?mode=disconnect', incomplete=True)
        self.assertEqual(status, 200)
        self.assertEqual(int(headers['Content-Length']), len(RangeFixture.data))
        status, _, body = self.request('/?mode=throttle', {'Range': 'bytes=0-4095'})
        self.assertEqual((status, len(body)), (206, 4096))


if __name__ == '__main__':
    unittest.main()
