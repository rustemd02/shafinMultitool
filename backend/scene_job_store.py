#!/usr/bin/env python3
"""Scene job store reference semantics (M12-007 idempotency, M12-008 lifecycle).

Fail-closed reference implementation of the backend job gate the deployed
service must enforce identically. Thread-safe under one lock; transitions
are atomic and versioned; terminal states are immutable except deletion;
provider work runs at most once per accepted job.
"""

from __future__ import annotations

import threading
import uuid
from dataclasses import dataclass, field
from typing import Any, Callable, Optional


TERMINAL = ("succeeded", "failed", "cancelled", "expired")
NON_TERMINAL = ("queued", "running", "awaiting_clarification")
ALLOWED_TRANSITIONS: dict[str, frozenset[str]] = {
    "queued": frozenset({"running", "cancelled", "expired"}),
    "running": frozenset({"awaiting_clarification", "succeeded", "failed", "cancelled", "expired"}),
    "awaiting_clarification": frozenset({"running", "cancelled", "expired"}),
    "succeeded": frozenset(),
    "failed": frozenset(),
    "cancelled": frozenset(),
    "expired": frozenset(),
}


class IdempotencyConflict(Exception):
    """Same installation + key submitted with a different request hash."""


class VersionConflict(Exception):
    """Transition attempted against a stale job version."""


class IllegalTransition(Exception):
    """Transition not in the frozen state machine."""


class UnknownJob(Exception):
    """No job for this id."""


@dataclass
class SceneJob:
    job_id: str
    installation_id: str
    idempotency_key: str
    request_hash: str
    status: str = "queued"
    version: int = 1
    payload: Any = None
    provider_calls: int = 0
    polls: int = 0
    deadline_s: float = 60.0
    created_at: float = 0.0


@dataclass
class CreateResult:
    job: SceneJob
    replayed: bool


class SceneJobStore:
    """Single-service job owner. All mutations hold one lock."""

    def __init__(self, clock: Optional[Callable[[], float]] = None) -> None:
        self._lock = threading.Lock()
        self._jobs: dict[str, SceneJob] = {}
        self._by_key: dict[tuple[str, str], str] = {}
        self._clock = clock or (lambda: 0.0)

    def create_or_replay(
        self,
        installation_id: str,
        idempotency_key: str,
        request_hash: str,
        payload: Any = None,
        deadline_s: float = 60.0,
    ) -> CreateResult:
        """Same installation+key+hash replays the same job; same key with a
        different hash raises IdempotencyConflict. Provider work is never
        started here — accept() runs it exactly once."""
        with self._lock:
            slot = (installation_id, idempotency_key)
            existing_id = self._by_key.get(slot)
            if existing_id is not None:
                job = self._jobs[existing_id]
                if job.request_hash != request_hash:
                    raise IdempotencyConflict(
                        f"key {idempotency_key} already used for a different request"
                    )
                return CreateResult(job=job, replayed=True)
            job = SceneJob(
                job_id=f"job_{uuid.uuid4().hex[:12]}",
                installation_id=installation_id,
                idempotency_key=idempotency_key,
                request_hash=request_hash,
                payload=payload,
                deadline_s=deadline_s,
                created_at=self._clock(),
            )
            self._jobs[job.job_id] = job
            self._by_key[slot] = job.job_id
            return CreateResult(job=job, replayed=False)

    def accept(self, job_id: str, provider: Callable[[SceneJob], Any]) -> Any:
        """Run provider work at most once per accepted job. Concurrent
        accepts serialize on the lock; the second sees provider_calls > 0
        and replays the stored result without calling the provider."""
        with self._lock:
            job = self._require(job_id)
            if job.payload is not None and job.provider_calls > 0:
                return job.payload
            if job.status != "queued":
                raise IllegalTransition(f"accept requires queued, got {job.status}")
            job.status = "running"
            job.version += 1
            job.provider_calls += 1
            result = provider(job)
            job.payload = result
            return result

    def transition(
        self,
        job_id: str,
        expected_version: int,
        to_status: str,
        payload: Any = None,
    ) -> SceneJob:
        """Atomic versioned transition. Terminal states reject every
        transition; only delete() removes them."""
        with self._lock:
            job = self._require(job_id)
            if job.version != expected_version:
                raise VersionConflict(
                    f"job {job_id} at v{job.version}, expected v{expected_version}"
                )
            if to_status not in ALLOWED_TRANSITIONS[job.status]:
                raise IllegalTransition(f"{job.status} -> {to_status} forbidden")
            job.status = to_status
            job.version += 1
            if payload is not None:
                job.payload = payload
            return job

    def poll(self, job_id: str, last_seen_version: int) -> tuple[SceneJob, bool]:
        """Versioned read for bounded client polling: unchanged version
        means the client can back off without re-rendering."""
        with self._lock:
            job = self._require(job_id)
            job.polls += 1
            return job, (job.version != last_seen_version)

    def delete(self, job_id: str) -> None:
        with self._lock:
            job = self._require(job_id)
            del self._jobs[job_id]
            self._by_key.pop((job.installation_id, job.idempotency_key), None)

    def expire_overdue(self) -> list[str]:
        """Sweep non-terminal jobs past their deadline to expired."""
        now = self._clock()
        expired: list[str] = []
        with self._lock:
            for job in self._jobs.values():
                if job.status in NON_TERMINAL and now - job.created_at >= job.deadline_s:
                    job.status = "expired"
                    job.version += 1
                    expired.append(job.job_id)
        return expired

    def _require(self, job_id: str) -> SceneJob:
        job = self._jobs.get(job_id)
        if job is None:
            raise UnknownJob(job_id)
        return job
