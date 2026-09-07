from __future__ import annotations

import importlib.util
import sys
import threading
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]


def load(name: str, rel: str):
    spec = importlib.util.spec_from_file_location(name, REPO_ROOT / rel)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


STORE = load("scene_job_store", "backend/scene_job_store.py")
POLICY = load("scene_provider_policy", "backend/scene_provider_policy.py")


class FakeClock:
    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now


class SceneJobStoreTests(unittest.TestCase):
    def test_same_key_same_hash_replays_same_job(self):
        store = STORE.SceneJobStore()
        first = store.create_or_replay("inst1", "k1", "a" * 64)
        second = store.create_or_replay("inst1", "k1", "a" * 64)
        self.assertFalse(first.replayed)
        self.assertTrue(second.replayed)
        self.assertEqual(first.job.job_id, second.job.job_id)

    def test_same_key_different_hash_conflicts(self):
        store = STORE.SceneJobStore()
        store.create_or_replay("inst1", "k1", "a" * 64)
        with self.assertRaises(STORE.IdempotencyConflict):
            store.create_or_replay("inst1", "k1", "b" * 64)

    def test_keys_are_scoped_per_installation(self):
        store = STORE.SceneJobStore()
        a = store.create_or_replay("inst1", "k1", "a" * 64)
        b = store.create_or_replay("inst2", "k1", "a" * 64)
        self.assertNotEqual(a.job.job_id, b.job.job_id)

    def test_provider_runs_at_most_once(self):
        store = STORE.SceneJobStore()
        created = store.create_or_replay("inst1", "k1", "a" * 64)
        calls: list[str] = []
        first = store.accept(created.job.job_id, lambda job: calls.append("p") or {"ok": True})
        second = store.accept(created.job.job_id, lambda job: calls.append("p2") or {"ok": True})
        self.assertEqual(len(calls), 1)
        self.assertEqual(first, second)

    def test_legal_transition_chain(self):
        store = STORE.SceneJobStore()
        created = store.create_or_replay("inst1", "k1", "a" * 64)
        store.accept(created.job.job_id, lambda j: {"draft": True})
        job, _ = store.poll(created.job.job_id, 0)
        self.assertEqual(job.status, "running")
        job = store.transition(job.job_id, job.version, "awaiting_clarification")
        self.assertEqual(job.status, "awaiting_clarification")
        job = store.transition(job.job_id, job.version, "running")
        job = store.transition(job.job_id, job.version, "succeeded", {"done": True})
        self.assertEqual(job.status, "succeeded")
        with self.assertRaises(STORE.IllegalTransition):
            store.transition(job.job_id, job.version, "running")

    def test_terminal_states_are_immutable_except_delete(self):
        store = STORE.SceneJobStore()
        for terminal in ("cancelled", "failed", "expired"):
            created = store.create_or_replay("inst1", f"k-{terminal}", "a" * 64)
            if terminal == "cancelled":
                job = store.transition(created.job.job_id, 1, "cancelled")
            elif terminal == "failed":
                store.accept(created.job.job_id, lambda j: None)
                job, _ = store.poll(created.job.job_id, 0)
                job = store.transition(job.job_id, job.version, "failed")
            else:
                job = store.transition(created.job.job_id, 1, "expired")
            with self.assertRaises(STORE.IllegalTransition):
                store.transition(job.job_id, job.version, "running")
            store.delete(job.job_id)
            with self.assertRaises(STORE.UnknownJob):
                store.poll(job.job_id, 0)

    def test_stale_version_conflicts(self):
        store = STORE.SceneJobStore()
        created = store.create_or_replay("inst1", "k1", "a" * 64)
        with self.assertRaises(STORE.VersionConflict):
            store.transition(created.job.job_id, 999, "cancelled")

    def test_concurrent_accepts_run_provider_once(self):
        store = STORE.SceneJobStore()
        created = store.create_or_replay("inst1", "k1", "a" * 64)
        calls: list[str] = []
        barrier = threading.Barrier(8)

        def worker():
            barrier.wait()
            store.accept(created.job.job_id, lambda j: calls.append("p") or {"ok": True})

        threads = [threading.Thread(target=worker) for _ in range(8)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        self.assertEqual(len(calls), 1)

    def test_concurrent_create_replays_one_job(self):
        store = STORE.SceneJobStore()
        barrier = threading.Barrier(8)
        results: list[str] = []

        def worker():
            barrier.wait()
            r = store.create_or_replay("inst1", "k1", "a" * 64)
            results.append(r.job.job_id)

        threads = [threading.Thread(target=worker) for _ in range(8)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        self.assertEqual(len(set(results)), 1)

    def test_overdue_jobs_expire(self):
        clock = FakeClock()
        store = STORE.SceneJobStore(clock=clock)
        created = store.create_or_replay("inst1", "k1", "a" * 64, deadline_s=60.0)
        clock.now += 61.0
        expired = store.expire_overdue()
        self.assertEqual(expired, [created.job.job_id])
        job, _ = store.poll(created.job.job_id, 0)
        self.assertEqual(job.status, "expired")

    def test_poll_reports_version_change(self):
        store = STORE.SceneJobStore()
        created = store.create_or_replay("inst1", "k1", "a" * 64)
        seed_version = created.job.version
        _, changed = store.poll(created.job.job_id, seed_version)
        self.assertFalse(changed)
        job = store.transition(created.job.job_id, seed_version, "cancelled")
        _, changed = store.poll(job.job_id, seed_version)
        self.assertTrue(changed)


class SceneProviderPolicyTests(unittest.TestCase):
    def test_success_first_try(self):
        breaker = POLICY.CircuitBreaker()
        outcome = POLICY.run_with_policy(lambda: {"ok": True}, breaker)
        self.assertTrue(outcome.ok)
        self.assertEqual(outcome.attempts, 1)

    def test_retryable_transport_retried_once(self):
        breaker = POLICY.CircuitBreaker()
        calls: list[int] = []

        def flaky():
            calls.append(1)
            if len(calls) == 1:
                raise POLICY.ProviderTransportError("429")
            return {"ok": True}

        outcome = POLICY.run_with_policy(flaky, breaker)
        self.assertTrue(outcome.ok)
        self.assertEqual(outcome.attempts, 2)

    def test_persistent_transport_reports_retryable(self):
        breaker = POLICY.CircuitBreaker()

        def down():
            raise POLICY.ProviderTransportError("5xx")

        outcome = POLICY.run_with_policy(down, breaker)
        self.assertFalse(outcome.ok)
        self.assertEqual(outcome.retryability, POLICY.RETRYABLE)
        self.assertEqual(outcome.attempts, 2)

    def test_invalid_output_never_retried(self):
        breaker = POLICY.CircuitBreaker()
        calls: list[int] = []

        def bad():
            calls.append(1)
            raise POLICY.ProviderInvalidOutput("malformed")

        outcome = POLICY.run_with_policy(bad, breaker)
        self.assertFalse(outcome.ok)
        self.assertEqual(outcome.retryability, POLICY.TERMINAL)
        self.assertEqual(calls, [1])

    def test_circuit_opens_after_three_failures(self):
        clock = FakeClock()
        breaker = POLICY.CircuitBreaker(clock=clock)

        def down():
            raise POLICY.ProviderTransportError("5xx")

        for _ in range(3):
            POLICY.run_with_policy(down, breaker, clock=clock)
        blocked = POLICY.run_with_policy(lambda: {"ok": True}, breaker, clock=clock)
        self.assertEqual(blocked.attempts, 0)
        clock.now += 31.0
        half_open = POLICY.run_with_policy(lambda: {"ok": True}, breaker, clock=clock)
        self.assertTrue(half_open.ok)

    def test_policy_constants_match_frozen_limits(self):
        self.assertLessEqual(POLICY.PROVIDER_TIMEOUT_S, 45.0)
        self.assertEqual(POLICY.MAX_RETRIES, 1)
        self.assertLessEqual(POLICY.JOB_DEADLINE_S, 60.0)


if __name__ == "__main__":
    unittest.main()
