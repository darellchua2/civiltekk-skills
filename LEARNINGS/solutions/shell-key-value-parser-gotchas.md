# Shell KEY<value> line parsers: quote `<` in case patterns, strip the wrapper

**Date**: 2026-10-31 · **Confidence**: High · **Scope**: bash parsers fed by node/CSV emit

## Summary

Two bash gotchas hit while writing `install_pack_runtime`'s `KEY<value>`
parser (package specs carry commas/brackets, so the node side emits
newline-delimited `PKG<spec>` lines): (1) `<` is a metacharacter in `case`
patterns — `'PKG<'*)` needs the literal quoted or bash dies with "syntax
error near unexpected token `<`"; (2) `${line#PKG<}` strips only the prefix,
leaving the closing `>` on the value (`none>`) — strip prefix AND trailing
`>`. Also: `printf '%s\n'` with a REAL newline inside the source string
splits python/awk line-based extraction — splice scripts must re-add the
trailing newline before appending a closing brace.

**Evidence**: deploy/setup.sh `install_pack_runtime` case block; #677 phase 1.

## Rule

Quote redirection characters in case patterns; wrapper-delimited values need
both ends stripped; never trust line-based tooling on sources containing
multi-line string literals.
