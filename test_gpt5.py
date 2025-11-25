"""Quick test script to query GPT-5 model."""

import os
from openai import OpenAI

client = OpenAI(api_key=os.environ.get("OPENAI_API_KEY"))

# Hard AIME-style math problem to test GPT-5's capabilities
# GPT-5 scores 94.6% on AIME 2025 without tools
math_problem = """
Let S be the set of all positive integers n such that n^2 + 12n - 2007 is a perfect square.
Find the sum of all elements in S.

Show your step-by-step reasoning.
"""

response = client.chat.completions.create(
    model="gpt-5",
    messages=[
        {"role": "user", "content": math_problem}
    ]
)

print("Model:", response.model)
print("\nResponse:")
print(response.choices[0].message.content)
print("\n" + "="*50)
print("Usage:", response.usage)
