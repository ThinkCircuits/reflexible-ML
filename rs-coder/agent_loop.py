#!/usr/bin/env python3
"""
ReflexScript Agent Loop - Iteratively generates syntactically correct ReflexScript code

This script:
1. Calls vLLM to generate ReflexScript code
2. Extracts code from markdown blocks
3. Runs reflexc compiler to check for errors
4. If errors, feeds them back to the LLM for another attempt
5. Loops until success or max iterations

Usage:
    python3 agent_loop.py --system-prompt prompts/reflexscript_agent_system_prompt.md \
                          --prompt rs-coder/examples/example_prompt.txt \
                          --output generated.rfx
"""

import argparse
import json
import os
import platform
import re
import subprocess
import sys
from pathlib import Path

import requests


# ============================================================================
# Compiler Detection
# ============================================================================

def detect_reflexc_path():
    """Auto-detect reflexc path based on platform architecture."""
    arch = platform.machine().lower()

    if arch in ('aarch64', 'arm64'):
        # ARM64 (Jetson, etc.)
        path = Path("/home/thinkcircuits/Reflexible/Reflexscript/build/reflexc")
    else:
        # x86_64
        path = Path("/home/thinkcircuits/Reflexible/reflexible-platforms/tools/reflexc/bin/reflexc")

    if path.exists() and os.access(path, os.X_OK):
        return str(path)

    # Try to find reflexc in PATH
    result = subprocess.run(["which", "reflexc"], capture_output=True, text=True)
    if result.returncode == 0:
        return result.stdout.strip()

    return None


# ============================================================================
# vLLM API Functions
# ============================================================================

def check_vllm_health(host, port):
    """Check if vLLM server is healthy."""
    try:
        response = requests.get(f"http://{host}:{port}/health", timeout=5)
        return response.status_code == 200
    except requests.exceptions.RequestException:
        return False


def get_model_name(host, port):
    """Get the model name from vLLM server."""
    try:
        response = requests.get(f"http://{host}:{port}/v1/models", timeout=10)
        if response.status_code == 200:
            models = response.json()
            if models.get("data"):
                return models["data"][0]["id"]
    except requests.exceptions.RequestException:
        pass

    # Default fallback
    return "deepseek-coder-v2-lite-instruct-fp8"


def call_vllm(messages, host, port, model, temperature, max_tokens=4096):
    """Call vLLM API and return the response text."""
    base_url = f"http://{host}:{port}"

    payload = {
        "model": model,
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": temperature,
        "stream": True
    }

    try:
        response = requests.post(
            f"{base_url}/v1/chat/completions",
            json=payload,
            stream=True,
            timeout=300
        )

        if response.status_code != 200:
            print(f"Error: vLLM returned status {response.status_code}")
            print(response.text)
            return None

        # Stream and accumulate response
        full_response = ""
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
                            full_response += content
                    except json.JSONDecodeError:
                        continue

        print()  # Newline after streaming
        return full_response

    except requests.exceptions.Timeout:
        print("Error: vLLM request timed out")
        return None
    except requests.exceptions.RequestException as e:
        print(f"Error: vLLM request failed: {e}")
        return None


# ============================================================================
# Code Extraction
# ============================================================================

def extract_code_from_response(response):
    """Extract ReflexScript code from LLM response.

    Tries in order:
    1. ```reflexscript ... ``` blocks
    2. Generic ``` ... ``` blocks
    3. Look for 'reflex ' keyword and extract to matching '}'
    """
    if not response:
        return None

    # Try to find ```reflexscript block
    pattern = r'```reflexscript\s*\n(.*?)```'
    match = re.search(pattern, response, re.DOTALL)
    if match:
        return match.group(1).strip()

    # Try generic code block
    pattern = r'```\s*\n(.*?)```'
    match = re.search(pattern, response, re.DOTALL)
    if match:
        code = match.group(1).strip()
        # Verify it looks like ReflexScript
        if 'reflex ' in code:
            return code

    # Look for reflex keyword directly
    if 'reflex ' in response:
        start = response.find('reflex ')
        # Find the matching closing brace
        brace_count = 0
        in_code = False
        end = start

        for i, char in enumerate(response[start:], start):
            if char == '{':
                brace_count += 1
                in_code = True
            elif char == '}':
                brace_count -= 1
                if in_code and brace_count == 0:
                    end = i + 1
                    break

        if end > start:
            return response[start:end].strip()

    return None


# ============================================================================
# Compiler Integration
# ============================================================================

def write_rfx_file(code, output_path):
    """Write code to .rfx file."""
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(code)


def run_reflexc(rfx_path, reflexc_path):
    """Run reflexc compiler with --check flag.

    Returns:
        (success: bool, output: str)
    """
    try:
        result = subprocess.run(
            [reflexc_path, "--check", rfx_path],
            capture_output=True,
            text=True,
            timeout=30
        )

        # Combine stdout and stderr
        output = result.stdout + result.stderr
        success = result.returncode == 0

        return success, output.strip()

    except subprocess.TimeoutExpired:
        return False, "Error: reflexc timed out"
    except FileNotFoundError:
        return False, f"Error: reflexc not found at {reflexc_path}"
    except Exception as e:
        return False, f"Error running reflexc: {e}"


# ============================================================================
# Error Parsing
# ============================================================================

def parse_errors(compiler_output):
    """Parse reflexc compiler output into structured errors.

    Format: FILE:LINE:COLUMN: ERROR_TYPE: MESSAGE
    May include 'Suggestion:' lines.
    """
    errors = []
    lines = compiler_output.strip().split('\n')
    current_error = None

    # Pattern for error line: FILE:LINE:COLUMN: TYPE: MESSAGE
    error_pattern = re.compile(r'^(.+):(\d+):(\d+):\s*(\w+(?:\s+\w+)*):\s*(.+)$')

    for line in lines:
        match = error_pattern.match(line)
        if match:
            if current_error:
                errors.append(current_error)
            current_error = {
                "file": match.group(1),
                "line": int(match.group(2)),
                "column": int(match.group(3)),
                "type": match.group(4),
                "message": match.group(5),
                "suggestion": None
            }
        elif line.strip().startswith("Suggestion:") and current_error:
            current_error["suggestion"] = line.split("Suggestion:", 1)[1].strip()
        elif line.strip() and current_error and not line.startswith(' '):
            # Continuation of error message
            current_error["message"] += " " + line.strip()

    if current_error:
        errors.append(current_error)

    return errors


def parse_and_categorize_errors(raw_output):
    """Parse compiler output and categorize errors exactly like Reflex-langchain.

    This mirrors the _parse_compiler_output method from enhanced_tools.py.
    """
    lines = raw_output.split("\n")
    syntax_errors = []
    type_errors = []
    linker_errors = []
    warnings = []
    other_messages = []

    for line in lines:
        if not line.strip():
            continue

        line_lower = line.lower()

        # Skip informational/success messages
        if any(pattern in line_lower for pattern in [
            "safety analysis results", "safety properties: verified",
            "estimated wcet", "estimated stack", "estimated state",
            "max loop depth", "max stack depth", "execution rate",
            "platform:", "toolchain:", "compilation complete", "build successful",
            "phase:", "checking:", "processing:"
        ]):
            other_messages.append(line)
            continue

        # Syntax and parse errors
        if any(pattern in line_lower for pattern in [
            "error:", "syntax error", "parse error", "expected", "missing",
            "unexpected token", "invalid syntax", "malformed"
        ]):
            syntax_errors.append(line)
        # Type and semantic errors
        elif any(pattern in line_lower for pattern in [
            "type error", "undefined", "undeclared", "incompatible types",
            "type mismatch", "cannot convert", "semantic error", "analysis error"
        ]):
            type_errors.append(line)
        # Linker errors
        elif any(pattern in line_lower for pattern in [
            "undefined reference", "ld:", "cannot find -l", "unresolved symbol",
            "linker error", "link error"
        ]):
            linker_errors.append(line)
        # Warnings
        elif any(pattern in line_lower for pattern in [
            "warning:", "deprecated", "unused"
        ]):
            warnings.append(line)
        # Other
        elif any(pattern in line_lower for pattern in [
            "failed", "error", "exception", "abort", "fatal"
        ]) and "cannot open file" not in line_lower:
            other_messages.append(line)
        else:
            other_messages.append(line)

    return syntax_errors, type_errors, linker_errors, warnings, other_messages


def format_error_feedback_for_history(code, errors, raw_output, simple_mode=False):
    """Format error feedback for the LLM.

    Args:
        code: The code that failed
        errors: Parsed error list
        raw_output: Raw compiler output
        simple_mode: If True, use minimal prompts for smaller models like DeepSeek-Coder
    """
    if simple_mode:
        # Simple, direct format for smaller/dumber models
        # Focus on showing the exact errors and the exact fixes needed
        lines = code.split('\n')

        output = []
        output.append("COMPILATION ERROR. Fix the code below.\n")
        output.append("ERRORS:")

        # Show first 5 errors with line context
        for e in errors[:5]:
            line_num = e['line']
            output.append(f"  Line {line_num}: {e['message']}")
            if e.get('suggestion'):
                output.append(f"    FIX: {e['suggestion']}")
            # Show the problematic line
            if 0 < line_num <= len(lines):
                output.append(f"    CODE: {lines[line_num-1].strip()}")

        if len(errors) > 5:
            output.append(f"  ... {len(errors) - 5} more errors")

        output.append("\nVALID UNITS: [m] [rad] [s] [ms] [Hz] [mps] [radps] [deg] [degC] [mm] [cm] [kg]")
        output.append("INVALID: [Nm] [rad/s] [m/s] - NO slash in units\n")

        output.append("YOUR CODE:")
        output.append("```reflexscript")
        output.append(code)
        output.append("```")
        output.append("\nFix the errors and output the complete corrected code in a ```reflexscript block.")

        return "\n".join(output)

    # Full Reflex-langchain style format for capable models
    syntax_errors, type_errors, linker_errors, warnings, other_messages = \
        parse_and_categorize_errors(raw_output)

    total_errors = len(syntax_errors) + len(type_errors) + len(linker_errors)

    structured_output = []
    structured_output.append("📊 COMPILATION OUTPUT ANALYSIS - BATCH ERROR REPORT:")
    structured_output.append("=" * 60)

    if syntax_errors:
        structured_output.append(f"\n🔴 SYNTAX ERRORS ({len(syntax_errors)} total):")
        for i, error in enumerate(syntax_errors[:10], 1):
            structured_output.append(f"  {i}. {error}")
        if len(syntax_errors) > 10:
            structured_output.append(f"  ... and {len(syntax_errors) - 10} more syntax errors (fix these first to resolve cascading issues)")

    if type_errors:
        structured_output.append(f"\n🟠 TYPE/DECLARATION ERRORS ({len(type_errors)} total):")
        for i, error in enumerate(type_errors[:10], 1):
            structured_output.append(f"  {i}. {error}")
        if len(type_errors) > 10:
            structured_output.append(f"  ... and {len(type_errors) - 10} more type errors")

    if linker_errors:
        structured_output.append(f"\n🔗 LINKER ERRORS ({len(linker_errors)} total):")
        for i, error in enumerate(linker_errors[:10], 1):
            structured_output.append(f"  {i}. {error}")
        if len(linker_errors) > 10:
            structured_output.append(f"  ... and {len(linker_errors) - 10} more linker errors")

    if warnings:
        structured_output.append(f"\n⚠️ WARNINGS ({len(warnings)} total):")
        for i, warning in enumerate(warnings[:10], 1):
            structured_output.append(f"  {i}. {warning}")
        if len(warnings) > 10:
            structured_output.append(f"  ... and {len(warnings) - 10} more warnings")

    if total_errors > 0:
        structured_output.append(f"\n💡 BATCH FIXING SUGGESTIONS ({total_errors} errors total):")

        if syntax_errors:
            structured_output.append("  🔴 For syntax errors:")
            structured_output.append("    - Fix missing/extra braces, parentheses, semicolons")
            structured_output.append("    - Check for typos in keywords and operators")
            structured_output.append("    - Ensure proper ReflexScript syntax structure")

        if type_errors:
            structured_output.append("  🟠 For type/declaration errors:")
            structured_output.append("    - Verify all variables are declared with correct types")
            structured_output.append("    - Check unit annotations (e.g., i16[m], u8[Hz])")
            structured_output.append("    - Ensure type compatibility in expressions")

        structured_output.append("\n  📝 BATCH FIXING STRATEGY:")
        structured_output.append("    1. Address ALL errors of the same type together")
        structured_output.append("    2. Start with syntax errors first (they often cascade)")
        structured_output.append("    3. Then fix type/declaration errors")
        structured_output.append("    4. Finally address linker issues")
        structured_output.append("    5. Re-compile to check if fixes resolved multiple errors")

    error_counts = []
    if syntax_errors:
        error_counts.append(f"{len(syntax_errors)} syntax")
    if type_errors:
        error_counts.append(f"{len(type_errors)} type")
    if linker_errors:
        error_counts.append(f"{len(linker_errors)} linker")
    if warnings:
        error_counts.append(f"{len(warnings)} warnings")

    if error_counts:
        structured_output.append(f"\n📊 SUMMARY: Found {', '.join(error_counts)} errors/warnings")
        structured_output.append("🔍 FIRST 10 ERRORS OF EACH TYPE SHOWN - Fix these to resolve many cascading issues")
        if total_errors > 30:
            structured_output.append("⚠️  Many errors detected - focus on syntax errors first as they often cause cascading failures")

    structured_output.append(f"\n❌ ReflexScript compilation FAILED")
    structured_output.append("\n📋 ACTION REQUIRED: Review the compilation errors above and fix the syntax issues before proceeding.")

    structured_output.append(f"\n### Your Code That Failed:")
    structured_output.append("```reflexscript")
    structured_output.append(code)
    structured_output.append("```")

    structured_output.append("\nOutput the FIXED code in a ```reflexscript block.")

    return "\n".join(structured_output)


def format_error_feedback(original_prompt, code, errors):
    """Format error feedback prompt for retry."""
    # Deduplicate errors by line number, keep first error per line
    seen_lines = set()
    unique_errors = []
    for e in errors:
        if e['line'] not in seen_lines:
            seen_lines.add(e['line'])
            unique_errors.append(e)

    # Limit to first 10 unique errors to avoid overwhelming the LLM
    limited_errors = unique_errors[:10]

    error_lines = []
    for e in limited_errors:
        error_str = f"- Line {e['line']}, Column {e['column']}: [{e['type']}] {e['message']}"
        if e.get('suggestion'):
            error_str += f"\n  Suggestion: {e['suggestion']}"
        error_lines.append(error_str)

    errors_text = "\n".join(error_lines)

    if len(unique_errors) > 10:
        errors_text += f"\n... and {len(unique_errors) - 10} more errors on other lines"

    # Include a working reference example based on Reflex-langchain essentials
    reference_example = '''
## WORKING EXAMPLE (use this as syntax reference)
```reflexscript
reflex example_controller @(rate(100Hz), wcet(50us), stack(256bytes), bounded) {
    input:  sensor: i16[m],
            trigger: bool
    output: actuator: bool,
            speed: i16[mps]
    state:  counter: u8 = 0,
            timer: u16 = 0

    safety {
        input:  { sensor in 0..5000, trigger in {true, false} }
        state:  { counter in 0..255, timer in 0..1000 }
        output: { actuator in {true, false}, speed in -1000..1000 }
        require: { sensor < 300 -> !actuator,
                   sensor < 300 -> speed == 0 }
    }

    loop {
        if (sensor < 300) {
            actuator = false
            speed = 0
            counter = clamp(counter + 1, 0, 255)
        } else {
            actuator = true
            speed = clamp(trigger ? 500 : 100, 0, 1000)
        }
        timer = (timer + 1) % 1000
    }

    tests {
        reset_state
        test safe_stop inputs: { sensor = 200[m], trigger = false },
                     expect: { actuator = false, speed = 0 }
        test normal_run inputs: { sensor = 1000[m], trigger = true },
                      expect: { actuator = true, speed = 500 }
    }
}
```

## VALID UNITS (only these are supported)
- **SI Core**: `[m]` `[rad]` `[s]` `[ms]` `[Hz]` `[mps]` `[radps]`
- **Angular**: `[deg]` (degrees)
- **Temperature**: `[degC]` `[degF]`
- **Length**: `[mm]` `[cm]` `[km]` `[ft]` `[in]`
- **Mass**: `[kg]` `[g]` `[lb]` `[oz]`

**INVALID units** (DO NOT USE): `[Nm]` `[rad/s]` `[m/s]` or any compound units with `/`

## CRITICAL SYNTAX RULES
1. **Types with units**: `i16[m]`, `i16[rad]`, `i16[mps]` - brackets contain ONLY a single unit name
2. **NO compound units**: `[rad/s]` is INVALID - use `[radps]` instead
3. **Float domains use brackets**: `[-1.0, 1.0]` NOT `..`
4. **Integer domains use `..`**: `0..100`
5. **Boolean domains use sets**: `{true, false}`
6. **MISRA-C parentheses**: `((a < b) || (c > d))` - wrap ALL comparisons
7. **Built-ins**: `clamp(val, min, max)`, `abs(val)`, `min(a, b)`, `max(a, b)`
8. **Safety block comes BEFORE loop block**
9. **No return statements** - use if/else for control flow
10. **Unit literals in tests**: `sensor = 200[m]` not `sensor = 200`
'''

    return f"""## TASK: Fix the compilation errors in the code below.

## Original Request
{original_prompt}

## YOUR CODE (fix this code - do NOT copy the reference example)
```reflexscript
{code}
```

## Compiler Errors
{errors_text}

## VALID UNITS (only these work)
`[m]` `[rad]` `[s]` `[ms]` `[Hz]` `[mps]` `[radps]` `[deg]` `[degC]` `[degF]` `[mm]` `[cm]` `[km]` `[kg]` `[g]`

**INVALID**: `[Nm]` `[rad/s]` `[m/s]` - NO compound units with `/`

## Common Fixes
- `i16[Nm]` → `i16` (Nm not valid)
- `i16[rad/s]` → `i16[radps]`
- `target_angle` undefined → add it to `input:` section
- float comparison → use integer scaled values

## SAFETY BLOCK SYNTAX (this is often wrong!)
The safety block uses `variable in range` syntax, NOT type declarations:
```
// WRONG - do NOT put types in safety block:
safety {{ input: {{ target_angle: i16[rad] }} }}

// CORRECT - use ranges:
safety {{ input: {{ target_angle in -314..314 }} }}
```

## Instructions
1. **Fix YOUR CODE above** - do NOT start over or copy examples
2. **Add missing variables** - if `target_angle` is undefined, add `target_angle: i16[rad]` to input section
3. **Fix invalid units** - replace `[Nm]` with no unit, `[rad/s]` with `[radps]`
4. **Output the FIXED version** of YOUR CODE in a ```reflexscript block

IMPORTANT: Output a FIXED version of the code above. Do NOT output example code or start from scratch."""


# ============================================================================
# Main Agent Loop
# ============================================================================

SIMPLE_SYSTEM_PROMPT = """You are a ReflexScript code generator. Generate syntactically correct ReflexScript code.

VALID UNITS: [m] [rad] [s] [ms] [Hz] [mps] [radps] [deg] [degC] [mm] [cm] [kg]
INVALID UNITS: [Nm] [rad/s] [m/s] - NO compound units with /

TEMPLATE:
```reflexscript
reflex name @(rate(100Hz), wcet(50us), stack(256bytes), bounded) {
    input:  sensor: i16[m]
    output: actuator: bool
    state:  counter: u8 = 0

    safety {
        input:  { sensor in 0..5000 }
        output: { actuator in {true, false} }
    }

    loop {
        if (sensor < 300) {
            actuator = false
        } else {
            actuator = true
        }
    }

    tests {
        reset_state
        test case1 inputs: { sensor = 200[m] }, expect: { actuator = false }
    }
}
```

Output code in a ```reflexscript block."""


def agent_loop(system_prompt_path, prompt_path, output_path, max_iterations,
               host, port, temperature, verbose=False, save_prompts=False, simple_mode=False):
    """Main agent loop for iterative code generation."""

    # Load prompts
    if simple_mode:
        system_prompt = SIMPLE_SYSTEM_PROMPT
        print("Using simple mode (smaller model optimizations)")
    else:
        try:
            system_prompt = Path(system_prompt_path).read_text().strip()
        except Exception as e:
            print(f"Error loading system prompt: {e}")
            return 1

    try:
        user_prompt = Path(prompt_path).read_text().strip()
    except Exception as e:
        print(f"Error loading user prompt: {e}")
        return 1

    # Check vLLM server
    print(f"Connecting to vLLM at {host}:{port}...")
    if not check_vllm_health(host, port):
        print(f"Error: Cannot connect to vLLM server at {host}:{port}")
        print("Make sure vLLM is running: vllm serve ...")
        return 1
    print("Connected to vLLM server")

    # Get model name
    model = get_model_name(host, port)
    print(f"Using model: {model}")

    # Detect reflexc
    reflexc = detect_reflexc_path()
    if not reflexc:
        print("Error: Cannot find reflexc compiler")
        print("Expected locations:")
        print("  ARM64: /home/thinkcircuits/Reflexible/Reflexscript/build/reflexc")
        print("  x86_64: /home/thinkcircuits/Reflexible/reflexible-platforms/tools/reflexc/bin/reflexc")
        return 1
    print(f"Using compiler: {reflexc}")

    print(f"\nOutput file: {output_path}")
    print(f"Max iterations: {max_iterations}")
    print("=" * 60)

    current_code = None
    errors = []
    compiler_output = ""
    conversation_history = []  # Track full conversation like LangGraph

    for iteration in range(1, max_iterations + 1):
        print(f"\n[{iteration}/{max_iterations}] Generating ReflexScript code...")

        # Build messages - maintain conversation history like Reflex-langchain
        if current_code is None:
            # First attempt - initialize conversation
            user_content = user_prompt
            active_system_prompt = system_prompt
            messages = [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_content}
            ]
            conversation_history = messages.copy()  # Start tracking history
        else:
            # Retry with error feedback - APPEND to conversation history
            # This mirrors the LangGraph approach where tool outputs accumulate
            active_system_prompt = system_prompt  # Keep full system prompt

            # Create a "tool-like" message with compilation results
            error_message = format_error_feedback_for_history(current_code, errors, compiler_output, simple_mode)
            conversation_history.append({"role": "user", "content": error_message})

            # Use the accumulated conversation history
            messages = conversation_history.copy()

        # Show what we're sending to the LLM
        msg_count = len(messages)
        total_chars = sum(len(m.get("content", "")) for m in messages)

        if verbose:
            print("\n" + "=" * 60)
            print("SENDING TO LLM:")
            print("=" * 60)
            print(f"Conversation: {msg_count} messages, {total_chars} total chars")
            print(f"System prompt: {len(active_system_prompt)} chars")
            if iteration > 1:
                # Show the error feedback message
                print("-" * 60)
                print("Latest error feedback:")
                print(messages[-1].get("content", "")[:2000])
            print("=" * 60 + "\n")
        else:
            # Always show a summary of what's being sent
            print(f"  Conversation: {msg_count} messages, {total_chars} total chars")
            if iteration > 1:
                print(f"  (includes {iteration - 1} previous attempt(s) with errors)")

        # Optionally save prompts to files for debugging
        if save_prompts:
            prompt_dir = Path(output_path).parent / "debug_prompts"
            prompt_dir.mkdir(parents=True, exist_ok=True)

            # Save system prompt (only on first iteration)
            if iteration == 1:
                (prompt_dir / "system_prompt.md").write_text(system_prompt)
                print(f"  Saved system prompt to: {prompt_dir / 'system_prompt.md'}")

            # Save full conversation for this iteration
            import json
            conv_file = prompt_dir / f"conversation_iter{iteration}.json"
            conv_file.write_text(json.dumps(messages, indent=2))
            print(f"  Saved conversation to: {conv_file}")

        # Call LLM
        print("-" * 40)
        response = call_vllm(messages, host, port, model, temperature)
        print("-" * 40)

        if not response:
            print("Warning: Empty response from LLM")
            continue

        # Add assistant response to conversation history (like LangGraph does)
        conversation_history.append({"role": "assistant", "content": response})

        # Extract code
        code = extract_code_from_response(response)
        if not code:
            print("Warning: No ReflexScript code found in response")
            # On subsequent attempts, keep the old code
            if current_code is None:
                continue
            code = current_code

        current_code = code

        # Write to file
        write_rfx_file(code, output_path)

        # Compile
        print(f"\n[{iteration}/{max_iterations}] Compiling with reflexc...")
        success, compiler_output = run_reflexc(output_path, reflexc)

        if success:
            print(f"\nSUCCESS after {iteration} iteration(s)")
            print(f"Output: {output_path}")
            if compiler_output:
                print(f"\nCompiler output:\n{compiler_output}")
            return 0

        # Parse errors - store compiler_output for next iteration's feedback
        errors = parse_errors(compiler_output)
        error_count = len(errors) if errors else 1

        print(f"[{iteration}/{max_iterations}] Found {error_count} error(s)")

        if verbose or not errors:
            print(f"\nCompiler output:\n{compiler_output}")
        else:
            for e in errors:
                print(f"  Line {e['line']}: [{e['type']}] {e['message']}")
                if e.get('suggestion'):
                    print(f"    Suggestion: {e['suggestion']}")

    print(f"\nFAILED after {max_iterations} iterations")
    print(f"Last attempt saved to: {output_path}")
    return 1


# ============================================================================
# CLI Entry Point
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="ReflexScript Agent Loop - Iteratively generates syntactically correct code",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Basic usage (uses default system prompt)
  python3 agent_loop.py --prompt rs-coder/examples/example_prompt.txt --output generated.rfx

  # With custom settings
  python3 agent_loop.py --prompt rs-coder/examples/example_prompt.txt \\
                        --output generated.rfx \\
                        --max-iterations 10 \\
                        --verbose

  # Remote vLLM server
  python3 agent_loop.py --prompt rs-coder/examples/example_prompt.txt \\
                        --host 192.168.1.100 \\
                        --port 8000

  # Custom system prompt
  python3 agent_loop.py --system-prompt custom_prompt.md \\
                        --prompt rs-coder/examples/example_prompt.txt
        """
    )

    parser.add_argument(
        '--system-prompt',
        type=str,
        default='prompts/reflexscript_agent_system_prompt.md',
        help='Path to system prompt file (default: prompts/reflexscript_agent_system_prompt.md)'
    )

    parser.add_argument(
        '--prompt',
        type=str,
        required=True,
        help='Path to user prompt file'
    )

    parser.add_argument(
        '--output',
        type=str,
        default='output.rfx',
        help='Output .rfx file path (default: output.rfx)'
    )

    parser.add_argument(
        '--max-iterations',
        type=int,
        default=5,
        help='Maximum retry attempts (default: 5)'
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
        '--temperature',
        type=float,
        default=0.1,
        help='LLM temperature (default: 0.1)'
    )

    parser.add_argument(
        '--verbose',
        action='store_true',
        help='Print detailed progress and full compiler output'
    )

    parser.add_argument(
        '--save-prompts',
        action='store_true',
        help='Save prompts to debug_prompts/ directory for debugging'
    )

    parser.add_argument(
        '--simple-mode',
        action='store_true',
        help='Use simplified prompts for smaller models (DeepSeek-Coder-Lite, etc.)'
    )

    args = parser.parse_args()

    return agent_loop(
        system_prompt_path=args.system_prompt,
        prompt_path=args.prompt,
        output_path=args.output,
        max_iterations=args.max_iterations,
        host=args.host,
        port=args.port,
        temperature=args.temperature,
        verbose=args.verbose,
        save_prompts=args.save_prompts,
        simple_mode=args.simple_mode
    )


if __name__ == "__main__":
    sys.exit(main())
