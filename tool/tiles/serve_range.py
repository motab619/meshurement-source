#!/usr/bin/env python3
# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

"""Local HTTP server with Range support (python -m http.server has none),
behaving like CloudFront for PMTiles: 206 + Content-Range + Accept-Ranges.

  python3 tool/tiles/serve_range.py [DIR] [--port 8765]

Then run the app with e.g.
  --dart-define=TILES_TERRAIN_URL=http://localhost:8765/coachella-terrain.pmtiles
(The iOS simulator reaches the Mac's localhost; a phone needs the Mac's IP.)
"""

import argparse
import functools
import http.server
import os
import re


class RangeHandler(http.server.SimpleHTTPRequestHandler):
    def send_head(self):
        path = self.translate_path(self.path)
        if not os.path.isfile(path):
            return super().send_head()
        size = os.path.getsize(path)
        m = re.match(r"bytes=(\d+)-(\d*)$", self.headers.get("Range", ""))
        f = open(path, "rb")
        if not m:
            self.send_response(200)
            self.send_header("Content-Length", str(size))
            start, length = 0, size
        else:
            start = int(m.group(1))
            end = min(int(m.group(2)) if m.group(2) else size - 1, size - 1)
            if start >= size:
                f.close()
                self.send_error(416)
                return None
            length = end - start + 1
            self.send_response(206)
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
            self.send_header("Content-Length", str(length))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        f.seek(start)
        self._remaining = length
        return f

    def copyfile(self, source, outputfile):
        left = getattr(self, "_remaining", None)
        while left is None or left > 0:
            chunk = source.read(65536 if left is None else min(65536, left))
            if not chunk:
                break
            outputfile.write(chunk)
            if left is not None:
                left -= len(chunk)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir", nargs="?", default=os.path.expanduser("~/mesh-tiles/out"))
    ap.add_argument("--port", type=int, default=8765)
    a = ap.parse_args()
    handler = functools.partial(RangeHandler, directory=a.dir)
    print(f"serving {a.dir} on http://localhost:{a.port}/ (Ctrl-C to stop)")
    http.server.ThreadingHTTPServer(("127.0.0.1", a.port), handler).serve_forever()


if __name__ == "__main__":
    main()
