# PLAN: Archive superlocalmemory data to S3 dataset and purge references

**Branch**: feat/681
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/681
**Base**: main

## Acceptance Criteria
- [ ] `s3://silentx-opencode-dataset/memory/memories.jsonl` contains exactly 234 lines, one `_type: "memory"` entry each, embeddings preserved
- [ ] `s3://silentx-opencode-dataset/memory/superlocalmemory-raw-2026-10-31.json` is a byte-identical copy of `~/.superlocalmemory/memories.json`
- [ ] `manifest.jsonl` gains a `_type: "memories-archive"` entry naming both keys; all 2,825 pre-existing session entries intact
- [ ] Manifest `memories-archive` entry records `"embedding_model": "xenova/all-MiniLM-L6-v2 (384-dim; inferred from vector width + plugin default config — not recorded in source)"`
- [ ] Post-upload verification passes: S3 object sizes + line counts match local sources
- [ ] `~/.superlocalmemory/` deleted only after verification passes
- [ ] `plugins/opencode-learnings-autoinject.README.md` rewritten to stand alone (no plugin mention, lines 12/70)
- [ ] `deploy/.AGENTS.md` watch-note dropped; the memory-hygiene line still explains the markdown LEARNINGS system
- [ ] `README.md:361` stale pointer fixed
- [ ] `CHANGELOG.md` untouched (immutable history)
- [ ] Deployed user-space copies (`~/.config/opencode/AGENTS.md`, `~/.config/opencode/plugins/opencode-learnings-autoinject.README.md`) synced from updated source

## Dependency & Consumer Map

| Node (file/module) | Depends on (must precede) | Consumers (who depends on this) | Change risk |
|---------------------|---------------------------|---------------------------------|-------------|
| `~/.superlocalmemory/memories.json` (source data) | — | Phase 1 conversion + raw upload | high (sole copy — never mutated, only read; deletion gated on verify) |
| `s3://…/memory/memories.jsonl` | source conversion (1.1) | future memory re-import / dataset analysis | medium |
| `s3://…/memory/superlocalmemory-raw-2026-10-31.json` | — (byte copy) | archival provenance / re-derivation | low |
| `s3://…/manifest.jsonl` | existing 2,825 session entries | dataset integrity for all consumers | medium (full-replace upload — must re-verify entry count) |
| `plugins/opencode-learnings-autoinject.README.md` | — | plugin docs readers; ships with skill installs | low |
| `deploy/.AGENTS.md` | — | deploys to `~/.config/opencode/AGENTS.md` (every session's instructions) | low |
| `README.md` (§Knowledge persistence, line 361) | — | repo readers / install docs | low |
| `~/.superlocalmemory/` deletion (3.3) | 1.4 verification pass | none (orphaned store) | low once gated |

## Implementation Phases

### Phase 1: S3 archive — convert, upload, manifest, verify
- [x] **1.1** Convert `~/.superlocalmemory/memories.json` to `memory/memories.jsonl` in a scratch dir: one JSON line per memory with `_type: "memory"`, `id`, `content`, `containerTag`, `metadata`, `embedding`, `createdAt`, `updatedAt`; assert exactly 234 lines and every line parses as JSON
    — **Why:** the dataset bucket's convention is typed JSONL (matches the 2,825 `_type: "session"` manifest entries); conversion must be verified before anything touches S3
    — **Done when:** scratch `memories.jsonl` has 234 lines, `python3 -c 'json.loads'` succeeds per line, embedding arrays present with length 384
    — **Consumers affected:** 1.2 upload
    — **Done:** 234 records serialized, all lines parse, all embeddings 384-dim (2,183,968 bytes); files: .scratch-681/memories.jsonl; fixes: none
- [x] **1.2** Upload raw source + converted JSONL to `s3://silentx-opencode-dataset/memory/` (`superlocalmemory-raw-2026-10-31.json` byte-copy + `memories.jsonl`)
    — **Why:** the raw copy preserves provenance and enables byte-level re-derivation; the JSONL is the dataset-consumable form
    — **Done when:** `aws s3 ls` shows both objects under `memory/` with sizes matching local byte counts
    — **Consumers affected:** 1.3 manifest, 1.4 verification
    — **Done:** both objects uploaded; remote sizes 2,923,209 + 2,183,968 match local; files: s3://…/memory/*; fixes: none
- [x] **1.3** Download `manifest.jsonl`, append one `_type: "memories-archive"` entry naming both S3 keys, line counts, byte sizes, memory count 234, and `embedding_model` provenance string, then re-upload (full replace)
    — **Why:** the manifest is the dataset's index — S3 has no append so replacement is the only path; provenance prevents a future re-import from embedding queries with the wrong model
    — **Done when:** uploaded manifest has 2,826 lines (2,825 `_type: "session"` + 1 `memories-archive`), and the new entry carries the `embedding_model` string
    — **Consumers affected:** 1.4 verification
    — **Done:** baseline re-measured 2,825/2,825 at execution time; concurrent-write check passed (remote still 2,825 pre-upload); replaced with 2,826 lines; files: .scratch-681/manifest.jsonl, s3://…/manifest.jsonl; fixes: none
- [x] **1.4** Verify: re-download both memory objects, `cmp` the raw against `~/.superlocalmemory/memories.json`, recount JSONL lines, re-download manifest and grep entry count + session-entry intactness
    — **Why:** AC gates `~/.superlocalmemory/` deletion on verified upload — the sole local copy must not be removed on unverified evidence
    — **Done when:** `cmp` exits 0, JSONL = 234 lines, manifest = 2,826 lines with 2,825 session entries; all four checks printed
    — **Consumers affected:** 3.3 deletion gate
    — **Done:** CHECK 1 cmp exit 0; CHECK 2 234 lines; CHECK 3 2,826 = 2,825 session + 1 archive w/ embedding_model; CHECK 4 sizes match; files: .scratch-681/verify-*; fixes: none

### Phase 2: Repo prose purge
- [ ] **2.1** Rewrite `plugins/opencode-learnings-autoinject.README.md` §Why to stand alone (motivation = OpenCode does not auto-scan `LEARNINGS/`, per continuous-learning-skill) and drop the `opencode-superlocalmemory` compatibility bullet (line 70)
    — **Why:** the referenced plugin is neither installed nor planned; docs must describe the plugin as shipped, not as a companion to a removed one
    — **Done when:** `grep -i superlocalmemory` over the file returns nothing
    — **Consumers affected:** plugin docs readers
- [ ] **2.2** Edit `deploy/.AGENTS.md` Memory Hygiene line: drop the watch-note (`memory` tool plugin / `opencode-superlocalmemory`), keep the LEARNINGS + auto-inject manifest explanation intact
    — **Why:** the watch-note references a plugin that will never return in this form; the survival requirement is that the line still explains where memory lives
    — **Done when:** `grep -i superlocalmemory deploy/.AGENTS.md` returns nothing and the line still names `LEARNINGS/*.md` + the auto-inject manifest + `continuous-learning-skill`
    — **Consumers affected:** deployed `~/.config/opencode/AGENTS.md` (synced in 3.1)
- [ ] **2.3** Fix `README.md:361`: correct the stale "watch-list … in `AGENTS.md` § Project Learnings" pointer to reference `deploy/.AGENTS.md` §Memory Hygiene (or drop the parenthetical once the watch-list no longer exists anywhere)
    — **Why:** the pointer names a section that no longer holds a watch-list — after 2.2 it holds nothing anywhere
    — **Done when:** no README line claims a watch-list lives in `AGENTS.md` § Project Learnings
    — **Consumers affected:** repo readers
- [ ] **2.4** Grep-verify the whole repo: `superlocalmemory` appears only in `CHANGELOG.md`
    — **Why:** AC requires CHANGELOG untouched (immutable history) and zero mentions elsewhere
    — **Done when:** `grep -ril superlocalmemory .` returns only `CHANGELOG.md`
    — **Consumers affected:** none

### Phase 3: Deployed-copy sync + local deletion
- [ ] **3.1** Sync the two deployed user-space copies from updated source: `cp deploy/.AGENTS.md ~/.config/opencode/AGENTS.md` and `cp plugins/opencode-learnings-autoinject.README.md ~/.config/opencode/plugins/`
    — **Why:** house rule is edit-source-then-sync (never hand-edit deployed copies); a full `setup.sh` redeploy is unnecessary for two byte-copies
    — **Done when:** `grep -i superlocalmemory ~/.config/opencode/AGENTS.md ~/.config/opencode/plugins/opencode-learnings-autoinject.README.md` returns nothing and file checksums match source
    — **Consumers affected:** every future OpenCode session (prompt instructions)
- [ ] **3.2** Commit repo prose changes (Phase 2 edits) and push
    — **Why:** pipeline convention — per-phase atomic commits on `feat/681`
    — **Done when:** `git log origin/feat/681` shows the prose-purge commit; `git status` clean in the worktree
    — **Consumers affected:** PR review (Step 9/10)
- [ ] **3.3** Delete `~/.superlocalmemory/` — only after 1.4 passed
    — **Why:** AC requires the last physical plugin remnant removed, strictly gated on verified upload
    — **Done when:** `ls ~/.superlocalmemory` errors with "No such file or directory"
    — **Consumers affected:** none

## Trace
GATE 29e3961 tier=light lint=n.a typecheck=n.a build=n.a unit=n.a e2e=n.a — docs/ops-only phase, no tracked-file diff; gate evidence = the four Done-when verifications (all pass)

## Technical Notes
- Embedding model is NOT recorded in the source file — provenance string in the manifest is the fix (384-dim vectors + plugin default config ⇒ `Xenova/all-MiniLM-L6-v2`).
- S3 is object storage, not git: "commit and push" = `aws s3 cp` + full manifest replace. Bucket is private (public access block on), same trust domain as the 2,826 session objects already present.
- Conversion scratch dir: `/home/silentx/VSCODE/worktrees/681/.scratch-681/` (inside worktree, never committed — remove in 3.3's cleanup or leave for worktree removal).
- The bucket count baseline (2,825 manifest lines / 2,826 objects incl. manifest) was measured 2026-10-31; re-count at execution time in case of drift and record actuals in the manifest entry.

## Dependencies
None — single ticket, no `blocked-by`.

## Risks & Mitigation
- **Sole-copy data loss** (memories.json is the only copy): deletion strictly gated on 1.4 byte-compare; raw upload lands before any manifest work.
- **Manifest clobber** (concurrent dataset writes): download → append → re-upload is a small window; re-count session entries immediately before re-upload and abort if the base count shifted from the 1.3 download.
- **Drift in AC numbers** (234 entries / 2,825 sessions measured at ticket time): execution re-measures; deltas are recorded, not forced.
