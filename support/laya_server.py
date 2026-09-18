"""Laya behind jev's JSON contract, for S1::Providers::Laya.

    pip install laya
    python support/laya_server.py            # POST http://127.0.0.1:8765/v1/systemone

  in:  {"state": ..., "model": "laya" | "multilingual" | "typed-decisions", "questions": {id: {type, instructions, criteria}}}
  out: {"model": "...", "usage": {"input_tokens": 0, "output_tokens": 0}, "answers": {id: {...}}}

Answers are passed through as Laya returns them (choice / probabilities / confidence,
score / probabilities, noul); a score's legend is filled from the question's levels.
"""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

import laya  # noqa: F401  (import error here means: pip install laya)
from laya import Router

router = Router(preload=True)


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):  # noqa: N802
        if self.path != "/v1/systemone":
            return self._send(404, {"detail": "not found"})
        try:
            req = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
            model = req.get("model") or "laya"
            answers = router.predict(req["state"], req["questions"], model=model)
            for qid, q in req["questions"].items():
                if q.get("type") == "score" and "legend" not in answers[qid]:
                    answers[qid]["legend"] = {str(i): lvl for i, lvl in enumerate(q["criteria"])}
            self._send(200, {"model": model, "usage": {"input_tokens": 0, "output_tokens": 0}, "answers": answers})
        except (KeyError, ValueError) as exc:
            self._send(422, {"detail": f"{type(exc).__name__}: {exc}"})
        except Exception as exc:  # noqa: BLE001
            self._send(500, {"detail": f"{type(exc).__name__}: {exc}"})

    def _send(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):  # quiet
        pass


if __name__ == "__main__":
    port = int(os.environ.get("LAYA_PORT", sys.argv[1] if len(sys.argv) > 1 else 8765))
    print(f"laya: serving jev-shaped /v1/systemone on 127.0.0.1:{port}", flush=True)
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()
