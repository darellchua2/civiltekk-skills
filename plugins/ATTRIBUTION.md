# Attributions

## vibeguard (`opencode-vibeguard`)

`plugins/opencode-vibeguard-v2.ts` is a single-file OpenCode **v2** port of
[opencode-vibeguard](https://github.com/inkdust2021/opencode-vibeguard) v0.1.0 by inkdust2021.

- **Upstream:** https://github.com/inkdust2021/opencode-vibeguard (npm: `opencode-vibeguard@0.1.0`)
- **License:** MIT (see full text below)
- **What was ported:** the redaction engine, pattern set (incl. builtins), placeholder
  session (HMAC-SHA256 `__VG_<CATEGORY>_<hash12>__` placeholders, TTL + eviction),
  deep object walk, and restore logic — essentially verbatim from upstream
  `src/{config,engine,session,deep,restore,patterns}.js`.
- **What changed:** the plugin entrypoint was rewritten for the v2 plugin API
  (`ctx.session.hook("context"|"generate")` for outbound masking,
  `ctx.tool.hook("execute.before")` for tool-input restore). Config discovery,
  placeholder format, and fail-open-when-disabled semantics are unchanged, so
  existing `vibeguard.config.json` files work as-is.
- **Why a local port:** V1 plugin implementations do not run on OpenCode v2 and
  upstream has no v2 release. The npm pin was removed from the `plugins` array
  (double-registration guard) in favor of this vendored port.

## ponytail (`@dietrichgebert/ponytail`)

This directory (`plugins/ponytail/`) contains code vendored and adapted from the
[ponytail](https://github.com/DietrichGebert/ponytail) project by Dietrich Gebert.

- **Upstream:** https://github.com/DietrichGebert/ponytail
- **Pinned version:** v4.10.0 (tag `v4.10.0`)
- **License:** MIT (see full text below)
- **Files vendored:**
  - `SKILL.md` — the ponytail ruleset (copied verbatim from `skills/ponytail/SKILL.md`)
  - `instructions.cjs` — adapted from `hooks/ponytail-instructions.js` and
    `hooks/ponytail-config.js` (mode-filtering logic preserved; Claude-Code-specific
    config-file paths dropped; reads the co-located `SKILL.md`)
  - `../skills/civiltekk-ponytail-audit-skill/SKILL.md` (+ its
    `references/{audit,review,debt}.md` values) — consolidates
    `skills/ponytail-audit/SKILL.md`, `skills/ponytail-review/SKILL.md`, and
    `skills/ponytail-debt/SKILL.md` (house frontmatter; sibling/command refs
    renamed; #603)
  - Upstream satellite command wrappers (`.opencode/command/*.md`) NOT vendored —
    the scoped plugin owns the `/ponytail*` command namespace.
- **Adaptation rationale:** vendoring (vs `require("@dietrichgebert/ponytail")`) removes
  the stock OpenCode
  adapter from the dependency tree (double-injection guard), and lets the wrapper
  plugin (`../opencode-ponytail-scoped.ts`) add agent-type-aware scoping that the upstream
  adapter does not support on OpenCode.

Re-vendor deliberately on upstream bumps: update `SKILL.md` from the new tag and
re-check `instructions.cjs` against the upstream instruction builder.

---

## pstack (`cursor/plugins`)

The following skills are vendored verbatim from the
[pstack](https://github.com/cursor/plugins/tree/main/pstack) collection by poteto.

- **Upstream:** https://github.com/cursor/plugins
- **Pinned commit:** `60c641e4fad674784b30abcf9f8915dea39df38d` (main, 2026-08-19)
- **License:** MIT (see full text below)
- **Files vendored:**
  - `../skills/unslop-skill/SKILL.md` — verbatim from `pstack/skills/unslop/SKILL.md`
  - `../skills/technical-writing-skill/SKILL.md` — verbatim from
    `pstack/skills/technical-writing/SKILL.md` (`unslop` sibling refs renamed)
  - `../skills/blast-radius-skill/SKILL.md` — verbatim from
    `pstack/skills/blast-radius/SKILL.md` (`how`/`why`/`arena` sibling refs
    neutralized — those skills are not vendored in this repo)

Re-vendor deliberately on upstream bumps: re-fetch from the new pinned commit and
re-apply only frontmatter + sibling-ref adaptations.

### MIT License (upstream ponytail)

```
MIT License

Copyright (c) Dietrich Gebert

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

---

### MIT License (upstream pstack)

Copyright (c) poteto. Same standard MIT terms as the license text above;
substitute the copyright line accordingly.

---

## laya-guard (`@receptron/laya` + Convai Innovations model weights)

`plugins/opencode-laya-guard.ts` and the `plugins/laya-guard/` sidecar are
self-authored, but the classification stack they drive is third-party:

- **JS client:** [@receptron/laya](https://github.com/receptron/laya)
  (npm `@receptron/laya@0.1.2`) — **MIT**. Not vendored: installed at
  provision time into `~/.cache/laya-guard/node_modules` by `deploy/setup.sh`,
  pinned to the exact version in `plugins/laya-guard/package.json`.
- **Model weights:** [Laya](https://huggingface.co/convaiinnovations/laya) by
  Convai Innovations — **Apache-2.0**. 421M-parameter ModernBERT-large
  decision model. ONNX bundle from `receptron/laya-onnx`, revision `68f27df`,
  pulled by laya's own downloader (`warm.mjs` / lazy first load).
- **Runtime:** `onnxruntime-node` + `@huggingface/tokenizers` (transitive
  dependencies of the client; Apache-2.0 / MIT respectively).

The plugin file itself is deliberately dependency-free (house pattern,
vibeguard-v2 precedent) — opencode never loads these packages; the Node
sidecar does.
