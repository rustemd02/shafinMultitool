from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
import sys

DOCS_ROOT = Path(__file__).resolve().parents[2]
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from training import ExperimentRegistryRequest, register_experiment


class TestExperimentRegistry(unittest.TestCase):
    def test_register_experiment_writes_reproducible_note(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            config = tmp / "phase3.json"
            config.write_text('{"phase":"phase3"}\n', encoding="utf-8")
            artifact = tmp / "checkpoint_table.json"
            artifact.write_text('{"winner_checkpoint_id":"abc"}\n', encoding="utf-8")
            out = tmp / "registry"
            payload = register_experiment(
                ExperimentRegistryRequest(
                    experiment_id="exp-001",
                    phase="phase3",
                    config_path=config,
                    output_dir=out,
                    input_artifacts=[artifact],
                    notes="smoke",
                )
            )
            self.assertEqual(payload["experiment_id"], "exp-001")
            saved = json.loads((out / "exp-001" / "experiment_note.json").read_text(encoding="utf-8"))
            self.assertEqual(saved["phase"], "phase3")
            self.assertEqual(saved["input_artifacts"][0]["path"], str(artifact))


if __name__ == "__main__":
    unittest.main()

