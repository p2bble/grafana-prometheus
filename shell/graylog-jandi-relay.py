#!/usr/bin/env python3
"""
graylog-jandi-relay.py
Graylog HTTP Notification → Jandi Incoming Webhook 포맷 변환 릴레이
Listen: 127.0.0.1:9876  →  Forward: JANDI_WEBHOOK_URL
"""
import json
import os
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

JANDI_URL = os.environ.get(
    "JANDI_URL",
    "https://wh.jandi.com/connect-api/webhook/18381544/015336224f0bb780cb9fed693501d493"
)

PRIORITY_COLOR = {1: "#AAAAAA", 2: "#FAC11B", 3: "#FF4444"}
PRIORITY_LABEL = {1: "낮음", 2: "보통", 3: "높음"}


def build_jandi_payload(graylog_payload: dict) -> dict:
    title = graylog_payload.get("event_definition_title", "Graylog Alert")
    desc = graylog_payload.get("event_definition_description", "")
    event = graylog_payload.get("event", {})
    priority = event.get("priority", 2)
    timestamp = event.get("timestamp", "")[:19].replace("T", " ")
    fields = event.get("fields", {})

    count_val = fields.get("aggregation_value_count", "")
    count_str = f"  집계 건수: {count_val}" if count_val else ""

    body = f"[Graylog 알럿] {title}"
    connect_info = []
    if desc:
        connect_info.append({"title": "설명", "description": desc})
    if count_str:
        connect_info.append({"title": "집계", "description": count_str.strip()})
    connect_info.append({"title": "발생 시각", "description": timestamp + " UTC"})
    connect_info.append({"title": "우선순위", "description": PRIORITY_LABEL.get(priority, str(priority))})

    return {
        "body": body,
        "connectColor": PRIORITY_COLOR.get(priority, "#FAC11B"),
        "connectInfo": connect_info,
    }


class RelayHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"[relay] {self.address_string()} - {fmt % args}")

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length)
        try:
            graylog_payload = json.loads(raw)
        except json.JSONDecodeError:
            self.send_response(400)
            self.end_headers()
            return

        jandi_payload = build_jandi_payload(graylog_payload)
        data = json.dumps(jandi_payload).encode()

        req = urllib.request.Request(
            JANDI_URL,
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                status = resp.status
        except Exception as e:
            print(f"[relay] Jandi 전송 실패: {e}")
            status = 500

        self.send_response(200 if status < 300 else 502)
        self.end_headers()

    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"graylog-jandi-relay OK")


if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", 9876), RelayHandler)
    print(f"[relay] Listening on 127.0.0.1:9876 → {JANDI_URL}")
    server.serve_forever()
