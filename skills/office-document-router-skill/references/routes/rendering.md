# Route: RENDERING

**Load when:** rendering document deliverables to the shared HTML (sidebar, dark mode, self-contained) and DOCX (auto-TOC, hyperlinks) standard — consumed by vision/SRS/BRD generation.
**Skip when:** spreadsheets (Route: XLSX) or decks (pptx-specialist-subagent) — peer deliverables, linked not embedded.


## What I do

I am the **single source of truth** for how document-creation skills render their Markdown sources into two complementary deliverables:

1. **Interactive HTML** — a self-contained, navigable, dark-mode-aware web page
2. **Word (.docx)** — a formal deliverable with auto-generated TOC and hyperlinked headers

Consumers (`solution-docs-skill` routes VISION/BRD/SRS/TECHNICAL-DESIGN) reference me via *"Render dual outputs per `Route: RENDERING`."* They do NOT redefine HTML/DOCX styling themselves — that would re-introduce the inconsistency this skill exists to eliminate.

## SCOPE — what I do NOT do

- **No `.xlsx`.** Tabular artifacts (RTM, data dictionaries, requirement registers) are produced by `Route: XLSX`/`xlsx-specialist-subagent` as **peer deliverables**, linked from the doc — never embedded in HTML/DOCX.
- **No `.pptx`.** Customer presentation decks are produced by `pptx-specialist-subagent` as peer deliverables.
- **No image interpretation.** If image content must be understood (screenshots, reference images, diagrams), **delegate to `image-analyzer-subagent`** — do not attempt to interpret images inline.

This keeps each format's tooling owned by its specialist and the rendering skill focused on HTML + DOCX.

## When to regenerate: living vs snapshot

| Doc type | HTML lifecycle | When to (re)render |
|---|---|---|
| **Vision** (discovery, customer) | **Living** — updated through the session | After each wireframe/feedback round so the client always sees current state; cheap to regenerate |
| **SRS / BRD** (internal) | **Snapshot** | Rendered once at wrap, after all sections are confirmed |

The living model applies to discovery only; internal docs render a single final snapshot.

## Naming & placement

| Artifact | Path |
|---|---|
| Source Markdown | `docs/{type}/{NAME}-{slug}.md` (e.g. `docs/vision/VISION-inventory.md`, `docs/srs/SRS-{key}.md`) |
| Interactive HTML | `docs/{type}/{slug}/{NAME}.interactive.html` |
| Word deliverable | `docs/{type}/{NAME}-{slug}.docx` |
| Peer xlsx | `docs/{type}/{slug}/{NAME}-{artifact}.xlsx` (linked, not embedded) |

`{type}` ∈ {`vision`, `srs`, `brd`}. `{slug}` is kebab-case from the title. HTML and peer artifacts are co-located under a per-slug subfolder.

---

## HTML Standard

Every interactive HTML document MUST be **self-contained** (no external CSS/JS CDNs — inline `<style>` and `<script>` only) so it renders identically when opened from disk or shared offline.

### Required structure

```html
<!DOCTYPE html>
<html lang="en" data-theme="light">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{Document Title}</title>
  <style>/* see Theming + Layout below */</style>
</head>
<body>
  <div class="layout">
    <aside class="sidebar" id="sidebar">
      <button class="theme-toggle" id="themeToggle" aria-label="Toggle dark mode">☾</button>
      <nav id="nav"><!-- auto-generated from H1–H3 --></nav>
    </aside>
    <main class="content">
      <!-- rendered Markdown body -->
    </main>
  </div>
  <script>/* sidebar nav gen + theme toggle + scroll-spy */</script>
</body>
</html>
```

### Left sidebar navigation (auto-generated)

The `<nav>` is populated from the document's `H1`–`H3` at render time (client-side JS), so the renderer does not need to parse headings in advance:

1. Query all `h1, h2, h3` inside `<main>` in document order.
2. For each, generate an `id` from its text (slugified) if none exists.
3. Build a nested `<ul>` (H1 → top-level, H2 → nested, H3 → nested-nested) of anchor links.
4. Active link follows scroll position (scroll-spy): highlight the nav entry whose heading is currently in view.

### Dark-mode-aware theming (REQUIRED)

The `<html>` carries `data-theme="light"|"dark"`. The toggle button flips it and persists the choice in `localStorage`.

- All colors MUST be defined as CSS custom properties on `:root` and `[data-theme="dark"]` — **never hard-coded** in rules. Example:

```css
:root {
  --bg: #ffffff;
  --bg-sidebar: #f6f7f9;
  --text: #1a1a1a;
  --text-muted: #5a6472;
  --accent: #2563eb;
  --border: #e2e6ec;
  --selection-bg: #cfe0ff;
  --selection-text: #0b2545;
}
[data-theme="dark"] {
  --bg: #0f1115;
  --bg-sidebar: #161a21;
  --text: #e7eaf0;
  --text-muted: #97a1b1;
  --accent: #6ea0ff;
  --border: #272d36;
  --selection-bg: #1f3a66;
  --selection-text: #ffffff;
}
```

### Color-aware text selection (REQUIRED)

Because selection color must adapt to the active theme, define `::selection` via the theme variables — **do not** set a single fixed selection color:

```css
::selection {
  background: var(--selection-bg);
  color: var(--selection-text);
}
```

This guarantees selected text remains legible in both light and dark modes.

### Layout & responsiveness

- Sidebar fixed-width (~260px) on desktop, collapses to a hamburger on `< 900px`.
- Content area is the scroll container; the sidebar nav scroll-spys against it.
- Use the theme variables for all backgrounds/borders/typography — no hard-coded hex outside `:root`/`[data-theme]`.

### Self-containment checklist

- [ ] All CSS inlined in a single `<style>` block (no `<link rel="stylesheet">` to external hosts)
- [ ] All JS inlined in a single `<script>` block (no external CDN)
- [ ] Fonts: system font stack only (`-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif`)
- [ ] No `fetch()`/network calls at runtime
- [ ] Opens correctly via `file://` with no console errors

---

## DOCX Standard (Word)

The Word deliverable is the **formal output** for sign-off and stakeholder distribution. It MUST have:

### Auto-generated Table of Contents

Insert a real Word TOC **field** (not a manually typed list) so it updates when the document changes:

- Field code: `{ TOC \o "1-3" \h \z \u }` — headings levels 1–3, hyperlinked, hide tab leader, outline levels.
- Mark it "update field on open" so stale TOCs self-heal.

### Hyperlinked headers / bookmarks

- Every `Heading 1`–`Heading 3` style application auto-creates a bookmark target for TOC linking.
- Internal cross-references (e.g. "see §3.2") should be hyperlinks to those bookmarks, not plain text.

### Heading style map

Map the Markdown source headings to Word built-in styles (do not invent custom styles):

| Markdown | Word Style |
|---|---|
| `#` | Heading 1 |
| `##` | Heading 2 |
| `###` | Heading 3 |
| body | Normal |
| tables | Table Grid |

### Section page-breaks

Insert a page break before each top-level (`##`) major section so each section starts on a new page in the formal deliverable. (Inline sub-sections do not force breaks.)

### Consistency rules

- Title page: document title, status, author, date, and (where applicable) the `**SRS**:`/`**VISION**:` back-link line.
- Numbered headings optional but recommended for SRS/BRD (1, 1.1, 1.1.1) to match IEEE 830 structure.
- Tables: `Table Grid` style with a shaded header row.

---

## Image routing clause

If rendering requires **understanding** image content (e.g. a client attached a screenshot of their current system during discovery, or an architecture diagram must be described), **do NOT attempt to interpret it inline** — delegate to `image-analyzer-subagent` and incorporate its structured description into the document. The renderer's job is to embed/link images and apply the HTML/DOCX standard, not to analyze them.

---

## Related

- `solution-docs-skill` route `vision` — discovery Vision Doc; uses **living** HTML regen
- `solution-docs-skill` routes `srs` (IEEE 830 SRS) + `brd` (BABOK BRD) + `technical-design` (TDD); snapshot HTML at wrap
- `Route: XLSX` / `xlsx-specialist-subagent` — peer tabular deliverables
- `pptx-specialist-subagent` — peer presentation deliverables (requires user-supplied Slide Master template)
- `image-analyzer-subagent` — image interpretation (delegate, don't inline)
- `Route: DOCX` / `docx-creation-subagent` — the actual Word file generation (this skill defines the standard they follow)
