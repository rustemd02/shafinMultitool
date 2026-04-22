#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

try:
    from .datasets import (
        chunk_anchor_builder,
        chunk_patch_builder,
        entity_registry_builder,
        macro_scene_builder,
        read_jsonl,
        split_rows_by_document,
        write_jsonl,
    )
except ImportError:  # pragma: no cover
    from datasets import (
        chunk_anchor_builder,
        chunk_patch_builder,
        entity_registry_builder,
        macro_scene_builder,
        read_jsonl,
        split_rows_by_document,
        write_jsonl,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Build V1 chunk-native train artifacts from exported document states")
    parser.add_argument("--documents-jsonl", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--val-fraction", type=float, default=0.1)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    document_rows = read_jsonl(args.documents_jsonl)
    output_dir = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)

    macro_rows = macro_scene_builder(document_rows)
    anchor_rows = chunk_anchor_builder(document_rows)
    registry_rows = entity_registry_builder(document_rows)
    patch_rows = chunk_patch_builder(document_rows)
    train_patch_rows, val_patch_rows = split_rows_by_document(
        patch_rows,
        val_fraction=args.val_fraction,
        seed=args.seed,
    )

    write_jsonl(macro_rows, output_dir / "macro_scenes.jsonl")
    write_jsonl(anchor_rows, output_dir / "chunk_anchors.jsonl")
    write_jsonl(registry_rows, output_dir / "entity_registries.jsonl")
    write_jsonl(train_patch_rows, output_dir / "v1_chunk_patch_train.jsonl")
    write_jsonl(val_patch_rows, output_dir / "v1_chunk_patch_val.jsonl")


if __name__ == "__main__":
    main()

