"""Convert Plasma/Qt notification HTML into plain text safe for Pango daemons.

Mako advertises ``body-markup`` but only parses Pango. DrKonqi/KNotifications
emit Qt HTML (e.g. ``<html><tt>/usr/bin/zsh</tt>…</html>``). When Pango rejects
that markup, mako escapes the whole body and the toast shows literal
``&lt;html&gt;&lt;tt&gt;…``.

Strip Plasma/HTML wrappers to plain text; callers that feed a Pango daemon
should escape the result (or leave markup disabled for that app).
"""

from __future__ import annotations

import html
import re

# Hint stamped on rewritten Notify calls so we do not rewrite our own traffic.
HINT_SANITIZED = "x-waybar-notify-sanitized"

_TAG_RE = re.compile(r"<[^>]+>", re.DOTALL)
_BR_RE = re.compile(r"(?is)<br\s*/?>")
_BLOCK_CLOSE_RE = re.compile(r"(?is)</(?:p|div|tr|li|h[1-6])>")

# Tags that mean "this is Plasma/Qt HTML, not freedesktop/Pango markup".
_PLASMA_HINT_RE = re.compile(
    r"(?is)</?(?:html|head|body|command|tt|font|center|table|tr|td|div|span)\b"
)

# Freedesktop body-markup allowlist-ish openers; bare ``<`` still needs care.
_FD_MARKUP_RE = re.compile(r"(?is)</?(?:b|i|u|a|img)\b")


def body_looks_like_plasma_html(body: str) -> bool:
    """True when the body uses Plasma/Qt HTML wrappers DrKonqi sends."""
    if not body:
        return False
    return bool(_PLASMA_HINT_RE.search(body))


def body_needs_sanitize(body: str) -> bool:
    """True when a Pango notification daemon should rewrite this body."""
    if not body:
        return False
    if body_looks_like_plasma_html(body):
        return True
    # Unescaped ``<`` that is not an fd-allowed tag usually breaks Pango.
    if "<" not in body:
        return False
    if _FD_MARKUP_RE.search(body) and not _PLASMA_HINT_RE.search(body):
        # Likely intentional fd/Pango markup — leave alone.
        return False
    return "<" in body


def plasma_html_to_plain(body: str) -> str:
    """Strip HTML/Plasma tags to plain text (entities unescaped)."""
    if not body:
        return ""
    text = _BR_RE.sub("\n", body)
    text = _BLOCK_CLOSE_RE.sub("\n", text)
    text = _TAG_RE.sub("", text)
    text = html.unescape(text)
    # Collapse whitespace but keep intentional newlines.
    lines = [" ".join(line.split()) for line in text.splitlines()]
    return "\n".join(line for line in lines if line).strip()


def sanitize_notification_body(body: str) -> str | None:
    """Return rewritten plain body, or None when no change is needed."""
    if not body_needs_sanitize(body):
        return None
    plain = plasma_html_to_plain(body)
    if plain == body:
        return None
    return plain
