# M11-004 / M11-005 — Russian and English editorial

Status: **closed on the current store**.

Audit of all 441 copy keys: terminology consistent (Camera Coach,
REDUCE MOTION, LIVE/STANDBY as proper product terms in both locales);
no mixed-language raw errors (the 25 latin-in-RU hits are product names
and terms; the only cyrillic-in-EN hit is a fixture key excluded from
Release claims); strings fit tested layouts (reduce-motion/dynamic-type
lanes green).

One fix: Decision Trace metadata labels (`coarse`, `overlay`, `id`,
`region`) were raw technical tokens in both locales — now proper
localized captions (EN "coarse action"/"overlay hint"/"ID"/"region",
RU equivalents).

Verification: `DecisionTracePresentationTests` 5/5 on permitted iPhone
17e (`/private/tmp/m11-004-005-tests.xcresult`).
