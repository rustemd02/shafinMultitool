#!/usr/bin/env python3
"""Provider timeout/retry/circuit-breaker policy (M12-009).

Reference policy the deployed service enforces: provider call timeout
<=45 s, at most one retry for retryable transport failures inside a
60 s job deadline, no retry on invalid output/content, circuit opens
after 3 consecutive provider failures and half-opens after 30 s.
Client-visible retryability is explicit: retryable / terminal /
clarify.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Optional


PROVIDER_TIMEOUT_S = 45.0
MAX_RETRIES = 1
JOB_DEADLINE_S = 60.0
CIRCUIT_FAILURE_THRESHOLD = 3
CIRCUIT_HALF_OPEN_S = 30.0

RETRYABLE = "retryable"
TERMINAL = "terminal"
CLARIFY = "clarify"


class ProviderTimeout(Exception):
    pass


class ProviderTransportError(Exception):
    pass


class ProviderInvalidOutput(Exception):
    """Malformed or content-rejected output: never retried."""


@dataclass(frozen=True)
class ProviderOutcome:
    ok: bool
    retryability: str
    attempts: int
    result: object = None


class CircuitBreaker:
    def __init__(self, clock: Optional[Callable[[], float]] = None) -> None:
        self._clock = clock or (lambda: 0.0)
        self.consecutive_failures = 0
        self.opened_at: Optional[float] = None

    def allow(self) -> bool:
        if self.opened_at is None:
            return True
        return self._clock() - self.opened_at >= CIRCUIT_HALF_OPEN_S

    def record_success(self) -> None:
        self.consecutive_failures = 0
        self.opened_at = None

    def record_failure(self) -> None:
        self.consecutive_failures += 1
        if self.consecutive_failures >= CIRCUIT_FAILURE_THRESHOLD:
            self.opened_at = self._clock()


def run_with_policy(
    provider: Callable[[], object],
    breaker: CircuitBreaker,
    clock: Optional[Callable[[], float]] = None,
    timeout_s: float = PROVIDER_TIMEOUT_S,
    deadline_s: float = JOB_DEADLINE_S,
) -> ProviderOutcome:
    """Run one provider job under the frozen policy. The provider callable
    raises ProviderTimeout / ProviderTransportError / ProviderInvalidOutput
    to model the fault; elapsed time is charged per attempt."""
    now = clock or (lambda: 0.0)
    if not breaker.allow():
        return ProviderOutcome(False, TERMINAL, 0, "circuit_open")
    attempts = 0
    elapsed = 0.0
    while True:
        attempts += 1
        try:
            result = provider()
            breaker.record_success()
            return ProviderOutcome(True, TERMINAL, attempts, result)
        except ProviderInvalidOutput as exc:
            breaker.record_failure()
            return ProviderOutcome(False, TERMINAL, attempts, str(exc))
        except (ProviderTimeout, ProviderTransportError) as exc:
            breaker.record_failure()
            elapsed += timeout_s
            if attempts > MAX_RETRIES or elapsed >= deadline_s:
                return ProviderOutcome(False, RETRYABLE, attempts, str(exc))
            continue
