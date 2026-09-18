"""Sidecar for S1::Providers::Cua: one JSON line in, one JSON line out.

  in:  {"context": "...", "options": ["...", "..."]}
  out: {"probabilities": [0.1, 0.9]}          or {"error": "..."}

Loads a cua-s1 checkpoint (safetensors + json; see github.com/trycua/cua libs/cua-s1)
and scores each request in one forward pass. First line out is the model config.
"""
import json
import sys

import torch

from cua_s1.model import ChoiceExample, load_checkpoint, select_device


def main(path: str, device: str = "auto") -> None:
    model, collator, config = load_checkpoint(path, select_device(device))
    print(json.dumps({"config": config}), flush=True)
    for line in sys.stdin:
        try:
            req = json.loads(line)
            example = ChoiceExample(context=req["context"], options=tuple(req["options"]), label=0)
            with torch.no_grad():
                logits = model(collator([example]))
            probs = torch.softmax(logits[0], dim=-1).tolist()
            print(json.dumps({"probabilities": probs}), flush=True)
        except Exception as exc:  # noqa: BLE001 — the Ruby side maps it
            print(json.dumps({"error": f"{type(exc).__name__}: {exc}"}), flush=True)


if __name__ == "__main__":
    main(*sys.argv[1:])
