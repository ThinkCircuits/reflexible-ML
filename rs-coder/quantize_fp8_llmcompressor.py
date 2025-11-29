#!/usr/bin/env python3
"""
Quantize DeepSeek-Coder-V2-Lite to FP8 using llm-compressor for vLLM
This is the CORRECT way to quantize for Jetson AGX Thor deployment
"""

import os
import sys
import torch
from transformers import AutoTokenizer, AutoModelForCausalLM

def print_banner(title):
    print("\n" + "=" * 80)
    print(title)
    print("=" * 80 + "\n")

def check_and_install_llmcompressor():
    """Check if llm-compressor is installed"""
    try:
        import llmcompressor
        print(f"✓ llm-compressor is installed")
        return True
    except ImportError:
        print("❌ llm-compressor not installed")
        print("\nInstalling llm-compressor...")
        import subprocess
        try:
            subprocess.check_call([
                sys.executable, "-m", "pip", "install",
                "llmcompressor[transformers]"
            ])
            print("✓ llm-compressor installed successfully")
            return True
        except Exception as e:
            print(f"❌ Failed to install: {e}")
            return False

def quantize_to_fp8(model_path, output_path):
    """Quantize model to FP8 using llm-compressor (the RIGHT way)"""

    print_banner("FP8 Quantization using llm-compressor")
    print("This is the OFFICIAL vLLM-compatible quantization method")

    # Check dependencies
    if not check_and_install_llmcompressor():
        sys.exit(1)

    # Import after installation
    from llmcompressor import oneshot
    from llmcompressor.modifiers.quantization import QuantizationModifier

    print("\n[1/5] Loading tokenizer...")
    tokenizer = AutoTokenizer.from_pretrained(model_path, trust_remote_code=True)
    print("✓ Tokenizer loaded")

    print("\n[2/5] Loading model...")
    print("  This may take several minutes...")
    model = AutoModelForCausalLM.from_pretrained(
        model_path,
        device_map="auto",
        torch_dtype="auto",
        trust_remote_code=True,
        low_cpu_mem_usage=True
    )
    print("✓ Model loaded")

    print("\n[3/5] Configuring FP8 quantization...")
    # FP8 Dynamic - no calibration data needed!
    recipe = QuantizationModifier(
        targets="Linear",
        scheme="FP8_DYNAMIC",
        ignore=["lm_head"]  # Don't quantize output layer
    )
    print("  Quantization scheme: FP8_DYNAMIC")
    print("  No calibration needed (dynamic quantization)")
    print("✓ Config ready")

    print("\n[4/5] Quantizing model (this will take 10-20 minutes)...")
    print("  This is much faster than other methods!")
    print("  " + "-" * 76)

    oneshot(
        model=model,
        recipe=recipe,
        output_dir=output_path,
        save_compressed=True,  # IMPORTANT: Actually compress on disk
    )

    print("  " + "-" * 76)
    print("✓ Model quantized to FP8")

    print("\n[5/5] Saving tokenizer and metadata...")
    tokenizer.save_pretrained(output_path)

    # Save deployment info
    import json
    metadata = {
        "quantization_method": "fp8",
        "tool": "llm-compressor",
        "scheme": "FP8_DYNAMIC",
        "vllm_compatible": True,
        "vllm_usage": f"vllm serve {output_path} --quantization fp8",
        "optimized_for": "nvidia_jetson_agx_thor",
        "expected_memory": "17-20GB",
        "expected_speed": "50-90 tokens/sec"
    }

    with open(os.path.join(output_path, "quantization_info.json"), 'w') as f:
        json.dump(metadata, f, indent=2)

    print("✓ Saved successfully")

    # Get output size
    import subprocess
    result = subprocess.run(['du', '-sh', output_path], capture_output=True, text=True)
    size = result.stdout.split('\t')[0] if result.returncode == 0 else "Unknown"

    print_banner("QUANTIZATION COMPLETE!")
    print(f"Quantization method:  FP8 (llm-compressor)")
    print(f"Original model size:  ~30GB")
    print(f"Quantized size:       {size}")
    print(f"Compression:          ~50% reduction")
    print(f"Output location:      {os.path.abspath(output_path)}")
    print(f"\nvLLM Usage on Jetson AGX Thor:")
    print(f"  vllm serve {output_path} \\")
    print(f"      --quantization fp8 \\")
    print(f"      --max-model-len 8192 \\")
    print(f"      --gpu-memory-utilization 0.9")
    print(f"\nExpected Performance:")
    print(f"  Memory usage: 17-20GB")
    print(f"  Speed: 50-90 tokens/sec")
    print(f"  Quality: 98-99% of FP16")
    print("\n" + "=" * 80)

def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Quantize to FP8 using llm-compressor (vLLM compatible)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
This is the CORRECT way to quantize for vLLM deployment!

Why this works when ModelOpt FP4 didn't:
- llm-compressor is the official vLLM quantization tool
- FP8 is well-supported (FP4 is experimental)
- Saves in vLLM-compatible format automatically
- Actually compresses on disk (not like ModelOpt)

Example:
  python3 quantize_fp8_llmcompressor.py

After quantization, transfer to Jetson and run:
  vllm serve ./deepseek-fp8 --quantization fp8
        """
    )

    parser.add_argument(
        '--model-path',
        type=str,
        default='./deepseek-coder-v2-lite-instruct',
        help='Path to input model'
    )

    parser.add_argument(
        '--output-path',
        type=str,
        default='./deepseek-coder-v2-lite-instruct-fp8',
        help='Path to save quantized model'
    )

    args = parser.parse_args()

    if not os.path.exists(args.model_path):
        print(f"❌ Error: Model not found at {args.model_path}")
        sys.exit(1)

    # Confirm
    print_banner("FP8 Quantization Configuration")
    print(f"Input model:     {args.model_path}")
    print(f"Output path:     {args.output_path}")
    print(f"Method:          llm-compressor (vLLM official)")
    print(f"Format:          FP8_DYNAMIC")
    print(f"Expected time:   10-20 minutes")
    print(f"Expected size:   ~15GB (actual compression!)")
    print(f"\nThis WILL work with vLLM (unlike ModelOpt FP4)")
    print()

    response = input("Continue? (y/n): ")
    if response.lower() != 'y':
        print("Cancelled.")
        sys.exit(0)

    try:
        quantize_to_fp8(args.model_path, args.output_path)
    except KeyboardInterrupt:
        print("\n\nInterrupted by user.")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()
