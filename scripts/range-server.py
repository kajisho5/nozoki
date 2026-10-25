#!/usr/bin/env python3
"""試験用：ファイルの一部だけを返せる（HTTP の Range に対応した）小さなサーバー。
使い方: python3 scripts/range-server.py <配るフォルダ> <ポート番号>"""
import http.server, os, re, sys, functools

class H(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        path = self.translate_path(self.path)
        if not os.path.isfile(path):
            self.send_error(404)
            return
        size = os.path.getsize(path)
        rng = self.headers.get('Range')
        if not rng:
            self.send_response(200)
            self.send_header('Content-Length', str(size))
            self.end_headers()
            with open(path, 'rb') as f:
                self.wfile.write(f.read())
            return
        m = re.match(r'bytes=(\d*)-(\d*)', rng)
        a, b = m.group(1), m.group(2)
        if a == '':
            start, end = max(0, size - int(b)), size - 1
        else:
            start, end = int(a), (int(b) if b else size - 1)
        end = min(end, size - 1)
        self.send_response(206)
        self.send_header('Content-Range', 'bytes %d-%d/%d' % (start, end, size))
        self.send_header('Content-Length', str(end - start + 1))
        self.end_headers()
        with open(path, 'rb') as f:
            f.seek(start)
            self.wfile.write(f.read(end - start + 1))

handler = functools.partial(H, directory=sys.argv[1])
http.server.ThreadingHTTPServer(('127.0.0.1', int(sys.argv[2])), handler).serve_forever()
