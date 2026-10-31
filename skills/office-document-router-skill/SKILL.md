---
name: office-document-router-skill
description: >-
  Office and document router — one entry point for Word (.docx), Excel
  (.xlsx/.csv), PowerPoint (.pptx), and PDF tasks: creation, editing,
  extraction, forms, OCR, template pipelines, OOXML surgery, thumbnails, and
  the markitdown/docling extraction ladder. Routes each document task to the
  right specialist route.
license: Apache-2.0
compatibility: opencode
metadata:
  protocol: opencode-skill
category: Office & Documents
---

# Office Document Router

One entry point for office-document tasks. Identify the deliverable, run only
the matched route's file, and follow it. All routes share one `scripts/` tree;
the former per-skill copies were consolidated here (#680).

Provenance: routes consolidated from the former office-document skill family
(2026-10, #680); per-route provenance lines live in the route files.

## Routes (load exactly one)

| Task | Route | Read | Skip-when |
|------|-------|------|-----------|
| Word document (.docx) create/read/edit | `docx` | `references/routes/docx.md` | spreadsheet → xlsx, PDF → pdf |
| Spreadsheet (.xlsx/.xlsm/.csv/.tsv) | `xlsx` | `references/routes/xlsx.md` | Word → docx, PDF → pdf |
| PDF: extract/forms/OCR/create | `pdf` | `references/routes/pdf.md` | fast text dump first → markitdown |
| Fill a PPTX template with JSON | `slides` | `references/routes/slides.md` | extract schema → template |
| Extract PPTX → template schema | `template` | `references/routes/template.md` | fill (slides) / extend (modifier) |
| Extend PPTX layouts (clone/promote) | `modifier` | `references/routes/modifier.md` | normal fill → slides |
| Fast local docs→Markdown (MCP) | `markitdown` | `references/routes/markitdown.md` | layout mangled → docling |
| Layout-aware extraction / scanned OCR | `docling` | `references/routes/docling.md` | markitdown sufficed → markitdown |
| Surgical OOXML edit (unpack/edit/repack) | `ooxml` | `references/routes/ooxml.md` | generation → slides/template |
| Office file → thumbnail grids / images | `thumbnails` | `references/routes/thumbnails.md` | text extraction → markitdown |
| Render docs to the shared HTML/DOCX standard | `rendering` | `references/routes/rendering.md` | spreadsheets (xlsx) / decks (pptx-specialist-subagent) |

Route files open with their own **Load when / Skip when** lines. Route detail
files (`references/routes/<id>/`) load when the route names them — never
preload.

## Extraction ladder (spine)

1. Plain text (.md/.txt/.json/code) → built-in `Read`. Nothing else needed.
2. Born-digital office doc or text-selectable PDF → Route `markitdown`
   (fast, local, ~1s/50 pages).
3. markitdown empty/garbage, complex tables, multi-column, or scanned →
   Route `docling` (layout-aware; CLI-on-demand with consent, or the
   persistent MCP pack).
4. Scanned/image-only and no docling → `pdftoppm` → `image-analyzer-subagent`.
5. Structured PDF data (forms, fillable fields, OCR-as-purpose) → Route `pdf`.
6. Visual understanding (charts, layout, "what does this look like") →
   `image-analyzer-subagent` (not a route — a subagent).

## Shared spine (all routes)

- Scripts run from this skill's directory: `scripts/<tool>` as each route
  documents; the LibreOffice wrapper lives at `scripts/soffice.py` (handles
  sandboxed-VM AF_UNIX socket restrictions; auto-configures on first run).
- Documents and spreadsheets must look designed, never generated: typographic
  or visual hierarchy, intentional color, styled headers — each route's
  aesthetics section has the specifics.
- Validate the artifact before handing it back (each route defines its
  validation pass); report assumptions and skipped checks.
- MCP packs (`markitdown`, `docling`) ship disabled by default — enable via
  `./deploy/setup.sh --enable-pack <name>` with user consent; docling's
  CLI-on-demand path asks before installing (~3–4 GB). Never auto-install.

## Hard rules

- Never fabricate chart numbers to pass validation (slides route): every value
  traces to a fetched source; the agent never touches real URLs (placeholders
  only).
- Template fill pipelines use user-supplied templates or the bundled default;
  the base template is never written (modifier clones to `template_new.pptx`).
- Form filling follows the pdf route's ordered steps — never fill with
  unvalidated coordinates.
- Existing template conventions override house aesthetics when updating
  user files (xlsx route).
- Each route file owns its deep detail; this router never restates it.

## Gates

- Zero-preload: only the matched route file (+ its named detail files) enters
  context.
- Report shape complete before declaring done: outputs, checks run/skipped,
  assumptions, risks.
- MCP/CLI enablement goes through the consent-gated pack flow above — never
  auto-install.
