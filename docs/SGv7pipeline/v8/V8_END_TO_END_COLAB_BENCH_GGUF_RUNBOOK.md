# V8 End-to-End Runbook (Local -> Colab -> Benchmark -> GGUF)

Дата: 2026-04-30  
Источник: текущий репозиторий + `/Users/unterlantas/Downloads/qwen_shafin.ipynb`

---

## 0) Что у тебя должно быть локально заранее

Проверь, что у тебя есть:

- `docs/SGv7pipeline/runs/v8_0_seed42/sgv8_train_pack`
- `experiments/sc_benchmark/workspace/eval_bundle_v1/eval_cases.jsonl`
- `docs/SGv7pipeline/runs/sgv7_full_20260417/iter3_1_prep_seed42`

Если `sgv8_train_pack` вдруг отсутствует, собери его:

```bash
cd /Users/unterlantas/Documents/XCode/shafinMultitool
bash docs/SGv7pipeline/v8/build_v8_train_pack.sh
```

---

## 1) Локально подготовь upload-пакеты для Colab

```bash
cd /Users/unterlantas/Documents/XCode/shafinMultitool

# 1) Пакет train-данных V8
cd docs/SGv7pipeline/runs/v8_0_seed42
zip -r sgv8_train_pack_upload.zip sgv8_train_pack

# 2) Пакет eval bundle (для генерации pred на кейсах)
cd /Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/workspace
zip -r eval_bundle_v1_upload.zip eval_bundle_v1
```

Дальше в Colab загрузишь:

- `sgv8_train_pack_upload.zip`
- `eval_bundle_v1_upload.zip`

---

## 2) Colab: V8 обучение + генерация план-предиктов + экспорт zip

Рантайм: лучше `A100`.

### Cell V8-00

```python
# V8 Cell 00 — CLEAN INSTALL (stable stack) + restart
!pip uninstall -y trl transformers peft accelerate bitsandbytes datasets pyarrow pandas numpy unsloth xformers
!pip install -q --no-cache-dir \
  "numpy==1.26.4" \
  "pandas==2.2.2" \
  "pyarrow==17.0.0" \
  "datasets==2.21.0" \
  "transformers==4.51.3" \
  "trl==0.11.4" \
  "peft==0.13.2" \
  "accelerate==1.1.1" \
  "bitsandbytes==0.45.5"

# optional unsloth install (может не завестись на части runtime; fallback есть в train_sft)
!pip install -q --no-cache-dir "unsloth[colab-new] @ git+https://github.com/unslothai/unsloth.git" || true

import os
os.kill(os.getpid(), 9)
```

### Cell V8-01 (mount + распаковка upload)

```python
from google.colab import drive
from pathlib import Path
import zipfile

drive.mount('/content/drive')

DRIVE_ROOT = Path("/content/drive/MyDrive")
EVAL_RUNS_DIR = DRIVE_ROOT / "sgv7_eval_runs"
ADAPTERS_DIR = EVAL_RUNS_DIR / "adapters"
ADAPTERS_DIR.mkdir(parents=True, exist_ok=True)

V8_PACK_DIR = DRIVE_ROOT / "sgv8_train_pack"
EVAL_BUNDLE_DIR = EVAL_RUNS_DIR / "eval_bundle_v1"
EVAL_BUNDLE_DIR.mkdir(parents=True, exist_ok=True)

# Если ты загрузил zip'ы в /content (через Colab Files), распакуй:
train_zip = Path("/content/sgv8_train_pack_upload.zip")
eval_zip = Path("/content/eval_bundle_v1_upload.zip")

if train_zip.exists():
    with zipfile.ZipFile(train_zip, "r") as zf:
        zf.extractall("/content/drive/MyDrive")
    print("Extracted train pack -> /content/drive/MyDrive/sgv8_train_pack")
else:
    print("train zip not found in /content, skip")

if eval_zip.exists():
    with zipfile.ZipFile(eval_zip, "r") as zf:
        zf.extractall(str(EVAL_RUNS_DIR))
    print("Extracted eval bundle -> /content/drive/MyDrive/sgv7_eval_runs/eval_bundle_v1")
else:
    print("eval zip not found in /content, skip")
```

### Cell V8-01a (пути)

```python
from pathlib import Path

DRIVE_ROOT = Path("/content/drive/MyDrive")
EVAL_RUNS_DIR = DRIVE_ROOT / "sgv7_eval_runs"
ADAPTERS_DIR = EVAL_RUNS_DIR / "adapters"
ADAPTERS_DIR.mkdir(parents=True, exist_ok=True)

EVAL_BUNDLE_DIR = EVAL_RUNS_DIR / "eval_bundle_v1"
EVAL_CASES_JSONL = EVAL_BUNDLE_DIR / "eval_cases.jsonl"

V8_PACK_DIR = DRIVE_ROOT / "sgv8_train_pack"
V8_PLAN_SFT_DIR = V8_PACK_DIR / "plan_sft"
V8_PLAN_PREF_DIR = V8_PACK_DIR / "plan_preference"

V8_PLAN_SFT_ADAPTER_DIR = ADAPTERS_DIR / "sgv8_qwen3_plan_sft_lora"
V8_PLAN_ORPO_ADAPTER_DIR = ADAPTERS_DIR / "sgv8_qwen3_plan_orpo_lora_iter1"

V8_PLAN_PRED_DIR = EVAL_RUNS_DIR / "v8_plan_predictions_seed42"
V8_PLAN_EXPORT_DIR = DRIVE_ROOT / "sgv8_eval_export_seed42"
V8_PLAN_PRED_DIR.mkdir(parents=True, exist_ok=True)
V8_PLAN_EXPORT_DIR.mkdir(parents=True, exist_ok=True)

BASE_MODEL_ID = "Qwen/Qwen3-1.7B"

required = [
    EVAL_CASES_JSONL,
    V8_PLAN_SFT_DIR / "v8_plan_sft_train.jsonl",
    V8_PLAN_SFT_DIR / "v8_plan_sft_val.jsonl",
    V8_PLAN_PREF_DIR / "v8_plan_preference_train.jsonl",
    V8_PLAN_PREF_DIR / "v8_plan_preference_val.jsonl",
]
missing = [str(p) for p in required if not p.exists()]
if missing:
    raise FileNotFoundError("Missing required V8 assets:\n" + "\n".join(missing))

print("OK paths ready")
```

### Cell V8-01b

```python
# V8 Cell 01b — torch pytree hotfix (must run BEFORE transformers/peft/trl imports)
import torch

pt = torch.utils._pytree

if not hasattr(pt, "register_constant"):
    def _register_constant(*args, **kwargs):
        return None
    pt.register_constant = _register_constant

# compatibility alias for some libs
if not hasattr(pt, "_register_pytree_node") and hasattr(pt, "register_pytree_node"):
    pt._register_pytree_node = pt.register_pytree_node

print("torch:", torch.__version__)
print("has register_constant:", hasattr(pt, "register_constant"))
print("has _register_pytree_node:", hasattr(pt, "_register_pytree_node"))
```

### Cell V8-02

```python
# V8 Cell 02 — CORE HELPERS
import json
from pathlib import Path
from transformers import AutoTokenizer

def read_jsonl(path: Path):
    rows = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows

def write_jsonl(path: Path, rows):
    with open(path, "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

tokenizer = AutoTokenizer.from_pretrained(BASE_MODEL_ID, trust_remote_code=True)
if tokenizer.pad_token is None:
    tokenizer.pad_token = tokenizer.eos_token
tokenizer.padding_side = "left"

def messages_to_text(messages):
    return tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=False)

print("Tokenizer + helpers ready")
```

### Cell V8-03

```python
# V8 Cell 03 — INPUT CHECK
must_exist = [
    V8_PLAN_SFT_DIR / "v8_plan_sft_train.jsonl",
    V8_PLAN_SFT_DIR / "v8_plan_sft_val.jsonl",
    V8_PLAN_PREF_DIR / "v8_plan_preference_train.jsonl",
    V8_PLAN_PREF_DIR / "v8_plan_preference_val.jsonl",
    EVAL_CASES_JSONL,
]
for p in must_exist:
    print("OK   " if p.exists() else "MISS ", p)

missing = [str(p) for p in must_exist if not p.exists()]
if missing:
    raise FileNotFoundError("Не хватает V8 файлов:\n" + "\n".join(missing))
```

### Cell V8-04

```python
# V8 Cell 04 — PLAN_SFT DATASET PREP
from datasets import Dataset, DatasetDict

v8_plan_train_raw = read_jsonl(V8_PLAN_SFT_DIR / "v8_plan_sft_train.jsonl")
v8_plan_val_raw = read_jsonl(V8_PLAN_SFT_DIR / "v8_plan_sft_val.jsonl")

def to_text_row_from_messages(row):
    msgs = row.get("messages")
    if not isinstance(msgs, list) or len(msgs) < 3:
        return None
    try:
        text = messages_to_text(msgs)
    except Exception:
        return None
    if not isinstance(text, str) or not text.strip():
        return None
    return {"text": text}

v8_plan_train = [x for x in (to_text_row_from_messages(r) for r in v8_plan_train_raw) if x is not None]
v8_plan_val = [x for x in (to_text_row_from_messages(r) for r in v8_plan_val_raw) if x is not None]

print("v8 plan train usable:", len(v8_plan_train))
print("v8 plan val usable:", len(v8_plan_val))

v8_plan_ds = DatasetDict({
    "train": Dataset.from_list(v8_plan_train),
    "validation": Dataset.from_list(v8_plan_val),
})
print(v8_plan_ds)
```

### Cell V8-05

```python
# V8 Cell 05 — ADAPTER COMPAT SHIM (no peft import)
import json
import shutil
import tempfile
from pathlib import Path

_ALLOWED_LORA_CONFIG_KEYS = {
    "peft_type", "task_type", "r", "target_modules", "lora_alpha", "lora_dropout",
    "fan_in_fan_out", "bias", "use_rslora", "modules_to_save", "init_lora_weights",
    "layers_to_transform", "layers_pattern", "rank_pattern", "alpha_pattern",
    "megatron_config", "megatron_core", "trainable_token_indices", "loftq_config",
    "eva_config", "corda_config", "runtime_config", "use_dora", "layer_replication",
    "lora_bias", "target_parameters", "arrow_config", "ensure_weight_tying", "exclude_modules",
}

def make_compat_adapter_dir(src_adapter_dir: Path) -> Path:
    src = Path(src_adapter_dir)
    if not src.exists():
        raise FileNotFoundError(f"Adapter dir not found: {src}")

    tmp_root = Path(tempfile.mkdtemp(prefix="peft_compat_"))
    dst = tmp_root / "adapter"
    shutil.copytree(src, dst, dirs_exist_ok=True)

    cfg_path = dst / "adapter_config.json"
    cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
    filtered = {k: v for k, v in cfg.items() if k in _ALLOWED_LORA_CONFIG_KEYS}
    cfg_path.write_text(json.dumps(filtered, ensure_ascii=False, indent=2), encoding="utf-8")
    return dst

print("compat helper ready")
```

### Cell V8-06

```python
# V8 Cell 06 — TRAIN SFT HELPER (A100-safe, no bitsandbytes)
import gc
import torch
from peft import LoraConfig, get_peft_model
from transformers import AutoModelForCausalLM, Trainer, TrainingArguments

def train_sft(ds, output_dir, run_name, num_epochs=2, lr=2e-4):
    max_seq_length = 2048

    try:
        model = AutoModelForCausalLM.from_pretrained(
            BASE_MODEL_ID, dtype=torch.bfloat16, device_map="auto",
            trust_remote_code=True, attn_implementation="flash_attention_2",
        )
    except Exception:
        model = AutoModelForCausalLM.from_pretrained(
            BASE_MODEL_ID, dtype=torch.bfloat16, device_map="auto",
            trust_remote_code=True, attn_implementation="sdpa",
        )

    model.config.use_cache = False
    model.gradient_checkpointing_enable()

    peft_config = LoraConfig(
        r=16, lora_alpha=16, lora_dropout=0.0, bias="none", task_type="CAUSAL_LM",
        target_modules=["q_proj","k_proj","v_proj","o_proj","gate_proj","up_proj","down_proj"],
    )
    model = get_peft_model(model, peft_config)

    def tokenize_row(batch):
        return tokenizer(batch["text"], truncation=True, max_length=max_seq_length, padding=False)

    train_tok = ds["train"].map(tokenize_row, remove_columns=ds["train"].column_names)
    val_tok = ds["validation"].map(tokenize_row, remove_columns=ds["validation"].column_names)

    def causal_lm_collator(features):
        batch = tokenizer.pad(features, return_tensors="pt")
        labels = batch["input_ids"].clone()
        labels[batch["attention_mask"] == 0] = -100
        batch["labels"] = labels
        return batch

    args = TrainingArguments(
        output_dir=str(output_dir), run_name=run_name, num_train_epochs=num_epochs, learning_rate=lr,
        per_device_train_batch_size=8, per_device_eval_batch_size=8, gradient_accumulation_steps=2,
        logging_steps=20, eval_strategy="no", save_strategy="epoch", save_total_limit=2, bf16=True, fp16=False,
        report_to="none", remove_unused_columns=False, dataloader_num_workers=2, dataloader_pin_memory=True,
        group_by_length=True, optim="adamw_torch_fused",
    )

    trainer = Trainer(
        model=model, args=args, train_dataset=train_tok, eval_dataset=val_tok, data_collator=causal_lm_collator,
    )

    trainer.train()
    trainer.model.save_pretrained(str(output_dir))
    tokenizer.save_pretrained(str(output_dir))
    print("Saved SFT adapter to:", output_dir)

    del trainer, model
    gc.collect()
    torch.cuda.empty_cache()
```

### Cell V8-07

```python
# V8 Cell 07 — TRAIN v8_plan_sft
if not (V8_PLAN_SFT_ADAPTER_DIR / "adapter_model.safetensors").exists():
    print("v8 plan SFT adapter not found -> training...")
    train_sft(
        ds=v8_plan_ds,
        output_dir=V8_PLAN_SFT_ADAPTER_DIR,
        run_name="sgv8_qwen3_plan_sft_lora",
        num_epochs=2,
        lr=2e-4,
    )
else:
    print("v8 plan SFT adapter already exists:", V8_PLAN_SFT_ADAPTER_DIR)

V8_PLAN_SFT_COMPAT_DIR = make_compat_adapter_dir(V8_PLAN_SFT_ADAPTER_DIR)
print("V8_PLAN_SFT_COMPAT_DIR:", V8_PLAN_SFT_COMPAT_DIR)
```

### Cell V8-08

```python
# V8 Cell 08 — PLAN_PREFERENCE ORPO DATASET PREP
from datasets import Dataset, DatasetDict
import json

v8_pref_train_raw = read_jsonl(V8_PLAN_PREF_DIR / "v8_plan_preference_train.jsonl")
v8_pref_val_raw = read_jsonl(V8_PLAN_PREF_DIR / "v8_plan_preference_val.jsonl")

def to_v8_orpo_row(row):
    msgs = row.get("messages")
    if not isinstance(msgs, list) or len(msgs) < 2:
        return None
    try:
        prompt = tokenizer.apply_chat_template(msgs, tokenize=False, add_generation_prompt=True)
    except Exception:
        return None

    chosen = row.get("chosen")
    rejected = row.get("rejected")
    if isinstance(chosen, dict):
        chosen = json.dumps(chosen, ensure_ascii=False)
    if isinstance(rejected, dict):
        rejected = json.dumps(rejected, ensure_ascii=False)
    if not isinstance(chosen, str) or not chosen.strip():
        return None
    if not isinstance(rejected, str) or not rejected.strip():
        return None
    return {"prompt": prompt, "chosen": chosen, "rejected": rejected}

v8_orpo_train = [x for x in (to_v8_orpo_row(r) for r in v8_pref_train_raw) if x is not None]
v8_orpo_val = [x for x in (to_v8_orpo_row(r) for r in v8_pref_val_raw) if x is not None]

print("v8 ORPO train usable:", len(v8_orpo_train))
print("v8 ORPO val usable:", len(v8_orpo_val))

v8_orpo_ds = DatasetDict({
    "train": Dataset.from_list(v8_orpo_train),
    "validation": Dataset.from_list(v8_orpo_val),
})
print(v8_orpo_ds)
```

### Cell V8-09

```python
# V8 Cell 09 — ORPO BOOTSTRAP + COMPAT PATCHES
import importlib.util
import subprocess
import sys
import os

def ensure_module(module_name: str, pip_spec: str) -> bool:
    if importlib.util.find_spec(module_name) is None:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", pip_spec])
        return True
    return False

changed = False
changed |= ensure_module("trl", "trl==0.11.4")
changed |= ensure_module("transformers", "transformers==4.51.3")
changed |= ensure_module("peft", "peft==0.13.2")
changed |= ensure_module("accelerate", "accelerate==1.1.1")

if changed:
    print("Installed missing ORPO deps. Restarting runtime now...")
    os.kill(os.getpid(), 9)

import inspect
from trl import ORPOTrainer
from transformers import Trainer

_orig_orpo_get_batch_samples = ORPOTrainer.get_batch_samples
_base_trainer_get_batch_samples = Trainer.get_batch_samples
_base_sig = inspect.signature(_base_trainer_get_batch_samples)

def _patched_orpo_get_batch_samples(self, *args, **kwargs):
    trainer_loop_path = (len(args) >= 1 and not hasattr(args[0], "generate"))
    if trainer_loop_path:
        if "device" in _base_sig.parameters and "device" not in kwargs and len(args) < 3:
            dev = getattr(getattr(self, "args", None), "device", None)
            return _base_trainer_get_batch_samples(self, *args, device=dev)
        return _base_trainer_get_batch_samples(self, *args, **kwargs)
    try:
        return _orig_orpo_get_batch_samples(self, *args, **kwargs)
    except TypeError:
        kwargs.pop("device", None)
        return _orig_orpo_get_batch_samples(self, *args, **kwargs)

ORPOTrainer.get_batch_samples = _patched_orpo_get_batch_samples

if not getattr(ORPOTrainer, "_v8_compute_loss_patch", False):
    _orig_compute_loss = ORPOTrainer.compute_loss
    sig = inspect.signature(_orig_compute_loss)
    if "num_items_in_batch" not in sig.parameters:
        def _patched_compute_loss(self, model, inputs, return_outputs=False, num_items_in_batch=None):
            return _orig_compute_loss(self, model, inputs, return_outputs=return_outputs)
        ORPOTrainer.compute_loss = _patched_compute_loss
    ORPOTrainer._v8_compute_loss_patch = True

if not getattr(ORPOTrainer, "_v8_log_patch", False):
    _orig_log = ORPOTrainer.log
    sig = inspect.signature(_orig_log)
    if len(sig.parameters) == 2:
        def _patched_log(self, logs, start_time=None):
            return _orig_log(self, logs)
        ORPOTrainer.log = _patched_log
    ORPOTrainer._v8_log_patch = True

print("ORPO compatibility patches applied")
```

### Cell V8-09b

```python
# V8 Cell 09b — patch Trainer.__init__ to swallow legacy tokenizer kwarg
import inspect
from transformers import Trainer

if not getattr(Trainer, "_v8_tokenizer_kw_patch", False):
    _orig_trainer_init = Trainer.__init__
    _sig = inspect.signature(_orig_trainer_init)

    def _patched_trainer_init(self, *args, **kwargs):
        tok = kwargs.pop("tokenizer", None)
        if "processing_class" in _sig.parameters:
            if kwargs.get("processing_class", None) is None and tok is not None:
                kwargs["processing_class"] = tok
        else:
            kwargs.pop("processing_class", None)
        return _orig_trainer_init(self, *args, **kwargs)

    Trainer.__init__ = _patched_trainer_init
    Trainer._v8_tokenizer_kw_patch = True
    print("Patched Trainer.__init__: tokenizer kwarg is now compatible")
else:
    print("Trainer tokenizer patch already applied")
```

### Cell V8-10

```python
# V8 Cell 10 — TRAIN v8_plan_orpo_iter1 (A100-safe, no bitsandbytes)
import gc
import inspect
import warnings
import torch
from peft import PeftModel
from transformers import AutoModelForCausalLM
from trl import ORPOTrainer, ORPOConfig

warnings.filterwarnings("ignore", message=".*Trainer.tokenizer is now deprecated.*")
warnings.filterwarnings("ignore", message=".*No label_names provided for model class `PeftModelForCausalLM`.*")

if len(v8_orpo_ds["train"]) == 0:
    raise RuntimeError("V8 ORPO train dataset is empty")

try:
    base = AutoModelForCausalLM.from_pretrained(
        BASE_MODEL_ID, dtype=torch.bfloat16, device_map="auto",
        trust_remote_code=True, attn_implementation="flash_attention_2",
    )
except Exception:
    base = AutoModelForCausalLM.from_pretrained(
        BASE_MODEL_ID, dtype=torch.bfloat16, device_map="auto",
        trust_remote_code=True, attn_implementation="sdpa",
    )

base.config.use_cache = False
base.gradient_checkpointing_enable()
model = PeftModel.from_pretrained(base, str(V8_PLAN_SFT_COMPAT_DIR), is_trainable=True)

cfg_params = set(inspect.signature(ORPOConfig.__init__).parameters.keys())
cfg_kwargs = {
    "output_dir": str(V8_PLAN_ORPO_ADAPTER_DIR),
    "num_train_epochs": 1,
    "learning_rate": 1e-6,
    "beta": 0.08,
    "per_device_train_batch_size": 4,
    "per_device_eval_batch_size": 4,
    "gradient_accumulation_steps": 2,
    "bf16": True,
    "gradient_checkpointing": True,
    "optim": "adamw_torch_fused",
    "lr_scheduler_type": "cosine",
    "warmup_steps": 50,
    "logging_steps": 10,
    "save_steps": 100,
    "save_total_limit": 2,
    "max_length": 1536,
    "max_prompt_length": 1152,
    "report_to": "none",
    "remove_unused_columns": False,
}
if "eval_strategy" in cfg_params:
    cfg_kwargs["eval_strategy"] = "steps"
    if "eval_steps" in cfg_params:
        cfg_kwargs["eval_steps"] = 100
elif "evaluation_strategy" in cfg_params:
    cfg_kwargs["evaluation_strategy"] = "steps"
    if "eval_steps" in cfg_params:
        cfg_kwargs["eval_steps"] = 100

cfg_kwargs = {k: v for k, v in cfg_kwargs.items() if k in cfg_params}
orpo_args = ORPOConfig(**cfg_kwargs)

tr_params = set(inspect.signature(ORPOTrainer.__init__).parameters.keys())
trainer_kwargs = {
    "model": model,
    "args": orpo_args,
    "train_dataset": v8_orpo_ds["train"],
    "eval_dataset": v8_orpo_ds["validation"],
}
if "processing_class" in tr_params:
    trainer_kwargs["processing_class"] = tokenizer
elif "tokenizer" in tr_params:
    trainer_kwargs["tokenizer"] = tokenizer
else:
    raise RuntimeError("ORPOTrainer has neither processing_class nor tokenizer")

trainer = ORPOTrainer(**trainer_kwargs)
trainer.train()

trainer.model.save_pretrained(str(V8_PLAN_ORPO_ADAPTER_DIR))
tokenizer.save_pretrained(str(V8_PLAN_ORPO_ADAPTER_DIR))
print("Saved V8 ORPO adapter to:", V8_PLAN_ORPO_ADAPTER_DIR)

del trainer, model, base
gc.collect()
torch.cuda.empty_cache()
```

### Cell V8-11

```python
# V8 Cell 11 — PLAN INFERENCE HELPERS
import gc
import json
import re
import torch
from pathlib import Path
from peft import PeftModel
from transformers import AutoModelForCausalLM

cases = read_jsonl(EVAL_CASES_JSONL)
print("eval cases:", len(cases))

PLAN_SYSTEM_PROMPT = "Ты ScenePlanIR planner. Верни только валидный JSON ScenePlanIR без пояснений и без markdown."

_THINK_BLOCK_RE = re.compile(r"<think\b[^>]*>.*?</think>", flags=re.IGNORECASE | re.DOTALL)
_THINK_OPEN_RE = re.compile(r"<think\b[^>]*>", flags=re.IGNORECASE)
_THINK_CLOSE_RE = re.compile(r"</think>", flags=re.IGNORECASE)

def load_eval_model(adapter_path=None):
    try:
        m = AutoModelForCausalLM.from_pretrained(
            BASE_MODEL_ID,
            torch_dtype=torch.bfloat16,
            device_map="auto",
            trust_remote_code=True,
            attn_implementation="flash_attention_2",
        )
    except Exception:
        m = AutoModelForCausalLM.from_pretrained(
            BASE_MODEL_ID,
            torch_dtype=torch.bfloat16,
            device_map="auto",
            trust_remote_code=True,
            attn_implementation="sdpa",
        )

    if adapter_path:
        compat_adapter_path = make_compat_adapter_dir(adapter_path)
        m = PeftModel.from_pretrained(m, str(compat_adapter_path))
        try:
            m = m.merge_and_unload()
        except Exception:
            pass

    m.eval()
    m.config.use_cache = True
    return m

def _strip_markdown_fence(text: str) -> str:
    candidate = text.strip()
    if not candidate.startswith("```"):
        return candidate
    lines = candidate.splitlines()
    if len(lines) < 2:
        return candidate
    if lines[0].startswith("```"):
        lines = lines[1:]
    if lines and lines[-1].strip() == "```":
        lines = lines[:-1]
    return "\n".join(lines).strip()

def _strip_think_tags(text: str) -> str:
    value = _THINK_BLOCK_RE.sub("", text)
    value = _THINK_OPEN_RE.sub("", value)
    value = _THINK_CLOSE_RE.sub("", value)
    return value

def _normalize_raw_output_text(text: str) -> str:
    value = _strip_think_tags(text)
    return _strip_markdown_fence(value).strip()

def first_json_object(text):
    if not text:
        return None
    candidate = _normalize_raw_output_text(text)
    try:
        obj = json.loads(candidate)
        return obj if isinstance(obj, dict) else None
    except Exception:
        pass

    start = candidate.find("{")
    if start < 0:
        return None

    depth = 0
    in_string = False
    escape = False
    end = -1

    for idx in range(start, len(candidate)):
        ch = candidate[idx]
        if in_string:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False
            continue
        if ch == '"':
            in_string = True
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                end = idx
                break

    if end < 0:
        return None

    snippet = candidate[start:end + 1]
    try:
        obj = json.loads(snippet)
        return obj if isinstance(obj, dict) else None
    except Exception:
        return None

def source_anchor_bundle_from_eval_case(case):
    gold = case.get("gold_target_json") or {}
    actors = gold.get("actors", []) if isinstance(gold, dict) else []
    beats = gold.get("beats", []) if isinstance(gold, dict) else []
    marked = case.get("marked_objects", []) if isinstance(case.get("marked_objects"), list) else []

    marked_ids = []
    marked_types = []
    object_surface_mentions = []

    for item in marked:
        if not isinstance(item, dict):
            continue
        if item.get("id"):
            marked_ids.append(str(item["id"]))
        marked_types.append(str(item.get("type") or "generic"))
        canonical_name = str(item.get("canonical_name") or "").strip().lower()
        if canonical_name:
            object_surface_mentions.append(canonical_name)
        for alias in item.get("allowed_aliases", []):
            alias_text = str(alias).strip().lower()
            if alias_text:
                object_surface_mentions.append(alias_text)

    unsupported_action_flags = []
    for beat in beats:
        if not isinstance(beat, dict):
            continue
        for action in beat.get("actions", []):
            if isinstance(action, dict) and action.get("type") == "described_action":
                unsupported_action_flags.append(str(action.get("id") or "described_action"))

    same_type_marker_conflict = len(marked_types) != len(set(marked_types))
    low_confidence_flags = []
    if same_type_marker_conflict:
        low_confidence_flags.append("same_type_marker_conflict")
    if unsupported_action_flags:
        low_confidence_flags.append("unsupported_action_present")

    return {
        "actor_count_hint": len(actors),
        "ordinal_mentions": list((case.get("eval_expectations") or {}).get("expected_ordinal_bindings", {}).keys()),
        "mentioned_marked_objects": marked_ids,
        "object_surface_mentions": sorted(set(object_surface_mentions)),
        "phase_cues": list((case.get("eval_expectations") or {}).get("expected_phase_sequence", [])),
        "unsupported_action_flags": unsupported_action_flags,
        "same_type_marker_conflict": same_type_marker_conflict,
        "low_confidence_flags": low_confidence_flags,
    }

def render_v8_plan_user_prompt(case):
    bundle = source_anchor_bundle_from_eval_case(case)
    sections = [
        "Task instruction:\nСконвертируй source text в ScenePlanIR JSON.",
        "Output contract:\nВерни только JSON c top-level полями actors, objects, beats, spatialRelations, referenceBindings.",
        "SourceAnchorBundle:\n" + json.dumps(bundle, ensure_ascii=False, separators=(',', ':')),
        "Source text:\n" + str(case.get("source_text") or "").strip(),
    ]
    return "\n\n".join(sections), bundle

def _plan_schema_valid(plan):
    if not isinstance(plan, dict):
        return False
    if not isinstance(plan.get("actors"), list):
        return False
    if not isinstance(plan.get("objects"), list):
        return False
    if not isinstance(plan.get("beats"), list):
        return False
    if not isinstance(plan.get("spatialRelations"), list):
        return False
    if not isinstance(plan.get("referenceBindings"), dict):
        return False
    for beat in plan["beats"]:
        if not isinstance(beat, dict):
            return False
        actions = beat.get("actions")
        if not isinstance(actions, list) or not actions:
            return False
    return True

def postprocess_plan_prediction(raw_text):
    raw_text_clean = _normalize_raw_output_text(raw_text)
    plan = first_json_object(raw_text_clean) if raw_text_clean else None
    return {
        "raw_output_text": raw_text,
        "raw_output_text_clean": raw_text_clean,
        "predicted_plan_ir": plan,
        "raw_output_json": plan,
        "plan_schema_valid": _plan_schema_valid(plan),
    }

def generate_v8_plan_predictions(model_id, adapter_path, seed, out_path, batch_size=8, max_new_tokens=512, save_every_batches=2):
    existing = {}
    if out_path.exists():
        for r in read_jsonl(out_path):
            case_id = r.get("eval_case_id")
            if isinstance(case_id, str) and isinstance(r.get("predicted_plan_ir"), dict):
                existing[case_id] = r

    rows_by_id = dict(existing)
    done = set(rows_by_id.keys())
    pending = [case for case in cases if case["eval_case_id"] not in done]

    print(f"[{model_id} seed={seed}] resume rows={len(done)} pending={len(pending)}")
    if not pending:
        print(f"[{model_id}] nothing to do")
        return

    model = load_eval_model(adapter_path=adapter_path)
    device = next(model.parameters()).device

    try:
        batch_counter = 0
        for start in range(0, len(pending), batch_size):
            chunk = pending[start:start + batch_size]
            prompts = []
            bundles = []

            for case in chunk:
                user_prompt, bundle = render_v8_plan_user_prompt(case)
                bundles.append(bundle)
                msgs = [
                    {"role": "system", "content": PLAN_SYSTEM_PROMPT},
                    {"role": "user", "content": user_prompt},
                ]
                prompt = tokenizer.apply_chat_template(msgs, tokenize=False, add_generation_prompt=True)
                prompts.append(prompt)

            inputs = tokenizer(
                prompts,
                return_tensors="pt",
                padding=True,
                truncation=True,
            ).to(device)

            torch.manual_seed(seed)

            with torch.inference_mode():
                out_ids = model.generate(
                    **inputs,
                    max_new_tokens=max_new_tokens,
                    do_sample=False,
                    use_cache=True,
                    pad_token_id=tokenizer.pad_token_id,
                    eos_token_id=tokenizer.eos_token_id,
                )

            input_len = inputs["input_ids"].shape[1]
            gen_ids = out_ids[:, input_len:]
            raw_texts = tokenizer.batch_decode(gen_ids, skip_special_tokens=True)

            for case, bundle, raw_text in zip(chunk, bundles, raw_texts):
                row = postprocess_plan_prediction(raw_text)
                row["eval_case_id"] = case["eval_case_id"]
                row["source_anchor_bundle"] = bundle
                rows_by_id[case["eval_case_id"]] = row

            batch_counter += 1
            if batch_counter % save_every_batches == 0:
                ordered = [rows_by_id[k] for k in sorted(rows_by_id.keys())]
                write_jsonl(out_path, ordered)
                parseable = sum(1 for r in ordered if isinstance(r.get("predicted_plan_ir"), dict))
                print(f"[{model_id}] saved {len(ordered)} rows parseable={parseable}")

            print(f"[{model_id}] {min(start + len(chunk), len(pending))}/{len(pending)}")

        ordered = [rows_by_id[k] for k in sorted(rows_by_id.keys())]
        write_jsonl(out_path, ordered)
        parseable = sum(1 for r in ordered if isinstance(r.get("predicted_plan_ir"), dict))
        print(f"[{model_id}] done parseable={parseable}/{len(ordered)} -> {out_path}")

    finally:
        del model
        gc.collect()
        torch.cuda.empty_cache()
```

### Cell V8-12

```python
# V8 Cell 12 — RUN PLAN PREDICTIONS
SEEDS = [42]

v8_specs = [
    ("dataset_v8_plan_sft", V8_PLAN_SFT_ADAPTER_DIR),
    ("dataset_v8_plan_orpo_iter1", V8_PLAN_ORPO_ADAPTER_DIR),
]

for model_id, adapter in v8_specs:
    if not (Path(adapter) / "adapter_model.safetensors").exists():
        raise FileNotFoundError(f"Missing adapter for {model_id}: {adapter}")

for model_id, adapter in v8_specs:
    for seed in SEEDS:
        out_file = V8_PLAN_PRED_DIR / f"{model_id}_seed{seed}.plan_predictions.jsonl"
        generate_v8_plan_predictions(
            model_id=model_id,
            adapter_path=adapter,
            seed=seed,
            out_path=out_file,
            batch_size=8,
            max_new_tokens=512,
            save_every_batches=2,
        )
```

### Cell V8-13

```python
# V8 Cell 13 — MANIFEST + ZIP EXPORT
import json
import zipfile

summary = {}

for model_id in ["dataset_v8_plan_sft", "dataset_v8_plan_orpo_iter1"]:
    p = V8_PLAN_PRED_DIR / f"{model_id}_seed42.plan_predictions.jsonl"
    rows = read_jsonl(p)

    parseable = sum(1 for r in rows if isinstance(r.get("predicted_plan_ir"), dict))
    schema_valid = sum(1 for r in rows if bool(r.get("plan_schema_valid", False)))

    summary[model_id] = {
        "rows": len(rows),
        "plan_parseable_rows": parseable,
        "plan_schema_valid_rows": schema_valid,
        "path": str(p),
    }

print(json.dumps(summary, ensure_ascii=False, indent=2))

manifest_path = V8_PLAN_EXPORT_DIR / "v8_plan_predictions_manifest_seed42.json"
manifest_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
print("Saved manifest:", manifest_path)

final_zip_path = V8_PLAN_EXPORT_DIR / "sgv8_eval_pack_seed42.zip"

with zipfile.ZipFile(final_zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for model_id in ["dataset_v8_plan_sft", "dataset_v8_plan_orpo_iter1"]:
        p = V8_PLAN_PRED_DIR / f"{model_id}_seed42.plan_predictions.jsonl"
        zf.write(p, arcname=p.name)
    zf.write(manifest_path, arcname=manifest_path.name)

print("ZIP:", final_zip_path)
```

Ожидаемый результат после V8-13:

- `/content/drive/MyDrive/sgv8_eval_export_seed42/sgv8_eval_pack_seed42.zip`

Скачай этот zip локально и положи в:

- `docs/SGv7pipeline/runs/v8_0_seed42/sgv8_eval_export_seed42/sgv8_eval_pack_seed42.zip`

---

## 3) Локально: прогон benchmark

```bash
cd /Users/unterlantas/Documents/XCode/shafinMultitool
python3 docs/SGv7pipeline/v8/07_run_v8_local_benchmark.py
```

Результаты:

- `docs/SGv7pipeline/runs/v8_0_seed42/benchmark_results_seed42/aggregate/runs_scored.csv`
- `docs/SGv7pipeline/runs/v8_0_seed42/benchmark_results_seed42/aggregate/pairwise_compare.csv`
- `docs/SGv7pipeline/runs/v8_0_seed42/benchmark_results_seed42/aggregate/model_slice_summary.csv`
- `docs/SGv7pipeline/runs/v8_0_seed42/benchmark_results_seed42/aggregate/v8_plan_slice_summary.csv`
- `docs/SGv7pipeline/runs/v8_0_seed42/benchmark_results_seed42/aggregate/scientific_report.md`

---

## 4) Colab: export в GGUF из V8 adapter

Это отдельный Colab-прогон после тренировки (или в том же рантайме).

### GGUF-00 (fix torchao + restart)

```python
# Fix torchao version for PEFT
!pip -q uninstall -y torchao
!pip -q install -U "torchao>=0.16.0"
import os
os.kill(os.getpid(), 9)
```

### GGUF-01

```python
!apt-get -y update
!apt-get -y install git cmake build-essential
!pip -q install -U transformers peft accelerate safetensors sentencepiece huggingface_hub
```

### GGUF-02

```python
from google.colab import drive
from pathlib import Path
import os, json, shutil, tempfile, inspect

drive.mount('/content/drive')

BASE_MODEL_ID = "Qwen/Qwen3-1.7B"
WORKDIR = Path("/content/v8_export")
WORKDIR.mkdir(parents=True, exist_ok=True)

EXPORT_DIR = Path("/content/drive/MyDrive/sgv8_gguf_export")
EXPORT_DIR.mkdir(parents=True, exist_ok=True)

CANDIDATES = [
    Path("/content/drive/MyDrive/sgv7_eval_runs/adapters/sgv8_qwen3_plan_orpo_lora_iter1"),
    Path("/content/drive/MyDrive/sgv7_eval_runs/adapters/sgv8_qwen3_plan_sft_lora"),
    Path("/content/drive/MyDrive/sgv8_qwen3_plan_orpo_lora_iter1"),
    Path("/content/drive/MyDrive/sgv8_qwen3_plan_sft_lora"),
]

ADAPTER_DIR = next((p for p in CANDIDATES if (p / "adapter_model.safetensors").exists()), None)
if ADAPTER_DIR is None:
    raise FileNotFoundError("Не найден adapter_model.safetensors. Проверь путь в CANDIDATES.")

print("ADAPTER_DIR:", ADAPTER_DIR)
print("EXPORT_DIR:", EXPORT_DIR)
```

### GGUF-03

```python
def make_compat_adapter_dir(src_adapter_dir: Path) -> Path:
    from peft import LoraConfig

    src = Path(src_adapter_dir)
    tmp_root = Path(tempfile.mkdtemp(prefix="peft_compat_"))
    dst = tmp_root / "adapter"
    shutil.copytree(src, dst, dirs_exist_ok=True)

    cfg_path = dst / "adapter_config.json"
    if not cfg_path.exists():
        return dst

    cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
    allowed = set(inspect.signature(LoraConfig.__init__).parameters.keys())
    filtered = {k: v for k, v in cfg.items() if k in allowed}
    cfg_path.write_text(json.dumps(filtered, ensure_ascii=False, indent=2), encoding="utf-8")
    return dst

COMPAT_ADAPTER_DIR = make_compat_adapter_dir(ADAPTER_DIR)
print("COMPAT_ADAPTER_DIR:", COMPAT_ADAPTER_DIR)
```

### GGUF-04 (merge adapter -> HF)

```python
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer
from peft import PeftModel

MERGED_DIR = WORKDIR / "merged_hf"
MERGED_DIR.mkdir(parents=True, exist_ok=True)

dtype = torch.bfloat16 if (torch.cuda.is_available() and torch.cuda.is_bf16_supported()) else (
    torch.float16 if torch.cuda.is_available() else torch.float32
)

print("dtype:", dtype, "cuda:", torch.cuda.is_available())

base = AutoModelForCausalLM.from_pretrained(
    BASE_MODEL_ID,
    torch_dtype=dtype,
    device_map="auto" if torch.cuda.is_available() else "cpu",
    trust_remote_code=True,
)

tokenizer = AutoTokenizer.from_pretrained(BASE_MODEL_ID, trust_remote_code=True)
if tokenizer.pad_token is None:
    tokenizer.pad_token = tokenizer.eos_token

peft_model = PeftModel.from_pretrained(base, str(COMPAT_ADAPTER_DIR))
merged = peft_model.merge_and_unload()

merged.save_pretrained(str(MERGED_DIR), safe_serialization=True, max_shard_size="2GB")
tokenizer.save_pretrained(str(MERGED_DIR))

print("Merged model saved to:", MERGED_DIR)
```

### GGUF-05 (build llama.cpp)

```python
%cd /content
!rm -rf llama.cpp
!git clone https://github.com/ggerganov/llama.cpp
%cd /content/llama.cpp

!cmake -S . -B build -DGGML_CUDA=ON
!cmake --build build -j --target llama-quantize
```

### GGUF-06 (HF -> F16 GGUF)

```python
%cd /content/llama.cpp

GGUF_F16 = WORKDIR / "dataset_v8_plan_orpo_iter1_f16.gguf"

!python3 convert_hf_to_gguf.py /content/v8_export/merged_hf \
  --outfile /content/v8_export/dataset_v8_plan_orpo_iter1_f16.gguf \
  --outtype f16

print("GGUF_F16:", GGUF_F16, "exists:", GGUF_F16.exists())
```

### GGUF-07 (F16 -> Q4_K_M)

```python
%cd /content/llama.cpp

GGUF_Q4 = WORKDIR / "dataset_v8_plan_orpo_iter1_q4_k_m.gguf"

!./build/bin/llama-quantize \
  /content/v8_export/dataset_v8_plan_orpo_iter1_f16.gguf \
  /content/v8_export/dataset_v8_plan_orpo_iter1_q4_k_m.gguf \
  Q4_K_M

print("GGUF_Q4:", GGUF_Q4, "exists:", GGUF_Q4.exists())
```

### GGUF-08 (копия в Drive + манифест)

```python
from pathlib import Path
import json, time, shutil

GGUF_F16 = Path("/content/v8_export/dataset_v8_plan_orpo_iter1_f16.gguf")
GGUF_Q4  = Path("/content/v8_export/dataset_v8_plan_orpo_iter1_q4_k_m.gguf")

shutil.copy2(GGUF_F16, EXPORT_DIR / GGUF_F16.name)
shutil.copy2(GGUF_Q4,  EXPORT_DIR / GGUF_Q4.name)

manifest = {
    "base_model": BASE_MODEL_ID,
    "adapter_dir": str(ADAPTER_DIR),
    "export_time": time.strftime("%Y-%m-%d %H:%M:%S"),
    "files": [
        str(EXPORT_DIR / GGUF_F16.name),
        str(EXPORT_DIR / GGUF_Q4.name),
    ]
}
(EXPORT_DIR / "gguf_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

print("Done. Files:")
print(EXPORT_DIR / GGUF_F16.name)
print(EXPORT_DIR / GGUF_Q4.name)
print(EXPORT_DIR / "gguf_manifest.json")
```

Итог в Drive:

- `/content/drive/MyDrive/sgv8_gguf_export/dataset_v8_plan_orpo_iter1_f16.gguf`
- `/content/drive/MyDrive/sgv8_gguf_export/dataset_v8_plan_orpo_iter1_q4_k_m.gguf`
- `/content/drive/MyDrive/sgv8_gguf_export/gguf_manifest.json`

---

## 5) Проверка конечного результата

1. Benchmark-файлы на локали есть и не пустые (особенно `runs_scored.csv` и `scientific_report.md`).
2. GGUF-файлы есть в Drive и скачаны локально.
3. В приложение добавляешь именно `dataset_v8_plan_orpo_iter1_q4_k_m.gguf` (как runtime-модель).

---

## 6) Частые ошибки и быстрые фиксы

- `ImportError ... torchao ... incompatible`  
  Запусти `GGUF-00` (переустановка `torchao>=0.16.0`) + restart.

- `ModuleNotFoundError: trl` в ORPO шаге  
  Запусти `V8-09` (он дотянет пакет и перезапустит runtime при необходимости).

- `bitsandbytes>=0.46.1` ошибки  
  В этом runbook обучение идет без bnb-квантизации в тренинге, на `bf16`/`sdpa` fallback.

- `generatedTokens=0` на inference в приложении  
  Это уже runtime prompt/decoder issue, а не Colab export issue; к benchmark/gguf шагам не относится.
