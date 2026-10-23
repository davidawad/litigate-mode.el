# AGENTS.md -- litigate-mode.el

Standalone, publishable Emacs major mode for litigate (`.lit` rule modules,
`.case` matters). Font-lock, indentation, navigation, grammar installation
and Eglot wiring all live in `src/litigate-mode.el`. `examples/` are real
litigate sources copied from litgraph, used as both a doc set and a live
smoke-test fixture.

The grammar is **not** in this repo: it is
[tree-sitter-litigate](https://github.com/davidawad/tree-sitter-litigate),
fetched at the commit pinned in `litigate-mode-grammar-rev`.

## For agents

- Read `README.md` first; it is the complete feature and install reference.
- Tests: ERT in `test/litigate-mode-test.el`, run via `emacs -Q --batch -L src
  -l src/litigate-mode.el -l test/litigate-mode-test.el -f
  ert-run-tests-batch-and-exit`. They need a built grammar
  (`M-x litigate-mode-install-grammar`, or point `LITIGATE_TS_GRAMMAR_DIR`
  at a directory holding `libtree-sitter-litigate`). Set
  `LITIGATE_GRAMMAR_SRC` to a tree-sitter-litigate checkout to run the two
  tests that keep the keyword/operator/indent lists equal to its queries; a
  skipped test is not a pass.
- `checkdoc-file` and `batch-byte-compile` should both be silent on the
  source file before any change lands.
- **Bumping the grammar**: change `litigate-mode-grammar-rev`, then re-run
  the suite with `LITIGATE_GRAMMAR_SRC` set to a checkout of that exact
  commit and `LITIGATE_CORPUS` pointing at a directory of real `.lit`/`.case`
  files (litgraph's `lit/` and `cases/`). The keyword and indent lists in
  `src/litigate-mode.el` must be updated by hand when the grammar's
  `highlights.scm`/`indents.scm` change; the ERT suite fails until they match.
- The grammar's committed parser is ABI 15. `litigate-mode-install-grammar`
  regenerates an older ABI when Emacs reports one; keep that branch working.
- Zero references to the owner's dotfiles are allowed here -- the repo must
  remain publishable as-is. THIS repo is canonical; the owner's dotfiles
  import it via `load-path` and carry no copy of the source. All changes land
  here.
- Authorized: david, swe.

## Provenance

Seeded 2026-10-23 from `editors/emacs` in litgraph (commit `6dbf033`),
restructured to the bend-mode.el layout.
