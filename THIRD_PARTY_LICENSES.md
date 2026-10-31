# Third-Party Licenses

This file preserves the upstream attribution notices required by Apache-2.0 §4(c)
for MIT-licensed content ported into this repository (which is Apache-2.0 — see
`LICENSE`). MIT→Apache-2.0 relicensing is one-way compatible; the original MIT
terms for each upstream are retained below verbatim.

## 1. uditgoenka/autoresearch

**Upstream:** <https://github.com/uditgoenka/autoresearch>
**License:** MIT
**Copyright:** Copyright (c) 2026 Udit Goenka

### MIT License (verbatim)

```
MIT License

Copyright (c) 2026 Udit Goenka

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### What we ported

- **`autoresearch-core-skill/SKILL.md`** — the 5-stage loop structure, the
  Goal/Scope/Metric/Verify/Guard argument shape, the bounded-by-default
  convention (`Iterations: N`, `Iterations: unlimited`), the
  keep/discard/crash/no-op/hook-blocked/metric-error status taxonomy, and the
  TSV audit-trail format all derive from uditgoenka's
  `.opencode/skills/autoresearch/SKILL.md` and `.agents/skills/autoresearch/autoresearch.md`.
- **`autoresearch-core-skill/scripts/init_research.py`** — project scaffolder
  adapted from uditgoenka's argument structure and TSV header conventions.
- **`autoresearch-core-skill/scripts/autoresearch-loop.sh`** — overnight loop
  driver adapted from uditgoenka's orchestrator pattern (`scripts/orchestrate.sh`).
- **`autoresearch-core-skill/scripts/check_progress.sh`** — progress viewer
  adapted from uditgoenka's TSV inspection patterns.
- **`autoresearch-core-skill/references/evaluator-contract.md`** — evaluator
  contract derived from uditgoenka's Verify/Guard distinction and the
  `{"pass":bool,"score":N}` shape (the strict JSON shape is inspired by
  wjgoarxiv/autoresearch-skill, below).
- **`autoresearch-core-skill/references/crash-recovery.md`** — failure-mode
  table derived from uditgoenka's status taxonomy.

## 2. karpathy/autoresearch

**Upstream:** <https://github.com/karpathy/autoresearch>
**License:** MIT (stated in upstream `README.md` §License and `pyproject.toml`;
the upstream repo ships no standalone `LICENSE` file)
**Copyright:** Copyright (c) 2026 Andrej Karpathy

### MIT License (verbatim)

```
MIT License

Copyright (c) 2026 Andrej Karpathy

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### What we ported

- **`autoresearch-ml-skill/templates/program.md`** — verbatim copy of
  karpathy's `program.md` (the canonical ML overnight-loop instructions), with
  a license-header comment prepended pointing back to this file.
- **`autoresearch-ml-skill/templates/prepare.py.template`** — parameterized
  derivation of karpathy's `prepare.py` (constants `MAX_SEQ_LEN`, `EVAL_TOKENS`,
  `VOCAB_SIZE` exposed as `{{...}}` placeholders for non-H100 platforms).
- **`autoresearch-ml-skill/templates/train.py.template`** — parameterized
  derivation of karpathy's `train.py` with the simplicity-criterion block from
  `program.md` embedded as a comment header.
- **`autoresearch-ml-skill/templates/CPU-FORKS.md`** — the 4 notable forks
  section (miolini/autoresearch-macos, trevin-creator/autoresearch-mlx,
  jsegov/autoresearch-win-rtx, andyluo7/autoresearch) reproduced from
  karpathy's `README.md`.
- **`autoresearch-core-skill/SKILL.md`** "Autonomy Directive" section — the
  NEVER STOP directive and the git-as-memory keep/revert pattern derive from
  karpathy's `program.md` §The experiment loop.

## 3. wjgoarxiv/autoresearch-skill

**Upstream:** <https://github.com/wjgoarxiv/autoresearch-skill>
**License:** MIT
**Copyright:** Copyright (c) 2026 wjgoarxiv contributors

### MIT License (verbatim)

```
MIT License

Copyright (c) 2026 wjgoarxiv contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### What we ported

- **`autoresearch-core-skill/references/evaluator-contract.md`** — the strict
  `{"pass":bool,"score":N}` JSON evaluator shape (boolean `pass` for keep/revert
  + numeric `score` for the audit trail) is adopted from wjgoarxiv's
  autoresearch-skill, layered on top of uditgoenka's Verify/Guard distinction.
  We do not copy wjgoarxiv's files verbatim; the contract shape is the
  contribution cited here.

## 4. microsoft/markitdown + markitdown-mcp

**Upstream:** <https://github.com/microsoft/markitdown>
**License:** MIT
**Copyright:** Copyright (c) Microsoft Corporation.

### How we consume it (#487)

- **`markitdown-mcp` (PyPI, pinned `==0.0.1a7`)** — the official MCP server is
  installed from PyPI at deploy time (setup.sh / setup.ps1).
  **No upstream markitdown or markitdown-mcp source code lives in
  this repo** — the former in-repo wrapper was retired in #487.
- The server pulls `markitdown[all]`; its cloud-capable extras are present but
  dormant (Azure converters require constructor kwargs that are never passed).
  Accepted residual: audio inputs upload to Google Speech, YouTube URLs contact
  YouTube — documented in the root README.

### MIT License (upstream, verbatim)

```
MIT License

Copyright (c) Microsoft Corporation.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## 5. greensock/gsap-skills

**Upstream:** <https://github.com/greensock/gsap-skills>
**License:** MIT
**Copyright:** Copyright (c) 2026 GreenSock

### What we vendor

- **`skills/gsap-*/SKILL.md`** — the eight official GSAP
  skills (`gsap-core`, `gsap-timeline`, `gsap-scrolltrigger`, `gsap-plugins`,
  `gsap-utils`, `gsap-react`, `gsap-performance`, `gsap-frameworks`) copied
  verbatim from upstream `skills/`, plus two frontmatter keys added locally
  for this repo's contract (`compatibility: opencode`,
  `category: Frontend Animation`). No upstream plugin/runtime code is
  embedded — GSAP itself is consumed from the public `gsap` npm package at
  the target project's build time.

### MIT License (verbatim)

```
MIT License

Copyright (c) 2026 GreenSock

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Optional dependency: docling (not ported — pip-installed on demand)

`docling` and `docling-mcp[local]` are **not shipped in this repository** — they are PyPI packages installed on-demand when the user explicitly runs `--enable-pack docling` (Decision 6: not baked by default, ~3-4 GB). Their licenses are carried by the pip packages themselves. Key transitive licenses:

| Package | License | Purpose |
|---------|---------|---------|
| `docling` / `docling-core` | MIT | Layout-aware document parsing |
| `torch` | BSD-style | Tensor computation (ML models) |
| `rapidocr` | Apache-2.0 | OCR engine |
| `transformers` (huggingface) | Apache-2.0 | ML model loading |

**Trust boundary:** unlike markitdown (zero phone-home, fully local), docling downloads ML models from `huggingface.co` on first use (~hundreds of MB, cached thereafter). See the `docling` route's trust-boundary section in `office-document-router-skill` for details.

## License of this repository

This repository is licensed under Apache-2.0 — see `LICENSE`. All ported
MIT-licensed content above remains redistributable under both MIT and Apache-2.0
terms; the upstream copyright notices in this file are preserved per Apache-2.0 §4(c).
