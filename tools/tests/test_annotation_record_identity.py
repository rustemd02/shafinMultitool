"""Record-identity collisions: isolated manifests/journals, no provider or media inference."""
from copy import deepcopy
import json
from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "camera_annotation"))
import build_annotation_queue as builder
import language_intake as intake
import language_review as review


def write_rows(path, rows):
    path.write_text("".join(json.dumps(row) + "\n" for row in rows))
    return path


def record(group="0_item", *, record_id="source__pair_0000__A", media_sha="a" * 64):
    return dict(record_id=record_id, image_path=f"/{group}/pair_0000/A.png",
                image_sha256=media_sha, pair_id="pair_0000", pair_group=group,
                pair_role="before", research_only=True, human_gold=False)


def invoke_builder(monkeypatch, output, *manifests, initial=()):
    monkeypatch.setattr(builder, "build_queue", lambda **_: list(initial))
    argv = ["--output", str(output), "--per-source"]
    for path in manifests:
        argv.extend(["--extra-manifest", str(path)])
    return builder.main(argv)


@pytest.mark.parametrize("preserve_existing", [False, True])
def test_conflicting_raw_pair_id_rejects_before_any_output_write(tmp_path, monkeypatch, preserve_existing):
    # SceneTrans groups reuse the same pair ID for different RGB content.
    manifest = write_rows(tmp_path / "source.jsonl", [record(), record("1_item", media_sha="b" * 64)])
    original_manifest = manifest.read_bytes()
    output = tmp_path / "queue.jsonl"
    if preserve_existing:
        output.write_bytes(b"existing immutable queue\n")
    with pytest.raises(ValueError, match="Conflicting record ID"):
        invoke_builder(monkeypatch, output, manifest)
    assert manifest.read_bytes() == original_manifest
    assert output.read_bytes() == b"existing immutable queue\n" if preserve_existing else not output.exists()


def test_same_pixels_do_not_merge_different_pair_membership(tmp_path, monkeypatch):
    first = record()
    collision = dict(first, pair_group="2_items")
    manifest = write_rows(tmp_path / "source.jsonl", [first, collision])
    output = tmp_path / "queue.jsonl"
    with pytest.raises(ValueError, match="Conflicting record ID"):
        invoke_builder(monkeypatch, output, manifest)
    assert not output.exists()


def test_content_hash_collision_under_stable_id_rejects(tmp_path, monkeypatch):
    # Same raw record_id and same pair/source identity, only the frame content
    # (image_sha256) changed: content is part of the stable identity, so a
    # silent rebind of the ID onto new pixels must stay rejected.
    manifest = write_rows(tmp_path / "source.jsonl", [record(), record(media_sha="b" * 64)])
    output = tmp_path / "queue.jsonl"
    with pytest.raises(ValueError, match="Conflicting record ID"):
        invoke_builder(monkeypatch, output, manifest)
    assert not output.exists()


def test_intake_queue_collision_rejects_before_any_review_or_output(tmp_path):
    # The language intake exporter merges the queue by raw record_id before any
    # journal interpretation; a colliding ID must fail closed there too, leaving
    # both source snapshots and the (nonexistent) output untouched.
    folder = tmp_path / "journal"
    folder.mkdir()
    write_rows(folder / "queue.jsonl", [photo(tmp_path), photo(tmp_path, digest="b" * 64)])
    journal = folder / "opinions.jsonl"
    journal.write_bytes(b'{"historical":"untouched"}\n')
    out = tmp_path / "intake-out"
    with pytest.raises(ValueError, match="Duplicate queue record IDs"):
        intake.export_language_review(folder, out)
    assert not out.exists()
    assert journal.read_bytes() == b'{"historical":"untouched"}\n'


def test_exact_repeat_remains_idempotent_and_distinct_ids_keep_identical_pixels(tmp_path, monkeypatch):
    first = record(record_id="source__0_item__pair_0000__A")
    second = dict(first, record_id="source__0_item__pair_0000__B", pair_role="after")
    source = write_rows(tmp_path / "source.jsonl", [first, second])
    repeat = write_rows(tmp_path / "repeat.jsonl", [deepcopy(first), deepcopy(second)])
    output = tmp_path / "queue.jsonl"
    assert invoke_builder(monkeypatch, output, source, repeat) == 0
    assert [json.loads(line) for line in output.read_text().splitlines()] == [first, second]


def test_collision_inside_sampled_source_is_not_published(tmp_path, monkeypatch):
    output = tmp_path / "queue.jsonl"
    with pytest.raises(ValueError, match="Duplicate source record ID"):
        invoke_builder(monkeypatch, output, initial=[record(), record("1_item")])
    assert not output.exists()


def photo(tmp_path, *, record_id="same", digest="a" * 64):
    return dict(record_id=record_id, kind="photo", media_path=str(tmp_path / "image.png"),
                media_sha256=digest, title="Generated identity fixture", source={}, **review.FLAGS)


def test_reopened_queue_collision_rejects_before_media_or_journal_work(tmp_path):
    queue = write_rows(tmp_path / "queue.jsonl", [photo(tmp_path), photo(tmp_path, digest="b" * 64)])
    journal = tmp_path / "opinions.jsonl"
    journal.write_bytes(b'{"historical":"untouched"}\n')
    original = queue.read_bytes(), journal.read_bytes()
    # No temporal manifest exists: identity validation must happen first.
    with pytest.raises(ValueError, match="Duplicate record ID"):
        review.prepare_queue(queue, tmp_path / "unused.jsonl", tmp_path / "unused")
    assert (queue.read_bytes(), journal.read_bytes()) == original


def test_direct_review_collision_rejects_before_worker_or_journal_read(tmp_path, monkeypatch):
    def forbidden(*args, **kwargs):
        pytest.fail("Collision validation must precede worker, journal and provider access")
    monkeypatch.setattr(review.threading, "Thread", forbidden)
    monkeypatch.setattr(review, "rows", forbidden)
    monkeypatch.setattr(review, "command_api", forbidden)
    with pytest.raises(ValueError, match="Duplicate record ID"):
        review.Review(tmp_path, [photo(tmp_path), photo(tmp_path, digest="b" * 64)], "fixture-only", 0)
    assert not (tmp_path / "opinions.jsonl").exists()


def test_duplicate_frame_join_is_rejected_before_new_queue_write(tmp_path):
    pilot = write_rows(tmp_path / "pilot.jsonl", [record()])
    write_rows(tmp_path / "temporal.jsonl", [])
    write_rows(tmp_path / "manifest.jsonl", [record(), record("1_item")])
    queue = tmp_path / "queue.jsonl"
    with pytest.raises(ValueError, match="Duplicate record ID in frame manifest"):
        review.prepare_queue(queue, pilot, tmp_path)
    assert not queue.exists()


def test_unique_reopened_queue_preserves_order_and_identical_media(tmp_path):
    originals = [photo(tmp_path, record_id="after"), photo(tmp_path, record_id="before")]
    queue = write_rows(tmp_path / "queue.jsonl", originals)
    frozen = queue.read_bytes()
    write_rows(tmp_path / "manifest.jsonl", [])
    loaded = review.prepare_queue(queue, tmp_path / "unused.jsonl", tmp_path)
    assert loaded == originals
    assert queue.read_bytes() == frozen
