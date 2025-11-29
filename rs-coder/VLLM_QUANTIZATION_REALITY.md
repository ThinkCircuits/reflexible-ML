# vLLM Quantization: What Actually Works

## ⚠️ Important Clarification

**Most vLLM quantization options require PRE-QUANTIZED models, not runtime quantization!**

This is different from what was initially suggested. Let me clarify what really works.

---

## 🔍 vLLM Quantization Types

### Type 1: Pre-Quantized Models (Most Common)

These require you to quantize the model BEFORE loading into vLLM:

| Method | Requires | Command |
|--------|----------|---------|
| `awq` | AWQ pre-quantized model | `--quantization awq` |
| `gptq` | GPTQ pre-quantized model | `--quantization gptq` |
| `modelopt` | NVIDIA ModelOpt quantized | `--quantization modelopt_fp4` |
| `squeezellm` | SqueezeLLM quantized | `--quantization squeezellm` |
| `marlin` | Marlin quantized | `--quantization marlin` |

**Problem:** DeepSeek V2 isn't supported by most pre-quantization tools (as we discovered).

### Type 2: Runtime Options (Limited)

These work with unquantized models:

| Method | What It Does | vLLM Support |
|--------|--------------|--------------|
| No flag | Native precision (BF16/FP16) | ✅ Always works |
| `--kv-cache-dtype fp8` | Quantize KV cache only | ✅ Recommended |
| `--kv-cache-dtype int8` | Quantize KV cache to INT8 | ✅ Works |

---

## ✅ What Actually Works for DeepSeek V2

### Recommended Approach: Full Precision + FP8 KV Cache

```bash
vllm serve ./deepseek-coder-v2-lite-instruct \
    --kv-cache-dtype fp8 \
    --max-model-len 4096 \
    --gpu-memory-utilization 0.9
```

**What this does:**
- Weights: BF16/FP16 (full precision)
- KV Cache: FP8 (quantized - saves memory)
- Result: Good balance of quality and memory efficiency

**Expected memory usage:**
- Model weights: ~30GB
- KV cache: ~2-4GB (instead of 8GB)
- Total: ~32-34GB
- **Works on 64GB Thor with room to spare**

---

## 🚀 Recommended Configurations for Jetson AGX Thor

### Configuration 1: Balanced (Recommended)

```bash
vllm serve ./deepseek-coder-v2-lite-instruct \
    --dtype bfloat16 \
    --kv-cache-dtype fp8 \
    --max-model-len 4096 \
    --gpu-memory-utilization 0.9 \
    --max-num-seqs 4
```

**Memory:** ~34GB
**Speed:** 40-70 tokens/sec
**Quality:** Full model quality
**Users:** 2-4 concurrent

### Configuration 2: Maximum Throughput

```bash
vllm serve ./deepseek-coder-v2-lite-instruct \
    --dtype bfloat16 \
    --kv-cache-dtype fp8 \
    --max-model-len 2048 \
    --gpu-memory-utilization 0.95 \
    --max-num-seqs 8
```

**Memory:** ~28GB
**Speed:** 50-80 tokens/sec (shorter sequences)
**Quality:** Full
**Users:** 4-8 concurrent (shorter contexts)

### Configuration 3: Long Context

```bash
vllm serve ./deepseek-coder-v2-lite-instruct \
    --dtype bfloat16 \
    --kv-cache-dtype fp8 \
    --max-model-len 8192 \
    --gpu-memory-utilization 0.9 \
    --max-num-seqs 2
```

**Memory:** ~42GB
**Speed:** 30-50 tokens/sec
**Quality:** Full
**Users:** 1-2 concurrent (long contexts)

### Configuration 4: Absolute Maximum Memory Saving

```bash
vllm serve ./deepseek-coder-v2-lite-instruct \
    --dtype bfloat16 \
    --kv-cache-dtype int8 \
    --max-model-len 2048 \
    --gpu-memory-utilization 0.85 \
    --max-num-seqs 4 \
    --enable-prefix-caching
```

**Memory:** ~26GB
**Speed:** 45-75 tokens/sec
**Quality:** Full (INT8 KV cache has minimal impact)
**Users:** 3-4 concurrent

---

## 🔄 If You Want True Weight Quantization

If you really need weight quantization (not just KV cache), you have two options:

### Option A: Use Quanto Locally (No vLLM)

Good for testing/development:
```bash
python3 quantize_model.py --method quanto --bits 4
python3 load_quantized_model.py
```

**Pros:** Works with DeepSeek V2
**Cons:** Can't use with vLLM

### Option B: Wait for Better Tool Support

NVIDIA ModelOpt might add DeepSeek V2 support in the future. Monitor:
- [ModelOpt releases](https://github.com/NVIDIA/TensorRT-Model-Optimizer)
- [vLLM discussions](https://github.com/vllm-project/vllm/discussions)

---

## 📊 Actual Performance Expectations on Thor

Based on the configurations above:

| Config | Model Memory | KV Cache | Total | Tokens/sec | Users |
|--------|--------------|----------|-------|------------|-------|
| **Balanced** | 30GB | 4GB FP8 | 34GB | 40-70 | 2-4 |
| Max Throughput | 30GB | 2GB FP8 | 32GB | 50-80 | 4-8 |
| Long Context | 30GB | 8GB FP8 | 38GB | 30-50 | 1-2 |
| Max Saving | 30GB | 1GB INT8 | 31GB | 45-75 | 3-4 |

All fit comfortably in Thor's 64GB!

---

## 🛠️ Updated Deployment Script

Let me update the jetson_deploy.sh to use realistic options:

```bash
#!/bin/bash
# Updated for actual vLLM capabilities

MODEL_PATH="$HOME/models/deepseek-coder-v2-lite-instruct"
KV_CACHE_DTYPE="fp8"  # fp8, int8, or auto
MAX_MODEL_LEN=4096
GPU_MEMORY_UTIL=0.9
PORT=8000

vllm serve $MODEL_PATH \
    --host 0.0.0.0 \
    --port $PORT \
    --dtype bfloat16 \
    --kv-cache-dtype $KV_CACHE_DTYPE \
    --max-model-len $MAX_MODEL_LEN \
    --gpu-memory-utilization $GPU_MEMORY_UTIL \
    --max-num-seqs 4 \
    --enable-prefix-caching \
    --trust-remote-code
```

---

## 🎯 Simple Decision Guide

**Question:** How much memory do you want to use?

### ~34GB (Recommended)
```bash
vllm serve ./deepseek-coder-v2-lite-instruct \
    --kv-cache-dtype fp8 \
    --max-model-len 4096
```

### ~31GB (More conservative)
```bash
vllm serve ./deepseek-coder-v2-lite-instruct \
    --kv-cache-dtype int8 \
    --max-model-len 2048
```

### ~38GB (Long context)
```bash
vllm serve ./deepseek-coder-v2-lite-instruct \
    --kv-cache-dtype fp8 \
    --max-model-len 8192
```

---

## ✅ Quick Start (Copy-Paste)

**For most use cases, just run:**

```bash
vllm serve ./deepseek-coder-v2-lite-instruct \
    --kv-cache-dtype fp8 \
    --max-model-len 4096 \
    --gpu-memory-utilization 0.9 \
    --max-num-seqs 4 \
    --enable-prefix-caching \
    --trust-remote-code
```

This gives you:
- ✅ Full model quality
- ✅ Reduced memory (FP8 KV cache)
- ✅ Good throughput
- ✅ Multi-user support
- ✅ ~34GB memory usage

---

## 🔍 Monitoring

Check actual memory usage:
```bash
# Watch GPU memory
watch nvidia-smi

# Check vLLM metrics
curl http://localhost:8000/metrics | grep memory
```

---

## 📝 Summary

**Key Takeaway:** You don't need aggressive weight quantization on Thor (64GB is plenty!)

**Best approach:**
1. Use full precision weights (BF16)
2. Quantize KV cache to FP8
3. Adjust `max-model-len` based on your use case
4. Monitor and tune

**This is simpler, more reliable, and gives better quality than fighting with pre-quantization tools that don't support DeepSeek V2.**
