# DeepSeek-Coder-V2-Lite Jetson Deployment Package

Complete deployment package for running DeepSeek-Coder-V2-Lite-Instruct on Jetson AGX Thor with vLLM.

## 🎯 What This Package Does

This package provides everything you need to deploy a production-ready LLM on Jetson AGX Thor:
- ✅ **Automated setup** for Jetson environment
- ✅ **Runtime quantization** with vLLM (FP8/INT8)
- ✅ **No pre-quantization needed** - works with original model
- ✅ **Complete testing suite**
- ✅ **Production-ready deployment scripts**

## 📦 Package Contents

### 🚀 Deployment Scripts
- **`transfer_to_jetson.sh`** - Automated transfer to Jetson
- **`jetson_setup.sh`** - One-time Jetson environment setup
- **`jetson_deploy.sh`** - Deploy and run vLLM server
- **`test_vllm_deployment.py`** - Comprehensive testing suite

### 📚 Documentation
- **`JETSON_DEPLOYMENT_GUIDE.md`** - Complete deployment guide
- **`QUANTIZATION_GUIDE.md`** - Quantization options explained
- **`README.md`** - This file

### 🧪 Experimental Scripts
- **`quantize_model.py`** - Multi-method quantization (AWQ/GPTQ/Quanto)
- **`test_vllm_quant.py`** - Local vLLM testing
- **`load_quantized_model.py`** - Load Quanto models

### 📁 Model
- **`deepseek-coder-v2-lite-instruct/`** - The base model (~30GB)

---

## ⚡ Quick Start (3 Commands)

### Method 1: Automated Transfer (Recommended)

```bash
# 1. Transfer everything to Jetson
./transfer_to_jetson.sh <jetson-ip>

# 2. SSH to Jetson and run setup
ssh jetson@<jetson-ip>
cd ~/scripts && bash jetson_setup.sh

# 3. Deploy
bash jetson_deploy.sh
```

### Method 2: Manual Steps

```bash
# 1. Transfer model
scp -r ./deepseek-coder-v2-lite-instruct jetson@<jetson-ip>:~/models/

# 2. Transfer scripts
scp jetson_*.sh test_vllm_deployment.py jetson@<jetson-ip>:~/

# 3. SSH and deploy
ssh jetson@<jetson-ip>
bash jetson_setup.sh
bash jetson_deploy.sh
```

---

## 📖 Documentation

### For First-Time Users
1. Start with **`JETSON_DEPLOYMENT_GUIDE.md`** - Complete walkthrough
2. Read **`QUANTIZATION_GUIDE.md`** - Understanding quantization options

### Quick Reference

| Task | Command |
|------|---------|
| Transfer to Jetson | `./transfer_to_jetson.sh <ip>` |
| Setup Jetson | `bash jetson_setup.sh` |
| Deploy with FP8 | `bash jetson_deploy.sh` |
| Deploy with INT8 | `bash jetson_deploy.sh --quantization int8_wo` |
| Test deployment | `python3 test_vllm_deployment.py` |
| Interactive chat | `python3 test_vllm_deployment.py --interactive` |

---

## 🔧 Deployment Options

### Runtime Quantization (Recommended) ⭐

**Why this is recommended:**
- No pre-processing needed
- Works with DeepSeek V2 architecture
- Flexible - change quantization on-the-fly
- Saves disk space

**How to use:**
```bash
# FP8 (best balance)
bash jetson_deploy.sh --quantization fp8

# INT8 (more conservative)
bash jetson_deploy.sh --quantization int8_wo

# No quantization (if you have 64GB RAM)
bash jetson_deploy.sh --quantization none
```

### Pre-Quantization (Experimental)

**Note:** Pre-quantization has compatibility issues with DeepSeek V2.

If you want to experiment:
```bash
# Try llm-compressor (vLLM's tool)
python3 quantize_model.py --method awq --bits 4

# Or use Quanto (no vLLM support)
python3 quantize_model.py --method quanto --bits 4
```

---

## 🎯 Performance Guide

### Jetson AGX Thor (64GB)

| Quantization | Memory | Speed | Quality | Recommendation |
|--------------|--------|-------|---------|----------------|
| **FP8** | ~10GB | Very Fast | Excellent | ⭐ Default |
| **INT8** | ~14GB | Fast | Excellent | Alternative |
| **FP16** | ~24GB | Medium | Perfect | If RAM available |

### Expected Performance

**FP8 Quantization (Recommended):**
- Token generation: 50-100 tokens/sec
- First token: ~200-500ms
- Memory usage: ~10-14GB
- Concurrent requests: 2-4

---

## 🧪 Testing

### Health Check
```bash
curl http://<jetson-ip>:8000/health
```

### Run Test Suite
```bash
python3 test_vllm_deployment.py --host <jetson-ip>
```

### Interactive Chat
```bash
python3 test_vllm_deployment.py --interactive
```

### Python Example
```python
from openai import OpenAI

client = OpenAI(
    base_url="http://<jetson-ip>:8000/v1",
    api_key="token"
)

response = client.chat.completions.create(
    model="deepseek-coder-v2-lite-instruct",
    messages=[{"role": "user", "content": "Hello!"}]
)

print(response.choices[0].message.content)
```

---

## 📊 File Structure

```
JetsonSetup/
├── README.md                          # This file
├── JETSON_DEPLOYMENT_GUIDE.md         # Complete deployment guide
├── QUANTIZATION_GUIDE.md              # Quantization explained
│
├── transfer_to_jetson.sh              # Automated transfer script
├── jetson_setup.sh                    # Jetson environment setup
├── jetson_deploy.sh                   # Deploy vLLM server
├── test_vllm_deployment.py            # Testing suite
│
├── quantize_model.py                  # Experimental quantization
├── test_vllm_quant.py                 # Local testing
├── load_quantized_model.py            # Quanto model loader
│
└── deepseek-coder-v2-lite-instruct/   # The model
    ├── config.json
    ├── model*.safetensors
    ├── tokenizer*
    └── modeling_deepseek.py
```

---

## 🐛 Troubleshooting

### Transfer Issues

**Problem:** Transfer is slow or failing
```bash
# Use rsync for resumable transfer
rsync -avz --progress ./deepseek-coder-v2-lite-instruct jetson@<ip>:~/models/
```

### Deployment Issues

**Problem:** Out of memory
```bash
# Use more aggressive quantization
bash jetson_deploy.sh --quantization fp8 --max-len 2048
```

**Problem:** vLLM won't install
```bash
# Build from source
git clone https://github.com/vllm-project/vllm.git
cd vllm && pip3 install -e .
```

### Testing Issues

**Problem:** Can't connect to server
```bash
# Check if server is running
ssh jetson@<ip> 'ps aux | grep vllm'

# Check port is accessible
curl http://<jetson-ip>:8000/health
```

---

## 📚 Additional Resources

- [vLLM Documentation](https://docs.vllm.ai/)
- [DeepSeek-Coder](https://github.com/deepseek-ai/DeepSeek-Coder)
- [Jetson Forums](https://forums.developer.nvidia.com/c/agx-autonomous-machines/jetson-embedded-systems/)
- [NVIDIA Jetson](https://developer.nvidia.com/embedded/jetson-agx-thor)

---

## ✅ Deployment Checklist

### Pre-Deployment
- [ ] Model downloaded (~30GB)
- [ ] Jetson AGX Thor accessible via SSH
- [ ] At least 35GB free space on Jetson
- [ ] Network connection stable

### Setup
- [ ] Files transferred to Jetson
- [ ] `jetson_setup.sh` completed successfully
- [ ] PyTorch installed and CUDA working
- [ ] vLLM installed

### Deployment
- [ ] vLLM server starts without errors
- [ ] Health check passes (`/health` endpoint)
- [ ] Test suite passes
- [ ] Performance is acceptable

### Production (Optional)
- [ ] Systemd service configured
- [ ] Monitoring set up
- [ ] Backups configured
- [ ] Load balancing (if multiple Jetsons)

---

## 🎓 Learning Path

1. **Start here:** Run the Quick Start commands
2. **Understand:** Read `JETSON_DEPLOYMENT_GUIDE.md`
3. **Optimize:** Read `QUANTIZATION_GUIDE.md`
4. **Test:** Run the test suite
5. **Production:** Configure as systemd service

---

## 🤝 Support

### Getting Help

1. Check the documentation in this package
2. Review the troubleshooting sections
3. Search [vLLM discussions](https://github.com/vllm-project/vllm/discussions)
4. Ask on [Jetson Forums](https://forums.developer.nvidia.com/)

### Reporting Issues

When reporting issues, include:
- Jetson model and JetPack version
- Error messages and logs
- Steps to reproduce
- Output of `nvidia-smi`

---

## 🎉 Success Criteria

Your deployment is successful when:

1. ✅ vLLM server starts without errors
2. ✅ Health check returns `{"status":"ok"}`
3. ✅ Test suite passes all tests
4. ✅ Token generation is 50+ tokens/sec
5. ✅ Memory usage is stable
6. ✅ You can interact via OpenAI API

---

## 📝 Next Steps After Deployment

### Development
- Build a web UI (Gradio/Streamlit)
- Integrate with your application
- Add custom prompts and templates

### Production
- Set up monitoring and alerts
- Configure auto-restart on failure
- Implement request queuing
- Add API authentication

### Optimization
- Tune quantization settings
- Adjust memory allocation
- Benchmark different configurations
- Profile performance bottlenecks

---

## 🚀 Ready to Deploy?

Start with the Quick Start section above, and refer to the detailed guides as needed.

**Happy deploying!** 🎊
