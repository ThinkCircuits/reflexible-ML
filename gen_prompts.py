"""
ReflexScript Training Prompt Generator

Generates diverse, platform-agnostic training prompts for fine-tuning a model
that writes ReflexScript code. Prompts exercise ReflexScript language features
(safety blocks, physical units, bounded loops, WCET constraints) without being
tied to specific hardware platforms.

Features:
- Parallel batch generation for speed
- Checkpoint/resume from crashes
- Deduplication (exact + n-gram)
- Validation (filters code, hardware mentions)

Usage:
    export OPENAI_API_KEY=your_key
    python gen_prompts.py

Output:
    prompts/gpt-5-Nov24/prompts_10k.csv
"""

import asyncio
import json
import csv
import os
import re
import time
from pathlib import Path
from dataclasses import dataclass, field
from typing import Optional
from openai import AsyncOpenAI


# =============================================================================
# Configuration
# =============================================================================

@dataclass
class Config:
    """Configuration for prompt generation."""
    api_key: str
    model: str = "gpt-5"
    max_tokens: int = 16384
    batch_size: int = 50
    n_per_domain: int = 2000
    max_retries: int = 3
    retry_delay: float = 1.0
    max_concurrent: int = 50  # Parallel API calls
    output_dir: Path = field(default_factory=lambda: Path("prompts/gpt-5-Nov24"))
    checkpoint_dir: Path = field(default_factory=lambda: Path("prompts/.checkpoints"))

    @classmethod
    def from_env(cls) -> "Config":
        api_key = os.environ.get("OPENAI_API_KEY")
        if not api_key:
            raise ValueError(
                "OPENAI_API_KEY environment variable not set.\n"
                "Set it via: export OPENAI_API_KEY=your_key"
            )
        return cls(api_key=api_key)

    @property
    def batches_per_domain(self) -> int:
        return (self.n_per_domain + self.batch_size - 1) // self.batch_size


# =============================================================================
# Domain Definitions
# =============================================================================

DOMAINS = [
    ("A", "LED / Lighting / Art Projects", {
        "focus": "PWM control, color patterns, brightness, timing sequences",
        "reflexscript_features": ["bounded loops for patterns", "rate attributes", "state machines"]
    }),
    ("B", "Sensors / Environmental Monitoring", {
        "focus": "Temperature, humidity, pressure, light, air quality monitoring",
        "reflexscript_features": ["physical units [degC], [%]", "safety thresholds", "alarm logic"]
    }),
    ("C", "Robotics / Motion / Actuators", {
        "focus": "Motors, servos, steppers, position control, velocity",
        "reflexscript_features": ["units [rad], [mps]", "PID control", "safety limits", "WCET"]
    }),
    ("D", "IoT / Home Automation / Smart Devices", {
        "focus": "Switches, relays, timers, automation rules, schedules",
        "reflexscript_features": ["state machines", "enum modes", "watchdog timers"]
    }),
    ("E", "Education / Beginner / STEM Classroom Projects", {
        "focus": "Simple tutorials, learning exercises, classroom demos",
        "reflexscript_features": ["basic syntax", "simple safety blocks", "inline tests"]
    })
]


# =============================================================================
# System Prompt
# =============================================================================

SYSTEM_PROMPT = """You are generating training prompts for an AI that writes ReflexScript code.
ReflexScript is a safety-critical DSL for embedded controllers that compiles to MISRA-C.

PROMPT STYLE GUIDELINES:
- Prompts should be natural language requests, NOT code
- Vary tones: casual, formal, terse, verbose, beginner-friendly, technical
- Do NOT mention specific hardware platforms (no "Pico", "Arduino", "ESP32", "STM32", "Raspberry Pi")
- Focus on the BEHAVIOR being requested, not implementation details
- Some prompts should explicitly mention safety requirements
- Some prompts should mention specific units (temperature in Celsius, velocity in m/s, etc.)
- Include prompts that request state machines, PID control, sensor fusion
- Include prompts that mention timing constraints (rate, WCET)

COMPLEXITY DISTRIBUTION for this batch:
- 30% Basic: Single input/output, simple logic ("turn on LED when button pressed")
- 40% Intermediate: Multi-I/O, state machines, conditional logic
- 20% Advanced: PID control, sensor fusion, complex safety requirements
- 10% Expert: Multi-mode systems, comprehensive testing requirements

IMPORTANT: Output ONLY a valid JSON array with no markdown formatting.
Format: [{"id": int, "domain": "domain_name", "prompt": "prompt_text"}, ...]
"""


# =============================================================================
# Validation
# =============================================================================

# Patterns that indicate code contamination
CODE_PATTERNS = [
    r"reflex\s+\w+\s*@",
    r"input:\s*\w+:",
    r"output:\s*\w+:",
    r"loop\s*\{",
    r"let\s+\w+:\s*\w+",
    r"^\s*//",
    r"def\s+\w+\(",
    r"void\s+\w+\(",
    r"#include",
    r"```",
]

# Hardware platforms to filter out
HARDWARE_PLATFORMS = [
    r"\bpico\b", r"\barduino\b", r"\besp32\b", r"\besp8266\b",
    r"\bstm32\b", r"\braspberry\s*pi\b", r"\batmega\b", r"\battiny\b",
    r"\brp2040\b", r"\bmega\b", r"\buno\b", r"\bnano\b"
]


def validate_prompt(prompt: dict) -> bool:
    """Validate a generated prompt."""
    if not isinstance(prompt, dict):
        return False

    text = prompt.get("prompt", "")
    if not isinstance(text, str):
        return False

    if len(text) < 15 or len(text) > 500:
        return False

    for pattern in CODE_PATTERNS:
        if re.search(pattern, text, re.IGNORECASE | re.MULTILINE):
            return False

    for pattern in HARDWARE_PLATFORMS:
        if re.search(pattern, text, re.IGNORECASE):
            return False

    return True


# =============================================================================
# Checkpointing - Individual batch files
# =============================================================================

class CheckpointManager:
    """Manages checkpoint files - one file per batch for crash recovery."""

    def __init__(self, checkpoint_dir: Path):
        self.checkpoint_dir = checkpoint_dir
        self.checkpoint_dir.mkdir(parents=True, exist_ok=True)

    def _batch_path(self, domain_code: str, batch_num: int) -> Path:
        return self.checkpoint_dir / f"{domain_code}_batch_{batch_num:04d}.json"

    def batch_exists(self, domain_code: str, batch_num: int) -> bool:
        """Check if a batch checkpoint exists."""
        return self._batch_path(domain_code, batch_num).exists()

    def save_batch(self, domain_code: str, batch_num: int, prompts: list[dict]) -> None:
        """Save a completed batch to its own file."""
        path = self._batch_path(domain_code, batch_num)
        with open(path, "w", encoding="utf-8") as f:
            json.dump({"batch": batch_num, "prompts": prompts}, f)

    def load_batch(self, domain_code: str, batch_num: int) -> list[dict]:
        """Load a batch from checkpoint."""
        path = self._batch_path(domain_code, batch_num)
        if not path.exists():
            return []
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
            return data.get("prompts", [])

    def get_completed_batches(self, domain_code: str) -> set[int]:
        """Get set of completed batch numbers for a domain."""
        completed = set()
        for path in self.checkpoint_dir.glob(f"{domain_code}_batch_*.json"):
            match = re.search(r"_batch_(\d+)\.json$", path.name)
            if match:
                completed.add(int(match.group(1)))
        return completed

    def load_all_for_domain(self, domain_code: str, num_batches: int) -> list[dict]:
        """Load all completed batches for a domain."""
        all_prompts = []
        for batch_num in range(num_batches):
            all_prompts.extend(self.load_batch(domain_code, batch_num))
        return all_prompts


# =============================================================================
# Progress Tracking
# =============================================================================

class ProgressTracker:
    """Thread-safe progress tracking."""

    def __init__(self, total_batches: int):
        self.total_batches = total_batches
        self.completed = 0
        self.failed = 0
        self.start_time = time.time()
        self._lock = asyncio.Lock()

    async def mark_complete(self) -> None:
        async with self._lock:
            self.completed += 1
            self._print()

    async def mark_failed(self) -> None:
        async with self._lock:
            self.failed += 1
            self._print()

    def _print(self) -> None:
        elapsed = time.time() - self.start_time
        done = self.completed + self.failed
        pct = (done / self.total_batches) * 100 if self.total_batches > 0 else 0

        if self.completed > 0:
            rate = self.completed / elapsed
            remaining = self.total_batches - done
            eta = remaining / rate if rate > 0 else 0
            eta_str = self._format_time(eta)
        else:
            eta_str = "--:--"

        print(
            f"\r[{pct:5.1f}%] "
            f"Done: {self.completed}/{self.total_batches} | "
            f"Failed: {self.failed} | "
            f"Elapsed: {self._format_time(elapsed)} | "
            f"ETA: {eta_str}   ",
            end="", flush=True
        )

    @staticmethod
    def _format_time(secs: float) -> str:
        m, s = divmod(int(secs), 60)
        h, m = divmod(m, 60)
        return f"{h}h{m:02d}m" if h else f"{m:02d}:{s:02d}"


# =============================================================================
# API Interaction
# =============================================================================

async def generate_batch(
    client: AsyncOpenAI,
    config: Config,
    domain_name: str,
    domain_meta: dict,
    batch_size: int,
    start_id: int
) -> list[dict]:
    """Generate a single batch of prompts."""

    user_prompt = f"""Generate exactly {batch_size} unique prompts for the domain: {domain_name}

Domain focus: {domain_meta.get('focus', '')}
ReflexScript features to emphasize: {', '.join(domain_meta.get('reflexscript_features', []))}

Label each with domain = "{domain_name}" and id = sequential integers starting at {start_id}.
Output ONLY a valid JSON array, no markdown, no explanation."""

    response = await client.chat.completions.create(
        model=config.model,
        max_completion_tokens=config.max_tokens,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt}
        ]
    )

    text = response.choices[0].message.content

    # Parse JSON, handling potential markdown code blocks
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        match = re.search(r'```(?:json)?\s*([\s\S]*?)\s*```', text)
        if match:
            data = json.loads(match.group(1))
        else:
            match = re.search(r'\[[\s\S]*\]', text)
            if match:
                data = json.loads(match.group(0))
            else:
                raise ValueError(f"Could not parse JSON from response: {text[:200]}...")

    return data


async def generate_batch_with_retry(
    client: AsyncOpenAI,
    config: Config,
    domain_name: str,
    domain_meta: dict,
    batch_size: int,
    start_id: int
) -> list[dict]:
    """Generate batch with retry logic."""

    last_error: Optional[Exception] = None

    for attempt in range(config.max_retries):
        try:
            return await generate_batch(
                client, config, domain_name, domain_meta, batch_size, start_id
            )
        except Exception as e:
            last_error = e
            error_str = str(e).lower()

            # Don't retry auth errors
            if any(x in error_str for x in ["invalid_api_key", "401", "authentication"]):
                raise

            # Retry with backoff
            if attempt < config.max_retries - 1:
                delay = config.retry_delay * (2 ** attempt)
                await asyncio.sleep(delay)

    raise last_error or Exception("Max retries exceeded")


# =============================================================================
# Parallel Generation
# =============================================================================

async def process_batch(
    client: AsyncOpenAI,
    config: Config,
    domain_code: str,
    domain_name: str,
    domain_meta: dict,
    batch_num: int,
    checkpoint_mgr: CheckpointManager,
    progress: ProgressTracker,
    semaphore: asyncio.Semaphore
) -> None:
    """Process a single batch with semaphore for concurrency control."""

    # Skip if already completed
    if checkpoint_mgr.batch_exists(domain_code, batch_num):
        await progress.mark_complete()
        return

    async with semaphore:
        try:
            start_id = batch_num * config.batch_size + 1

            raw_prompts = await generate_batch_with_retry(
                client, config, domain_name, domain_meta,
                config.batch_size, start_id
            )

            # Validate prompts
            valid_prompts = [p for p in raw_prompts if validate_prompt(p)]

            # Save to checkpoint file immediately
            checkpoint_mgr.save_batch(domain_code, batch_num, valid_prompts)
            await progress.mark_complete()

        except Exception as e:
            print(f"\n  Failed {domain_code} batch {batch_num}: {e}")
            await progress.mark_failed()


async def generate_all_parallel(
    client: AsyncOpenAI,
    config: Config,
    checkpoint_mgr: CheckpointManager
) -> dict[str, list[dict]]:
    """Generate all prompts in parallel across all domains."""

    # Calculate total batches
    total_batches = len(DOMAINS) * config.batches_per_domain
    progress = ProgressTracker(total_batches)

    # Semaphore for concurrency control
    semaphore = asyncio.Semaphore(config.max_concurrent)

    # Create all tasks immediately to ensure they're scheduled in parallel
    tasks = []
    for domain_code, domain_name, domain_meta in DOMAINS:
        for batch_num in range(config.batches_per_domain):
            task = asyncio.create_task(process_batch(
                client, config,
                domain_code, domain_name, domain_meta,
                batch_num, checkpoint_mgr, progress, semaphore
            ))
            tasks.append(task)

    # Run all tasks in parallel (limited by semaphore)
    await asyncio.gather(*tasks, return_exceptions=True)

    print()  # Newline after progress

    # Collect results from checkpoint files
    results = {}
    for domain_code, domain_name, _ in DOMAINS:
        results[domain_code] = checkpoint_mgr.load_all_for_domain(
            domain_code, config.batches_per_domain
        )

    return results


# =============================================================================
# Deduplication (post-processing)
# =============================================================================

def normalize_text(text: str) -> str:
    return " ".join(text.lower().split())


def get_ngrams(text: str, n: int = 3) -> set:
    text = normalize_text(text)
    if len(text) < n:
        return {text}
    return set(text[i:i+n] for i in range(len(text) - n + 1))


def jaccard_similarity(set1: set, set2: set) -> float:
    if not set1 or not set2:
        return 0.0
    return len(set1 & set2) / len(set1 | set2)


def deduplicate_prompts(prompts: list[dict], threshold: float = 0.8) -> list[dict]:
    """Remove duplicate prompts using exact match and n-gram similarity.
    
    Optimized version that pre-computes n-grams and uses efficient set operations.
    """
    if not prompts:
        return []
    
    # Pre-compute normalized texts and n-grams for all prompts
    print("  Pre-computing n-grams...", end="", flush=True)
    prompt_data = []
    for i, p in enumerate(prompts):
        text = p.get("prompt", "")
        normalized = normalize_text(text)
        ngrams = get_ngrams(text)
        prompt_data.append((p, normalized, ngrams))
        if (i + 1) % 1000 == 0:
            print(f" {i+1}/{len(prompts)}", end="", flush=True)
    print()
    
    seen_normalized: set[str] = set()
    seen_ngrams: list[set] = []
    unique = []
    total = len(prompt_data)
    
    print("  Deduplicating...", end="", flush=True)
    for i, (p, normalized, ngrams) in enumerate(prompt_data):
        # Progress update every 1000 items
        if i > 0 and i % 1000 == 0:
            print(f" {i}/{total} (kept: {len(unique)})", end="", flush=True)
        
        # Exact match check (fast)
        if normalized in seen_normalized:
            continue

        # N-gram similarity check (optimized with early exit)
        is_dup = False
        ngram_size = len(ngrams)
        
        # Early exit optimization: if sets are very different in size,
        # they can't be similar enough
        for existing in seen_ngrams:
            existing_size = len(existing)
            # Quick size-based filter
            if abs(ngram_size - existing_size) > max(ngram_size, existing_size) * (1 - threshold):
                continue
            
            # Calculate Jaccard similarity
            intersection = len(ngrams & existing)
            union = len(ngrams | existing)
            if union > 0 and intersection / union > threshold:
                is_dup = True
                break

        if is_dup:
            continue

        seen_normalized.add(normalized)
        seen_ngrams.append(ngrams)
        unique.append(p)
    
    print(f" {total}/{total} (kept: {len(unique)})")
    return unique


# =============================================================================
# Main
# =============================================================================

async def main():
    """Main entry point."""

    # Load configuration
    config = Config.from_env()
    config.output_dir.mkdir(parents=True, exist_ok=True)
    config.checkpoint_dir.mkdir(parents=True, exist_ok=True)

    # Initialize
    client = AsyncOpenAI(api_key=config.api_key)
    checkpoint_mgr = CheckpointManager(config.checkpoint_dir)

    # Count existing progress
    total_batches = len(DOMAINS) * config.batches_per_domain
    existing_batches = sum(
        len(checkpoint_mgr.get_completed_batches(code))
        for code, _, _ in DOMAINS
    )

    # Print configuration
    print("=" * 60)
    print("ReflexScript Training Prompt Generator")
    print("=" * 60)
    print(f"Model:            {config.model}")
    print(f"Domains:          {len(DOMAINS)}")
    print(f"Prompts/domain:   {config.n_per_domain}")
    print(f"Batch size:       {config.batch_size}")
    print(f"Batches/domain:   {config.batches_per_domain}")
    print(f"Total batches:    {total_batches}")
    print(f"Max concurrent:   {config.max_concurrent}")
    print(f"Already done:     {existing_batches}/{total_batches}")
    print(f"Output dir:       {config.output_dir}")
    print("=" * 60)
    print()

    # Generate all prompts in parallel
    print("Generating prompts...")
    results = await generate_all_parallel(client, config, checkpoint_mgr)

    # Combine and deduplicate
    print("\nDeduplicating...")
    all_prompts = []
    for domain_code, domain_name, _ in DOMAINS:
        domain_prompts = results.get(domain_code, [])
        all_prompts.extend(domain_prompts)

    before_dedup = len(all_prompts)
    all_prompts = deduplicate_prompts(all_prompts)
    after_dedup = len(all_prompts)

    print(f"  Before: {before_dedup}, After: {after_dedup}, Removed: {before_dedup - after_dedup}")

    # Renumber IDs and write final output
    output_file = config.output_dir / "prompts_10k.csv"
    with open(output_file, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["id", "domain", "prompt"])
        writer.writeheader()
        for i, p in enumerate(all_prompts, start=1):
            writer.writerow({
                "id": i,
                "domain": p.get("domain", ""),
                "prompt": p.get("prompt", "")
            })

    # Print summary
    print()
    print("=" * 60)
    print("Generation Complete!")
    print("=" * 60)
    print(f"Total prompts:    {len(all_prompts)}")
    print(f"Output file:      {output_file}")
    print()

    # Domain breakdown
    print("Prompts by domain:")
    domain_counts = {}
    for p in all_prompts:
        d = p.get("domain", "Unknown")
        domain_counts[d] = domain_counts.get(d, 0) + 1
    for domain, count in sorted(domain_counts.items()):
        print(f"  {domain}: {count}")


if __name__ == "__main__":
    asyncio.run(main())
