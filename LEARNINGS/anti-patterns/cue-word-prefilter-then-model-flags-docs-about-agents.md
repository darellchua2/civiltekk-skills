# A cue-word pre-filter plus a decision model flags documentation about agents as injection

- **Category**: anti-pattern
- **Confidence**: 0.9
- **Scope**: project
- **Date**: 2026-11-26

A fetched-page injection check (send the two 1,000-character windows with the most prompt/agent cue words to Laya, ask "instructions aimed at an AI agent?") scored 14 of 15 real fetched pages at 0.8 or more (OpenAI and OpenCode docs, opencode source, GitHub issues) and missed 2 of 12 planted injections the cue list did not cover. The filter selects exactly the benign text that discusses prompts, and the base model cannot tell "documentation about instructions" from an injection. Test a guard on real traffic before shipping it; this one was removed (`plugins/laya-guard/README.md`, "Evidence").
