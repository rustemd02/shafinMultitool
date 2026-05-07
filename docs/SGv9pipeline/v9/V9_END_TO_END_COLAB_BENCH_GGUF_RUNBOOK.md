# V9 End-to-End Runbook (Dataset -> Colab Train -> Event Predictions -> Local Benchmark -> GGUF)

Дата: 2026-04-30  
Контекст: текущий `V9-Full` в `docs/SGv9pipeline/v9/*`

---

## Короткий ответ на главный вопрос

Для текущего этапа считаем, что у тебя уже есть рабочий V8-бейзлайн и `CIR`. Поэтому в этом runbook основной путь простой: **берем существующий `CIR` и конвертируем его в V9 `event_sft + patch_sft`**, затем идем в Colab/benchmark/GGUF.

Этот документ не описывает новую генерацию source/CIR в главе 1. Здесь только практичный путь “из того, что уже есть”.

---

## 1) Локально: конвертация существующего V8-бейзлайна в V9 формат

Исходим из того, что у тебя уже есть V8 этап и исходный `CIR`:
- `docs/SGv7pipeline/runs/sgv7_full_20260417/final/cir_merged.jsonl`

Ниже один основной блок команд: он сразу собирает V9 `event_sft` и `patch_sft` в run-папку V9.

```bash
cd /Users/unterlantas/Documents/XCode/shafinMultitool

export REPO=/Users/unterlantas/Documents/XCode/shafinMultitool
export RUN_ROOT=$REPO/docs/SGv9pipeline/runs/v9_0_seed42
export CIR_JSONL=$REPO/docs/SGv7pipeline/runs/sgv7_full_20260417/final/cir_merged.jsonl

mkdir -p "$RUN_ROOT"/{event_sft,patch_sft,colab_upload,colab_export,eval_artifacts,benchmark_results_seed42}

python3 $REPO/docs/SGv9pipeline/v9/01_build_v9_event_dataset.py \
  --cir-jsonl "$CIR_JSONL" \
  --output-dir "$RUN_ROOT/event_sft" \
  --val-fraction 0.10 \
  --seed 42

python3 $REPO/docs/SGv9pipeline/v9/02_build_v9_patch_dataset.py \
  --cir-jsonl "$CIR_JSONL" \
  --output-dir "$RUN_ROOT/patch_sft" \
  --val-fraction 0.10 \
  --seed 42
```

Быстрая sanity-проверка после конвертации:

```bash
python3 - << 'PY'
import json
from pathlib import Path
root = Path('/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv9pipeline/runs/v9_0_seed42')
for rel in [
    'event_sft/v9_event_sft_all.jsonl',
    'event_sft/v9_event_sft_train.jsonl',
    'event_sft/v9_event_sft_val.jsonl',
    'patch_sft/v9_patch_sft_all.jsonl',
    'patch_sft/v9_patch_sft_train.jsonl',
    'patch_sft/v9_patch_sft_val.jsonl',
]:
    p = root / rel
    n = sum(1 for ln in p.open('r', encoding='utf-8') if ln.strip())
    print(rel, n)
PY
```

---

## 2) Локально: подготовить upload-пакеты в Colab

Нужны 2 zip:

1. `v9_event_sft` (train/val/all + manifest)  
2. `eval_cases` для инференса

```bash
cd "$RUN_ROOT"
zip -r colab_upload/v9_event_sft_upload.zip event_sft

cd "$REPO/experiments/sc_benchmark/workspace"
zip -r "$RUN_ROOT/colab_upload/eval_bundle_v1_upload.zip" eval_bundle_v1
```

Загрузи эти 2 zip в Colab (`/content`).

---

## 3) Colab: обучение V9 event model (adapter)

Рантайм: лучше `A100`.

### Cell V9-00 (чистый стек + restart)

```python
!pip uninstall -y trl transformers peft accelerate bitsandbytes datasets pyarrow pandas numpy unsloth xformers torchao
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

import os
os.kill(os.getpid(), 9)
```

### Cell V9-01 (mount + распаковка)

```python
from google.colab import drive
from pathlib import Path
import zipfile

drive.mount('/content/drive')

DRIVE_ROOT = Path("/content/drive/MyDrive")
V9_ROOT = DRIVE_ROOT / "sgv9_eval_runs"
V9_ROOT.mkdir(parents=True, exist_ok=True)
ADAPTERS_DIR = V9_ROOT / "adapters"
ADAPTERS_DIR.mkdir(parents=True, exist_ok=True)

event_zip = Path("/content/v9_event_sft_upload.zip")
eval_zip = Path("/content/eval_bundle_v1_upload.zip")

if event_zip.exists():
    with zipfile.ZipFile(event_zip, "r") as zf:
        zf.extractall(str(V9_ROOT))
if eval_zip.exists():
    with zipfile.ZipFile(eval_zip, "r") as zf:
        zf.extractall(str(V9_ROOT))

EVENT_DIR = V9_ROOT / "event_sft"
EVAL_CASES = V9_ROOT / "eval_bundle_v1" / "eval_cases.jsonl"
ADAPTER_DIR = ADAPTERS_DIR / "sgv9_qwen3_event_sft_lora"

BASE_MODEL_ID = "Qwen/Qwen3-1.7B"
print(EVENT_DIR, EVAL_CASES, ADAPTER_DIR, sep="\n")
```

### Cell V9-02 (helpers + tokenizer)

```python
import json
from pathlib import Path
from transformers import AutoTokenizer
from datasets import Dataset, DatasetDict

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
```

### Cell V9-03 (dataset prep)

```python
train_raw = read_jsonl(EVENT_DIR / "v9_event_sft_train.jsonl")
val_raw = read_jsonl(EVENT_DIR / "v9_event_sft_val.jsonl")
all_raw = read_jsonl(EVENT_DIR / "v9_event_sft_all.jsonl")

def to_text_row(row):
    msgs = row.get("messages")
    if not isinstance(msgs, list) or len(msgs) < 3:
        return None
    txt = messages_to_text(msgs)
    if not txt.strip():
        return None
    return {"text": txt}

train_rows = [x for x in (to_text_row(r) for r in train_raw) if x is not None]
val_rows = [x for x in (to_text_row(r) for r in val_raw) if x is not None]

event_ds = DatasetDict({
    "train": Dataset.from_list(train_rows),
    "validation": Dataset.from_list(val_rows),
})
print(event_ds)
print("all_raw rows:", len(all_raw))
```

### Cell V9-04 (train helper)

```python
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

    def tok(batch):
        return tokenizer(batch["text"], truncation=True, max_length=max_seq_length, padding=False)

    train_tok = ds["train"].map(tok, remove_columns=ds["train"].column_names)
    val_tok = ds["validation"].map(tok, remove_columns=ds["validation"].column_names)

    def collate(features):
        batch = tokenizer.pad(features, return_tensors="pt")
        labels = batch["input_ids"].clone()
        labels[batch["attention_mask"] == 0] = -100
        batch["labels"] = labels
        return batch

    args = TrainingArguments(
        output_dir=str(output_dir),
        run_name=run_name,
        num_train_epochs=num_epochs,
        learning_rate=lr,
        per_device_train_batch_size=8,
        per_device_eval_batch_size=8,
        gradient_accumulation_steps=2,
        logging_steps=20,
        eval_strategy="no",
        save_strategy="epoch",
        save_total_limit=2,
        bf16=True,
        report_to="none",
        remove_unused_columns=False,
        group_by_length=True,
        optim="adamw_torch_fused",
    )

    trainer = Trainer(model=model, args=args, train_dataset=train_tok, eval_dataset=val_tok, data_collator=collate)
    trainer.train()
    trainer.model.save_pretrained(str(output_dir))
    tokenizer.save_pretrained(str(output_dir))
    print("saved:", output_dir)

    del trainer, model
    gc.collect()
    torch.cuda.empty_cache()
```

### Cell V9-05 (train)

```python
if not (ADAPTER_DIR / "adapter_model.safetensors").exists():
    train_sft(
        ds=event_ds,
        output_dir=ADAPTER_DIR,
        run_name="sgv9_qwen3_event_sft_lora",
        num_epochs=2,
        lr=2e-4,
    )
else:
    print("adapter already exists:", ADAPTER_DIR)
```

---

## 4) Colab: генерация V9 event predictions для benchmark

### Cell V9-06 (inference helpers)

```python
import re
import gc
import torch
from peft import PeftModel
from transformers import AutoModelForCausalLM

cases = read_jsonl(EVAL_CASES)
all_rows = read_jsonl(EVENT_DIR / "v9_event_sft_all.jsonl")
slot_by_sample_id = {str(r.get("sample_id")): r.get("slot_catalog") for r in all_rows if isinstance(r.get("slot_catalog"), dict)}

SYSTEM_PROMPT = "Ты V9 slot-event planner. Верни только валидный JSON с top-level полями contractVersion и rows."
_think_re = re.compile(r"<think\\b[^>]*>.*?</think>", flags=re.IGNORECASE | re.DOTALL)

def normalize_text(text: str) -> str:
    t = _think_re.sub("", text or "").strip()
    if t.startswith("```"):
        lines = t.splitlines()
        if lines: lines = lines[1:]
        if lines and lines[-1].strip() == "```": lines = lines[:-1]
        t = "\\n".join(lines).strip()
    return t

def first_json(text: str):
    s = normalize_text(text)
    try:
        obj = json.loads(s)
        if isinstance(obj, dict):
            return obj
    except Exception:
        pass
    i = s.find("{")
    j = s.rfind("}")
    if i >= 0 and j > i:
        try:
            obj = json.loads(s[i:j+1])
            if isinstance(obj, dict):
                return obj
        except Exception:
            return None
    return None

def load_model(adapter_path: Path):
    try:
        base = AutoModelForCausalLM.from_pretrained(
            BASE_MODEL_ID, torch_dtype=torch.bfloat16, device_map="auto",
            trust_remote_code=True, attn_implementation="flash_attention_2",
        )
    except Exception:
        base = AutoModelForCausalLM.from_pretrained(
            BASE_MODEL_ID, torch_dtype=torch.bfloat16, device_map="auto",
            trust_remote_code=True, attn_implementation="sdpa",
        )
    model = PeftModel.from_pretrained(base, str(adapter_path))
    try:
        model = model.merge_and_unload()
    except Exception:
        pass
    model.eval()
    return model
```

### Cell V9-07 (run predictions)

```python
OUT_DIR = V9_ROOT / "v9_event_predictions_seed42"
OUT_DIR.mkdir(parents=True, exist_ok=True)
OUT_FILE = OUT_DIR / "dataset_v9_event_sft_seed42.event_predictions.jsonl"

model = load_model(ADAPTER_DIR)
device = next(model.parameters()).device

rows = []
for idx, case in enumerate(cases, start=1):
    eval_case_id = str(case.get("eval_case_id"))
    sample_id = str(case.get("sample_id"))
    source_text = str(case.get("source_text") or "")
    slot_catalog = slot_by_sample_id.get(sample_id)

    if not isinstance(slot_catalog, dict):
        rows.append({
            "eval_case_id": eval_case_id,
            "sample_id": sample_id,
            "predicted_slot_catalog": None,
            "predicted_event_table": None,
            "raw_output_text": "",
            "error": "slot_catalog_not_found",
        })
        continue

    user_prompt = "\n\n".join([
        "Task instruction:\nСконвертируй source text в sg_v9_event_table_v1 JSON.",
        "Output contract:\nВерни только JSON c top-level полями contractVersion, rows.",
        "SlotCatalog:\n" + json.dumps(slot_catalog, ensure_ascii=False, separators=(",", ":")),
        "Source text:\n" + source_text,
    ])

    msgs = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": user_prompt},
    ]
    prompt = tokenizer.apply_chat_template(msgs, tokenize=False, add_generation_prompt=True)
    inputs = tokenizer([prompt], return_tensors="pt", truncation=True).to(device)

    with torch.inference_mode():
        out = model.generate(
            **inputs,
            max_new_tokens=512,
            do_sample=False,
            use_cache=True,
            pad_token_id=tokenizer.pad_token_id,
            eos_token_id=tokenizer.eos_token_id,
        )
    gen = out[:, inputs["input_ids"].shape[1]:]
    raw = tokenizer.batch_decode(gen, skip_special_tokens=True)[0]
    event_table = first_json(raw)

    rows.append({
        "eval_case_id": eval_case_id,
        "sample_id": sample_id,
        "predicted_slot_catalog": slot_catalog,
        "predicted_event_table": event_table,
        "raw_output_text": raw,
        "event_parse_ok": isinstance(event_table, dict),
    })

    if idx % 25 == 0:
        write_jsonl(OUT_FILE, rows)
        print(f"{idx}/{len(cases)}")

write_jsonl(OUT_FILE, rows)
print("saved:", OUT_FILE)

del model
gc.collect()
torch.cuda.empty_cache()
```

### Cell V9-08 (export zip)

```python
import zipfile

EXPORT_DIR = V9_ROOT / "sgv9_eval_export_seed42"
EXPORT_DIR.mkdir(parents=True, exist_ok=True)
ZIP_PATH = EXPORT_DIR / "sgv9_event_eval_pack_seed42.zip"

with zipfile.ZipFile(ZIP_PATH, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    zf.write(OUT_FILE, arcname=OUT_FILE.name)

print("ZIP:", ZIP_PATH)
```

Скачай `dataset_v9_event_sft_seed42.event_predictions.jsonl` (или zip) на локальную машину.

---

## 5) Локально: V9 benchmark

Положи файл предиктов сюда:

- `$RUN_ROOT/colab_export/dataset_v9_event_sft_seed42.event_predictions.jsonl`

Запуск:

```bash
cd /Users/unterlantas/Documents/XCode/shafinMultitool
python3 docs/SGv9pipeline/v9/04_run_v9_local_benchmark.py \
  --event-predictions-jsonl \
  "$RUN_ROOT/colab_export/dataset_v9_event_sft_seed42.event_predictions.jsonl"
```

Итоги:
- `.../v9_0_seed42/benchmark_results_seed42/aggregate/runs_scored.csv`
- `.../v9_0_seed42/benchmark_results_seed42/aggregate/pairwise_compare.csv`
- `.../v9_0_seed42/benchmark_results_seed42/aggregate/model_slice_summary.csv`
- `.../v9_0_seed42/benchmark_results_seed42/aggregate/scientific_report.md`
- `.../v9_0_seed42/eval_artifacts/dataset_v9_event_sft_seed42.event_slice_summary.json`
- `.../v9_0_seed42/eval_artifacts/dataset_v9_event_sft_seed42.live_vs_offline_gap.json`

---

## 6) Colab: V9 adapter -> GGUF

Логика та же, что для V8, но источник adapter другой.

### GGUF-00

```python
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
import json, shutil, tempfile, inspect

drive.mount('/content/drive')

BASE_MODEL_ID = "Qwen/Qwen3-1.7B"
WORKDIR = Path("/content/v9_export")
WORKDIR.mkdir(parents=True, exist_ok=True)

ADAPTER_DIR = Path("/content/drive/MyDrive/sgv9_eval_runs/adapters/sgv9_qwen3_event_sft_lora")
if not (ADAPTER_DIR / "adapter_model.safetensors").exists():
    raise FileNotFoundError(f"Adapter not found: {ADAPTER_DIR}")

EXPORT_DIR = Path("/content/drive/MyDrive/sgv9_gguf_export")
EXPORT_DIR.mkdir(parents=True, exist_ok=True)
print("adapter:", ADAPTER_DIR)
print("export:", EXPORT_DIR)
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
    if cfg_path.exists():
        cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
        allowed = set(inspect.signature(LoraConfig.__init__).parameters.keys())
        filtered = {k: v for k, v in cfg.items() if k in allowed}
        cfg_path.write_text(json.dumps(filtered, ensure_ascii=False, indent=2), encoding="utf-8")
    return dst

COMPAT_ADAPTER_DIR = make_compat_adapter_dir(ADAPTER_DIR)
```

### GGUF-04

```python
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer
from peft import PeftModel

MERGED_DIR = WORKDIR / "merged_hf"
MERGED_DIR.mkdir(parents=True, exist_ok=True)

dtype = torch.bfloat16 if (torch.cuda.is_available() and torch.cuda.is_bf16_supported()) else (
    torch.float16 if torch.cuda.is_available() else torch.float32
)

base = AutoModelForCausalLM.from_pretrained(
    BASE_MODEL_ID,
    torch_dtype=dtype,
    device_map="auto" if torch.cuda.is_available() else "cpu",
    trust_remote_code=True,
)
tok = AutoTokenizer.from_pretrained(BASE_MODEL_ID, trust_remote_code=True)
if tok.pad_token is None:
    tok.pad_token = tok.eos_token

peft_model = PeftModel.from_pretrained(base, str(COMPAT_ADAPTER_DIR))
merged = peft_model.merge_and_unload()
merged.save_pretrained(str(MERGED_DIR), safe_serialization=True, max_shard_size="2GB")
tok.save_pretrained(str(MERGED_DIR))
print("merged:", MERGED_DIR)
```

### GGUF-05

```python
%cd /content
!rm -rf llama.cpp
!git clone https://github.com/ggerganov/llama.cpp
%cd /content/llama.cpp
!cmake -S . -B build -DGGML_CUDA=ON
!cmake --build build -j --target llama-quantize
```

### GGUF-06

```python
%cd /content/llama.cpp
!python3 convert_hf_to_gguf.py /content/v9_export/merged_hf \
  --outfile /content/v9_export/dataset_v9_event_sft_f16.gguf \
  --outtype f16
```

### GGUF-07

```python
%cd /content/llama.cpp
!./build/bin/llama-quantize \
  /content/v9_export/dataset_v9_event_sft_f16.gguf \
  /content/v9_export/dataset_v9_event_sft_q4_k_m.gguf \
  Q4_K_M
```

### GGUF-08

```python
from pathlib import Path
import shutil, json, time

f16 = Path("/content/v9_export/dataset_v9_event_sft_f16.gguf")
q4 = Path("/content/v9_export/dataset_v9_event_sft_q4_k_m.gguf")
shutil.copy2(f16, EXPORT_DIR / f16.name)
shutil.copy2(q4, EXPORT_DIR / q4.name)

manifest = {
    "base_model": BASE_MODEL_ID,
    "adapter_dir": str(ADAPTER_DIR),
    "export_time": time.strftime("%Y-%m-%d %H:%M:%S"),
    "files": [str(EXPORT_DIR / f16.name), str(EXPORT_DIR / q4.name)],
}
(EXPORT_DIR / "gguf_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
print("done:", EXPORT_DIR)
```

---

## 7) Минимальный чек-лист выхода

1. Перегенерен `v9_event_sft_*` локально.
2. В Colab обучен `sgv9_qwen3_event_sft_lora`.
3. Сгенерен `dataset_v9_event_sft_seed42.event_predictions.jsonl`.
4. Локально отработал `04_run_v9_local_benchmark.py`.
5. Собран `dataset_v9_event_sft_q4_k_m.gguf`.
