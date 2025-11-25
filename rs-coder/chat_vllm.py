#!/usr/bin/env python3
"""
Interactive chat client for vLLM server
Usage: python3 chat_vllm.py [--host HOST] [--port PORT] [--prompt-file FILE] [--system-prompt FILE]
"""

import argparse
import requests
import json
import sys
from pathlib import Path

def chat_with_vllm(host="localhost", port=8000, prompt_file=None, system_prompt_file=None):
    """Interactive chat session with vLLM server"""

    base_url = f"http://{host}:{port}"

    # Check if server is running
    try:
        health_response = requests.get(f"{base_url}/health", timeout=5)
        if health_response.status_code != 200:
            print(f"❌ vLLM server not healthy at {base_url}")
            sys.exit(1)
        print(f"✓ Connected to vLLM server at {base_url}")
    except requests.exceptions.RequestException as e:
        print(f"❌ Cannot connect to vLLM server at {base_url}")
        print(f"   Make sure vLLM is running: vllm serve ...")
        sys.exit(1)

    # Get model info
    try:
        models_response = requests.get(f"{base_url}/v1/models")
        models = models_response.json()
        model_name = models["data"][0]["id"]
        print(f"✓ Using model: {model_name}")
    except:
        model_name = "deepseek-coder-v2-lite-instruct-fp8"
        print(f"✓ Using default model name: {model_name}")

    # Initialize conversation history
    conversation_history = []

    # Load system prompt if provided
    if system_prompt_file:
        try:
            system_prompt = Path(system_prompt_file).read_text().strip()
            conversation_history.append({
                "role": "system",
                "content": system_prompt
            })
            print(f"✓ Loaded system prompt from: {system_prompt_file}")
        except Exception as e:
            print(f"❌ Error loading system prompt: {e}")
            sys.exit(1)

    # One-shot mode if prompt file is provided
    if prompt_file:
        try:
            user_prompt = Path(prompt_file).read_text().strip()
            print(f"✓ Loaded prompt from: {prompt_file}")
            print("\n" + "="*80)
            print("One-Shot Mode")
            print("="*80 + "\n")

            # Add user prompt to history
            conversation_history.append({
                "role": "user",
                "content": user_prompt
            })

            # Make request
            payload = {
                "model": model_name,
                "messages": conversation_history,
                "max_tokens": 4096,
                "temperature": 0.7,
                "stream": True
            }

            print("Response:\n")
            print("-" * 80)

            response = requests.post(
                f"{base_url}/v1/chat/completions",
                json=payload,
                stream=True,
                timeout=300
            )

            if response.status_code != 200:
                print(f"\n❌ Error: {response.status_code}")
                print(response.text)
                sys.exit(1)

            # Stream the response
            assistant_message = ""
            for line in response.iter_lines():
                if line:
                    line = line.decode('utf-8')
                    if line.startswith('data: '):
                        data = line[6:]
                        if data == '[DONE]':
                            break
                        try:
                            chunk = json.loads(data)
                            delta = chunk['choices'][0]['delta']
                            if 'content' in delta:
                                content = delta['content']
                                print(content, end="", flush=True)
                                assistant_message += content
                        except json.JSONDecodeError:
                            continue

            print("\n" + "-" * 80)
            print(f"\n✓ Response complete ({len(assistant_message)} characters)")
            return

        except FileNotFoundError:
            print(f"❌ Error: Prompt file not found: {prompt_file}")
            sys.exit(1)
        except Exception as e:
            print(f"❌ Error in one-shot mode: {e}")
            sys.exit(1)

    # Interactive mode
    print("\n" + "="*80)
    print("DeepSeek Coder Chat (FP8 Quantized)")
    print("="*80)
    if system_prompt_file:
        print(f"System prompt: {system_prompt_file}")
    print("Type 'quit', 'exit', or Ctrl+C to exit")
    print("Type 'clear' to start a new conversation")
    print("="*80 + "\n")

    while True:
        try:
            # Get user input
            user_input = input("You: ").strip()

            if not user_input:
                continue

            if user_input.lower() in ['quit', 'exit']:
                print("\nGoodbye!")
                break

            if user_input.lower() == 'clear':
                conversation_history = []
                print("\n✓ Conversation cleared\n")
                continue

            # Add user message to history
            conversation_history.append({
                "role": "user",
                "content": user_input
            })

            # Prepare request
            payload = {
                "model": model_name,
                "messages": conversation_history,
                "max_tokens": 2048,
                "temperature": 0.7,
                "stream": True
            }

            # Send request
            print("Assistant: ", end="", flush=True)

            response = requests.post(
                f"{base_url}/v1/chat/completions",
                json=payload,
                stream=True,
                timeout=120
            )

            if response.status_code != 200:
                print(f"\n❌ Error: {response.status_code}")
                print(response.text)
                continue

            # Stream the response
            assistant_message = ""
            for line in response.iter_lines():
                if line:
                    line = line.decode('utf-8')
                    if line.startswith('data: '):
                        data = line[6:]  # Remove 'data: ' prefix
                        if data == '[DONE]':
                            break
                        try:
                            chunk = json.loads(data)
                            delta = chunk['choices'][0]['delta']
                            if 'content' in delta:
                                content = delta['content']
                                print(content, end="", flush=True)
                                assistant_message += content
                        except json.JSONDecodeError:
                            continue

            print("\n")

            # Add assistant response to history
            if assistant_message:
                conversation_history.append({
                    "role": "assistant",
                    "content": assistant_message
                })

        except KeyboardInterrupt:
            print("\n\nGoodbye!")
            break
        except requests.exceptions.Timeout:
            print("\n❌ Request timed out. The model might be overloaded.")
        except requests.exceptions.RequestException as e:
            print(f"\n❌ Request error: {e}")
        except Exception as e:
            print(f"\n❌ Unexpected error: {e}")

def main():
    parser = argparse.ArgumentParser(
        description="Interactive chat with vLLM server or one-shot prompt execution",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Interactive mode (default)
  python3 chat_vllm.py

  # One-shot mode with prompt from file
  python3 chat_vllm.py --prompt-file prompt.txt

  # One-shot mode with system prompt
  python3 chat_vllm.py --prompt-file prompt.txt --system-prompt system.txt

  # Interactive mode with system prompt
  python3 chat_vllm.py --system-prompt system.txt

  # Connect to remote vLLM server
  python3 chat_vllm.py --host 192.168.1.100 --prompt-file prompt.txt

  # Use custom port
  python3 chat_vllm.py --port 8080

  # Connect to Jetson AGX Thor with one-shot
  python3 chat_vllm.py --host jetson-thor.local --prompt-file code_review.txt
        """
    )

    parser.add_argument(
        '--host',
        type=str,
        default='localhost',
        help='vLLM server host (default: localhost)'
    )

    parser.add_argument(
        '--port',
        type=int,
        default=8000,
        help='vLLM server port (default: 8000)'
    )

    parser.add_argument(
        '--prompt-file',
        type=str,
        help='File containing the prompt (enables one-shot mode)'
    )

    parser.add_argument(
        '--system-prompt',
        type=str,
        help='File containing the system prompt (optional)'
    )

    args = parser.parse_args()

    chat_with_vllm(args.host, args.port, args.prompt_file, args.system_prompt)

if __name__ == "__main__":
    main()
