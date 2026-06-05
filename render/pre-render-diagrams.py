#!/usr/bin/env python3
"""
pre-render-diagrams.py — Extract and render mermaid/plantuml code blocks to PNGs.

Usage:
    python3 pre-render-diagrams.py <input.md> <output.md> <img-dir>

Finds every ```mermaid and ```plantuml fence, renders it to a PNG in <img-dir>,
and replaces the fence with a markdown image reference. Output is a new .md file
safe to pass to pandoc.

Requirements: mmdc (npm install -g @mermaid-js/mermaid-cli), plantuml (brew install plantuml)
"""

import sys
import re
import os
import subprocess
import tempfile
import hashlib

def render_mermaid(code: str, out_path: str) -> bool:
    with tempfile.NamedTemporaryFile(suffix=".mmd", mode="w", delete=False) as f:
        f.write(code)
        tmp = f.name
    try:
        result = subprocess.run(
            ["mmdc", "-i", tmp, "-o", out_path, "-b", "white", "--width", "1200"],
            capture_output=True, text=True, timeout=30
        )
        return result.returncode == 0
    except Exception as e:
        print(f"  ⚠ mmdc error: {e}", file=sys.stderr)
        return False
    finally:
        os.unlink(tmp)

def render_plantuml(code: str, out_path: str) -> bool:
    with tempfile.NamedTemporaryFile(suffix=".puml", mode="w", delete=False) as f:
        f.write(code)
        tmp = f.name
    out_dir = os.path.dirname(out_path)
    os.makedirs(out_dir, exist_ok=True)
    before = set(os.listdir(out_dir))
    try:
        result = subprocess.run(
            ["plantuml", "-png", "-o", out_dir, tmp],
            capture_output=True, text=True, timeout=60
        )
        # plantuml names the output after the @startuml title (or input basename)
        # Find whichever new .png appeared in out_dir
        after = set(os.listdir(out_dir))
        new_pngs = [f for f in (after - before) if f.endswith(".png")]
        if new_pngs:
            generated = os.path.join(out_dir, new_pngs[0])
            if generated != out_path:
                os.rename(generated, out_path)
            return os.path.exists(out_path)
        # Fallback: check input-basename convention
        fallback = os.path.join(out_dir, os.path.basename(tmp).replace(".puml", ".png"))
        if os.path.exists(fallback) and fallback != out_path:
            os.rename(fallback, out_path)
        return os.path.exists(out_path)
    except Exception as e:
        print(f"  ⚠ plantuml error: {e}", file=sys.stderr)
        return False
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

def process(input_md: str, output_md: str, img_dir: str):
    os.makedirs(img_dir, exist_ok=True)

    with open(input_md, "r") as f:
        content = f.read()

    # Match ```mermaid or ```plantuml fences
    pattern = re.compile(
        r'```(mermaid|plantuml)\s*\n(.*?)```',
        re.DOTALL | re.IGNORECASE
    )

    counter = [0]
    replaced = [0]

    def replace_block(m):
        lang = m.group(1).lower()
        code = m.group(2)
        counter[0] += 1
        digest = hashlib.md5(code.encode()).hexdigest()[:8]
        img_name = f"diagram-{counter[0]:02d}-{digest}.png"
        img_path = os.path.join(img_dir, img_name)

        print(f"  → Rendering {lang} diagram {counter[0]:02d} ...", file=sys.stderr)

        ok = False
        if lang == "mermaid":
            ok = render_mermaid(code, img_path)
        elif lang == "plantuml":
            ok = render_plantuml(code, img_path)

        if ok and os.path.exists(img_path):
            replaced[0] += 1
            # Use absolute path so pandoc resolves correctly regardless of cwd
            print(f"     ✓ {img_name}", file=sys.stderr)
            return f"![]({img_path})"
        else:
            print(f"     ✗ render failed — keeping as code block", file=sys.stderr)
            return m.group(0)

    processed = pattern.sub(replace_block, content)

    with open(output_md, "w") as f:
        f.write(processed)

    print(f"  Diagrams: {replaced[0]}/{counter[0]} rendered", file=sys.stderr)

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <input.md> <output.md> <img-dir>", file=sys.stderr)
        sys.exit(1)
    process(sys.argv[1], sys.argv[2], sys.argv[3])
