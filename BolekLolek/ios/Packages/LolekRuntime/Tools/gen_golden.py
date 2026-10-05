#!/usr/bin/env python3
"""Renders sample conversations through the REAL chat templates embedded in the GGUF
files (fetched from the Hugging Face API) and writes golden outputs that the Swift
prompt renderer must reproduce byte for byte.

    python3 -m venv /tmp/venv && /tmp/venv/bin/pip install jinja2
    /tmp/venv/bin/python Tools/gen_golden.py

Mimics the Hugging Face `tojson` filter and sandboxed environment (trim_blocks,
lstrip_blocks, loopcontrols), which is what llama.cpp's own Jinja engine is tested against.
"""
import json
import urllib.request
from pathlib import Path

import jinja2
import jinja2.ext
from jinja2.sandbox import ImmutableSandboxedEnvironment

FIXTURES = Path(__file__).resolve().parent.parent / "Tests" / "LolekRuntimeTests" / "Fixtures"
SOURCES = {
    "qwen35": ("unsloth/Qwen3.5-4B-GGUF", "<|im_end|>"),
}


def fetch_template(repo):
    with urllib.request.urlopen(f"https://huggingface.co/api/models/{repo}") as r:
        gguf = json.load(r)["gguf"]
    return gguf["chat_template"], gguf.get("bos_token", "")


def make_env():
    env = ImmutableSandboxedEnvironment(
        trim_blocks=True, lstrip_blocks=True, extensions=[jinja2.ext.loopcontrols]
    )

    def raise_exception(message):
        raise jinja2.exceptions.TemplateError(message)

    def tojson(x, ensure_ascii=False, indent=None, separators=None, sort_keys=False):
        return json.dumps(x, ensure_ascii=ensure_ascii, indent=indent, separators=separators, sort_keys=sort_keys)

    env.globals["raise_exception"] = raise_exception
    env.filters["tojson"] = tojson
    return env


def tool(name, description, props, required):
    return {"type": "function", "function": {"name": name, "description": description,
            "parameters": {"type": "object", "properties": props, "required": required}}}


TOOLS = [
    tool("get_weather", "Get the current weather.", {"place": {"type": "string"}}, []),
    tool("set_timer", "Start a timer.", {"seconds": {"type": "integer"}, "label": {"type": "string"}}, ["seconds"]),
]

SYS = "You are Lolek. Be brief."


def call(name, **arguments):
    return {"function": {"name": name, "arguments": arguments}}


CASES = {
    "qwen35": [
        ("plain", None, [{"role": "system", "content": SYS}, {"role": "user", "content": "Cześć!"}]),
        ("with_tools", TOOLS, [{"role": "system", "content": SYS}, {"role": "user", "content": "Pogoda w Krakowie?"}]),
        ("tool_loop", TOOLS, [
            {"role": "system", "content": SYS},
            {"role": "user", "content": "Pogoda w Krakowie?"},
            {"role": "assistant", "content": "", "tool_calls": [call("get_weather", place="Kraków")]},
            {"role": "tool", "content": "Kraków: 14°C, pochmurno."},
        ]),
        ("parallel_calls", TOOLS, [
            {"role": "system", "content": SYS},
            {"role": "user", "content": "Pogoda i timer na 5 minut."},
            {"role": "assistant", "content": "Już robię.", "tool_calls": [call("get_weather"), call("set_timer", seconds=300, label="herbata")]},
            {"role": "tool", "content": "Warszawa: 13°C"},
            {"role": "tool", "content": "Timer set."},
        ]),
        ("multi_turn", TOOLS, [
            {"role": "system", "content": SYS},
            {"role": "user", "content": "Hi"},
            {"role": "assistant", "content": "Hello! How can I help?"},
            {"role": "user", "content": "Weather?"},
            {"role": "assistant", "content": "", "tool_calls": [call("get_weather")]},
            {"role": "tool", "content": "Warszawa: 13°C"},
            {"role": "assistant", "content": "It's 13°C in Warszawa."},
            {"role": "user", "content": "Thanks, and a 2 minute timer"},
        ]),
    ],
}


def main():
    FIXTURES.mkdir(parents=True, exist_ok=True)
    env = make_env()
    for key, (repo, _) in SOURCES.items():
        template, bos = fetch_template(repo)
        (FIXTURES / f"{key}.jinja").write_text(template)
        compiled = env.from_string(template)
        golden = []
        for name, tools, messages in CASES[key]:
            kwargs = dict(messages=messages, add_generation_prompt=True, bos_token=bos)
            if tools:
                kwargs["tools"] = tools
            golden.append({"name": name, "tools": tools, "messages": messages, "expected": compiled.render(**kwargs)})
        (FIXTURES / f"{key}.golden.json").write_text(json.dumps(golden, ensure_ascii=False, indent=1))
        print(f"{key}: {len(golden)} cases from {repo}")


if __name__ == "__main__":
    main()
