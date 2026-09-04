#!/usr/bin/env python3
"""
TravelView devsink — 开发期产物回收服务（零依赖）

手机上的 debug 版 App 把生成的 manifest.json / 压缩图 / 网页 POST 到这里，
本服务把它们写进 <project>/test-output/runs/<run-name>/。

用法:
    python3 server.py [--port 8787] [--out ../../test-output/runs]

App 侧约定:
    POST /upload
      Header  X-Run : 本次运行名（如 kyoto-2025-09），缺省用当前时间戳
      Header  X-Path: 相对路径（如 manifest.json、photos/001.webp）
      Body   : 文件原始字节
    GET  /ping   -> "pong"   （App 启动时探测 Mac 是否在线）

安全说明: 只监听局域网、只接受写入到 out 目录内的路径，
         拒绝任何 .. 越界路径。此服务仅供开发期使用，勿暴露到公网。
"""

import argparse
import datetime as dt
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MAX_BYTES = 64 * 1024 * 1024  # 单文件上限 64MB
SAFE_SEG = re.compile(r"^[A-Za-z0-9._\-]+$")


def sanitize(rel_path: str) -> str:
    """把 X-Path 规整成安全的相对路径，任何可疑成分直接拒绝。"""
    rel_path = rel_path.strip().replace("\\", "/").lstrip("/")
    if not rel_path:
        raise ValueError("empty path")
    parts = [p for p in rel_path.split("/") if p not in ("", ".")]
    if not parts or any(p == ".." or not SAFE_SEG.match(p) for p in parts):
        raise ValueError(f"unsafe path: {rel_path}")
    return os.path.join(*parts)


def default_run() -> str:
    return dt.datetime.now().strftime("%Y-%m-%d-%H%M%S")


class Handler(BaseHTTPRequestHandler):
    out_root = ""

    def _reply(self, code: int, body: str = ""):
        payload = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.path == "/ping":
            self._reply(200, "pong")
        else:
            self._reply(404, "not found")

    def do_POST(self):
        if self.path != "/upload":
            return self._reply(404, "not found")

        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            return self._reply(400, "bad Content-Length")
        if length <= 0:
            return self._reply(400, "empty body")
        if length > MAX_BYTES:
            return self._reply(413, f"too large (>{MAX_BYTES} bytes)")

        run = self.headers.get("X-Run", "").strip() or default_run()
        try:
            run = sanitize(run)
            if os.sep in run:
                raise ValueError("run must be a single segment")
            rel = sanitize(self.headers.get("X-Path", ""))
        except ValueError as e:
            return self._reply(400, str(e))

        dest = os.path.join(self.out_root, run, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)

        remaining, tmp = length, dest + ".part"
        try:
            with open(tmp, "wb") as f:
                while remaining > 0:
                    chunk = self.rfile.read(min(1 << 16, remaining))
                    if not chunk:
                        raise IOError("connection closed early")
                    f.write(chunk)
                    remaining -= len(chunk)
            os.replace(tmp, dest)
        except Exception as e:
            if os.path.exists(tmp):
                os.remove(tmp)
            return self._reply(500, f"write failed: {e}")

        shown = os.path.relpath(dest, self.out_root)
        print(f"  ✓ {shown}  ({length/1024:.1f} KB)", flush=True)
        self._reply(200, shown)

    def log_message(self, *args):
        pass  # 静音默认访问日志，只保留上面的 ✓ 行


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--out", default=os.path.join(here, "..", "..", "test-output", "runs"))
    args = ap.parse_args()

    out_root = os.path.abspath(args.out)
    os.makedirs(out_root, exist_ok=True)
    Handler.out_root = out_root

    print(f"TravelView devsink")
    print(f"  产物目录 : {out_root}")
    print(f"  监听     : http://{args.host}:{args.port}")
    print(f"  Android  : adb reverse tcp:{args.port} tcp:{args.port} → App 填 http://127.0.0.1:{args.port}")
    print(f"  iPhone   : App 填 http://$(ipconfig getifaddr en0):{args.port}（同一 Wi-Fi）")
    print(f"  Ctrl+C 退出\n")

    try:
        ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()
    except KeyboardInterrupt:
        print("\n已停止")
        sys.exit(0)


if __name__ == "__main__":
    main()
