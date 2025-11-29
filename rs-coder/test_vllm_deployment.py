#!/usr/bin/env python3
"""
Test script for vLLM deployment on Jetson
Tests the deployed vLLM server with various prompts and measures performance
"""

import argparse
import time
import json
import sys
from typing import List, Dict

try:
    from openai import OpenAI
except ImportError:
    print("❌ OpenAI package not installed")
    print("Install with: pip install openai")
    sys.exit(1)


class Colors:
    """ANSI color codes"""
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    END = '\033[0m'
    BOLD = '\033[1m'


def print_header(text: str):
    """Print a formatted header"""
    print(f"\n{Colors.BLUE}{'=' * 80}{Colors.END}")
    print(f"{Colors.BLUE}{text}{Colors.END}")
    print(f"{Colors.BLUE}{'=' * 80}{Colors.END}\n")


def print_status(text: str):
    """Print a status message"""
    print(f"{Colors.GREEN}[✓]{Colors.END} {text}")


def print_error(text: str):
    """Print an error message"""
    print(f"{Colors.RED}[✗]{Colors.END} {text}")


def print_info(text: str):
    """Print an info message"""
    print(f"{Colors.YELLOW}[i]{Colors.END} {text}")


def test_health(base_url: str) -> bool:
    """Test server health endpoint"""
    import requests

    print_info("Testing server health...")
    health_url = base_url.replace('/v1', '/health')

    try:
        response = requests.get(health_url, timeout=5)
        if response.status_code == 200:
            print_status("Server is healthy")
            return True
        else:
            print_error(f"Health check failed: {response.status_code}")
            return False
    except Exception as e:
        print_error(f"Cannot connect to server: {e}")
        return False


def test_completion(client: OpenAI, model: str, prompt: str, max_tokens: int = 256) -> Dict:
    """Test a single completion"""

    start_time = time.time()

    try:
        response = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "user", "content": prompt}
            ],
            max_tokens=max_tokens,
            temperature=0.7,
        )

        end_time = time.time()
        duration = end_time - start_time

        completion = response.choices[0].message.content
        tokens_generated = len(completion.split())  # Rough estimate
        tokens_per_second = tokens_generated / duration if duration > 0 else 0

        return {
            "success": True,
            "completion": completion,
            "duration": duration,
            "tokens": tokens_generated,
            "tokens_per_second": tokens_per_second,
        }

    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }


def run_tests(base_url: str, model: str):
    """Run a suite of tests"""

    print_header("vLLM Deployment Test Suite")

    # Initialize client
    print_info(f"Connecting to: {base_url}")
    client = OpenAI(
        base_url=base_url,
        api_key="token"  # vLLM doesn't require a real key
    )

    # Test health
    if not test_health(base_url):
        print_error("Server health check failed. Is the server running?")
        return

    # Define test prompts
    test_cases = [
        {
            "name": "Simple greeting",
            "prompt": "Hello! How are you?",
            "max_tokens": 50
        },
        {
            "name": "Code generation - Fibonacci",
            "prompt": "Write a Python function to calculate the nth Fibonacci number using dynamic programming:",
            "max_tokens": 256
        },
        {
            "name": "Code explanation",
            "prompt": "Explain what a binary search tree is and when to use it:",
            "max_tokens": 200
        },
        {
            "name": "Code debugging",
            "prompt": "Find and fix the bug in this code:\n```python\ndef factorial(n):\n    if n = 0:\n        return 1\n    return n * factorial(n-1)\n```",
            "max_tokens": 150
        },
        {
            "name": "Algorithm complexity",
            "prompt": "What is the time complexity of bubble sort and why?",
            "max_tokens": 150
        }
    ]

    # Run tests
    results = []

    print_header("Running Test Cases")

    for i, test_case in enumerate(test_cases, 1):
        print(f"\n{Colors.BOLD}Test {i}/{len(test_cases)}: {test_case['name']}{Colors.END}")
        print(f"Prompt: {test_case['prompt'][:80]}...")

        result = test_completion(
            client,
            model,
            test_case['prompt'],
            test_case['max_tokens']
        )

        if result['success']:
            print_status(f"Completed in {result['duration']:.2f}s")
            print(f"  Tokens: ~{result['tokens']}")
            print(f"  Speed: ~{result['tokens_per_second']:.1f} tokens/sec")
            print(f"\n  Response:\n  {'-' * 76}")
            # Print first 200 chars of response
            response_preview = result['completion'][:200]
            if len(result['completion']) > 200:
                response_preview += "..."
            for line in response_preview.split('\n'):
                print(f"  {line}")
            print(f"  {'-' * 76}")
        else:
            print_error(f"Failed: {result['error']}")

        results.append({
            "test": test_case['name'],
            **result
        })

        # Small delay between tests
        time.sleep(1)

    # Print summary
    print_header("Test Summary")

    successful = sum(1 for r in results if r['success'])
    total = len(results)

    print(f"Tests passed: {successful}/{total}")

    if successful > 0:
        avg_duration = sum(r['duration'] for r in results if r['success']) / successful
        avg_tokens = sum(r['tokens'] for r in results if r['success']) / successful
        avg_speed = sum(r['tokens_per_second'] for r in results if r['success']) / successful

        print(f"\nAverage performance:")
        print(f"  Duration: {avg_duration:.2f}s")
        print(f"  Tokens: ~{avg_tokens:.0f}")
        print(f"  Speed: ~{avg_speed:.1f} tokens/sec")

    # Save detailed results
    output_file = f"test_results_{int(time.time())}.json"
    with open(output_file, 'w') as f:
        json.dump(results, f, indent=2)

    print_status(f"Detailed results saved to: {output_file}")

    print(f"\n{Colors.GREEN}{'=' * 80}{Colors.END}")
    if successful == total:
        print(f"{Colors.GREEN}All tests passed! ✓{Colors.END}")
    else:
        print(f"{Colors.YELLOW}Some tests failed. Check the output above.{Colors.END}")
    print(f"{Colors.GREEN}{'=' * 80}{Colors.END}\n")


def interactive_mode(base_url: str, model: str):
    """Interactive chat mode"""

    print_header("Interactive Chat Mode")
    print_info("Type your prompts below. Type 'exit' or 'quit' to end.\n")

    client = OpenAI(
        base_url=base_url,
        api_key="token"
    )

    while True:
        try:
            prompt = input(f"{Colors.BOLD}You: {Colors.END}")

            if prompt.lower() in ['exit', 'quit', 'q']:
                print("\nGoodbye!")
                break

            if not prompt.strip():
                continue

            print(f"\n{Colors.BLUE}Assistant: {Colors.END}", end='', flush=True)

            start_time = time.time()

            response = client.chat.completions.create(
                model=model,
                messages=[{"role": "user", "content": prompt}],
                max_tokens=512,
                temperature=0.7,
            )

            duration = time.time() - start_time
            completion = response.choices[0].message.content

            print(completion)
            print(f"\n{Colors.YELLOW}({duration:.2f}s){Colors.END}\n")

        except KeyboardInterrupt:
            print("\n\nGoodbye!")
            break
        except Exception as e:
            print_error(f"Error: {e}\n")


def main():
    parser = argparse.ArgumentParser(
        description="Test vLLM deployment on Jetson",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Run test suite
  python3 test_vllm_deployment.py

  # Test server on different port
  python3 test_vllm_deployment.py --port 8080

  # Interactive chat mode
  python3 test_vllm_deployment.py --interactive

  # Test remote server
  python3 test_vllm_deployment.py --host 192.168.1.100
        """
    )

    parser.add_argument(
        '--host',
        type=str,
        default='localhost',
        help='Server host (default: localhost)'
    )

    parser.add_argument(
        '--port',
        type=int,
        default=8000,
        help='Server port (default: 8000)'
    )

    parser.add_argument(
        '--model',
        type=str,
        default='deepseek-coder-v2-lite-instruct',
        help='Model name (default: deepseek-coder-v2-lite-instruct)'
    )

    parser.add_argument(
        '--interactive',
        action='store_true',
        help='Run in interactive chat mode'
    )

    args = parser.parse_args()

    base_url = f"http://{args.host}:{args.port}/v1"

    if args.interactive:
        interactive_mode(base_url, args.model)
    else:
        run_tests(base_url, args.model)


if __name__ == "__main__":
    main()
