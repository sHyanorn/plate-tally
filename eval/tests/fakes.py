"""Fake SDK pieces for tests. Nothing here touches the network."""

import struct
import threading
import urllib.error
import zlib
from collections.abc import Callable

import anthropic
import httpx2
from anthropic.types import Message

REQUEST = httpx2.Request("POST", "https://api.example.invalid/v1/messages")


def _chunk(kind: bytes, body: bytes) -> bytes:
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))


def png(width: int = 640, height: int = 480, tag: str = "") -> bytes:
    """A small valid PNG whose IHDR claims the given size; tag makes the bytes unique."""
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", header)
        + _chunk(b"IDAT", zlib.compress(tag.encode() + b"\x00" * 64))
        + _chunk(b"IEND", b"")
    )


def message(
    text: str = '{"total_kcal": 100}',
    *,
    stop_reason: str = "end_turn",
    input_tokens: int = 500,
    output_tokens: int = 20,
    model: str = "claude-haiku-5-5",
) -> Message:
    return Message(
        id="msg_test",
        content=[{"type": "text", "text": text}] if text else [],
        model=model,
        role="assistant",
        stop_reason=stop_reason,
        stop_sequence=None,
        type="message",
        usage={"input_tokens": input_tokens, "output_tokens": output_tokens},
    )


def status_error(
    cls: type[anthropic.APIStatusError],
    status: int,
    headers: dict | None = None,
    *,
    message: str | None = None,
    body: object | None = None,
) -> anthropic.APIStatusError:
    response = httpx2.Response(status, request=REQUEST, headers=headers or {})
    return cls(message or f"status {status}", response=response, body=body)


def http_error(code: int, headers: dict | None = None) -> urllib.error.HTTPError:
    """What urllib raises for a bucket answer with this status."""
    url = "https://bucket.invalid/image.png"
    return urllib.error.HTTPError(url, code, f"status {code}", headers or {}, None)


def connection_error() -> anthropic.APIConnectionError:
    return anthropic.APIConnectionError(request=REQUEST)


def reply_for(kwargs: dict) -> Message:
    """A valid answer to either prompt, chosen from the prompt text."""
    prompt = kwargs["messages"][0]["content"][1]["text"]
    if "total_kcal" in prompt:
        return message('{"total_kcal": 100}', model=kwargs["model"])
    items = '{"items": [{"name": "rice", "grams": 100, "kcal": 130}]}'
    return message(items, model=kwargs["model"])


class FakeClient:
    """Stands in for anthropic.Anthropic. handler gets the request kwargs and returns a Message
    or raises."""

    def __init__(self, handler: Callable[[dict], Message] = reply_for) -> None:
        self.handler = handler
        self.calls: list[dict] = []
        self.lock = threading.Lock()
        self.messages = self

    def create(self, **kwargs: object) -> Message:
        with self.lock:
            self.calls.append(kwargs)
        return self.handler(kwargs)
