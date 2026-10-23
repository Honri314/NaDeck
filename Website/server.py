# TrueNAS 관리 프로그램 다운로드 서버 (표준 라이브러리만 사용)
# 실행: python3 Website/server.py [포트]
# 기본 포트: 8181  (pm2로 관리하는 것을 전제)
#
# pm2 실행 예:
#   pm2 start Website/ecosystem.config.js
#   pm2 save
#
# 외부 접속(공유 프록시/터널) 안내는 Website/README.md 참고.

import http.server
import os
import socketserver
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8181

RELEASES = os.path.join(ROOT, "releases")

# 같은 터널(공유 프록시)에서 다른 사이트들(systems/hivedesk/maccleaner)처럼
# 경로를 추가해 접속할 수 있게 지원: 예) https://<터널주소>/nadeck/
# 여기에 없는 경로로 노출하려면 PATH_PREFIXES에 추가한다.
PATH_PREFIXES = ("nadeck", "downloads", "deck")


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def _split_prefix(self):
        """요청 경로를 (원본, 접두사 or None, 접두사 제거한 경로)로 분해"""
        clean = self.path.split("?", 1)[0].split("#", 1)[0]
        parts = [p for p in clean.split("/") if p]
        prefix = parts[0].lower() if parts and parts[0].lower() in PATH_PREFIXES else None
        rest = "/" + "/".join(parts[1:]) if len(parts) > 1 else "/"
        return prefix, rest

    def do_GET(self):
        prefix, rest = self._split_prefix()
        if prefix:
            if rest == "/" and not self.path.endswith("/"):
                # 상대 경로(releases/...)가 접두사 아래에서 동작하게 슬래시로 리다이렉트
                self.send_response(301)
                self.send_header("Location", "/%s/" % prefix)
                self.end_headers()
                return
            self.path = rest
        super().do_GET()

    def end_headers(self):
        # 다운로드 zip은 캐시되어도 되지만, 안전하게 no-store 유지
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):  # pm2 로그에 남도록
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


class ThreadingServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


def main():
    os.makedirs(RELEASES, exist_ok=True)
    server = ThreadingServer(("0.0.0.0", PORT), Handler)
    print(f"다운로드 사이트 실행 중: http://0.0.0.0:{PORT}  (root={ROOT})", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
