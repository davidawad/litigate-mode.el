# litigate-mode.el

An Emacs major mode for litigate: `.lit` rule modules and `.case` matters.
litigate is a typed language for encoding procedural-law rules and matters;
its compiler also ships a language server, `litigate lsp --stdio`.

The mode is built on Emacs's built-in tree-sitter support (`treesit`, Emacs
29.1+ built with tree-sitter) and the grammar
[tree-sitter-litigate](https://github.com/davidawad/tree-sitter-litigate).
Without the grammar it still loads and falls back to regexp font-lock, so
installing the package first and the grammar second is safe.

Editor support for litigate: this package (Emacs),
[tree-sitter-litigate](https://github.com/davidawad/tree-sitter-litigate)
(the grammar), [litigate.vim](https://github.com/davidawad/litigate.vim)
(Vim, Neovim) and [helix-litigate](https://github.com/davidawad/helix-litigate)
(Helix).

## What it does

- **Syntax highlighting** (`treesit-font-lock-level` 3 by default; 4 adds
  operators, brackets, delimiters and plain identifiers): comments and doc
  comments, strings and escapes, citations (`cite FRCP 8(c)(1)` -- the
  keyword and the citation text get different faces), every keyword,
  declared names (`rule`, `deadline`, `chance`, events, types, ...), numbers,
  money, durations and dates, record keys, builtin calls
  (`deadline(...)`, `has_event(...)`), and `?` holes. The keyword, operator
  and indent-type lists mirror the grammar's `highlights.scm`/`indents.scm`;
  the test suite checks that they stay equal.
- **Indentation**: `treesit-simple-indent-rules` mirroring `indents.scm`.
  Two spaces per level (`litigate-mode-indent-offset`), the canonical
  `litigate fmt` format; re-indenting a canonically formatted file changes
  nothing.
- **Navigation**: `imenu` lists modules, cases, nodes, edges, types, events,
  rules, deadlines, counting rules, calendars, transitions, tests and
  parties; `beginning-of-defun`/`end-of-defun` (`C-M-a`, `C-M-e`) move
  between top-level declarations; with Emacs 30+, `outline-minor-mode` folds
  over them.
- **Eglot**: registers `litigate lsp --stdio` for `litigate-mode`, so
  `M-x eglot` starts the language server. `litigate-mode-lsp-command`
  changes the command.

`litigate-ts-mode` (the name this mode had inside litgraph) is kept as an
alias of `litigate-mode`.

## Install

### 1. The package

#### straight.el

```elisp
(straight-use-package
 '(litigate-mode :type git :host github :repo "davidawad/litigate-mode.el"
                 :files ("src/litigate-mode.el")))
```

#### use-package + straight.el

```elisp
(use-package litigate-mode
  :straight (:type git :host github :repo "davidawad/litigate-mode.el"
             :files ("src/litigate-mode.el"))
  :mode ("\\.lit\\'" "\\.case\\'")
  :hook (litigate-mode . eglot-ensure))
```

#### Manual

Clone this repo and add its `src/` directory to your `load-path`:

```elisp
(add-to-list 'load-path "/path/to/litigate-mode.el/src")
(require 'litigate-mode)
```

`litigate-mode.el` registers itself for `*.lit` and `*.case` in
`auto-mode-alist`, and adds the language server to `eglot-server-programs`
once Eglot loads.

### 2. The grammar

```
M-x litigate-mode-install-grammar
```

That clones tree-sitter-litigate at `litigate-mode-grammar-rev` (a pinned
commit -- an unpinned grammar can silently change how your files highlight),
builds it with the `tree-sitter` CLI and writes `libtree-sitter-litigate` to
`<user-emacs-directory>/tree-sitter/`, where `treesit` looks. It needs `git`,
a C compiler and the CLI (`cargo install tree-sitter-cli` or
`npm i -g tree-sitter-cli`).

The committed grammar parser is tree-sitter **ABI 15**. If your Emacs is
linked against a libtree-sitter older than 0.25 it can only load ABI 14;
`litigate-mode-install-grammar` asks Emacs (`treesit-library-abi-version`)
and regenerates the parser at that ABI, which additionally needs node.

Alternatively, on Emacs 30+ with an ABI 15 libtree-sitter,
`M-x treesit-install-language-grammar RET litigate` works too -- the mode adds
the pinned source to `treesit-language-source-alist`.

Check: open a `.lit` file; the mode line says `litigate`, and
`(treesit-ready-p 'litigate)` returns `t`.

## Language server

`litigate` must be on Emacs's `exec-path` (a daemon Emacs does not inherit
your shell `PATH`):

```elisp
(add-hook 'litigate-mode-hook #'eglot-ensure)   ; or: M-x eglot
```

`litigate-mode-lsp-command` defaults to `("litigate" "lsp" "--stdio")`. The
project root is found by Eglot's usual project detection (a git repo; the
litigate manifest is `Lit.toml`, the lock `Lit.lock`).

## Tests

ERT tests live in `test/litigate-mode-test.el`:

```sh
emacs -Q --batch -L src -l src/litigate-mode.el \
  -l test/litigate-mode-test.el -f ert-run-tests-batch-and-exit
```

Environment, all optional: `LITIGATE_TS_GRAMMAR_DIR` (directory holding
`libtree-sitter-litigate`, when it is not where `treesit` already looks),
`LITIGATE_CORPUS` (a directory walked for every `.lit`/`.case` file instead
of `examples/`) and `LITIGATE_GRAMMAR_SRC` (a tree-sitter-litigate checkout;
enables the two tests that compare this mode's keyword and indent lists with
the grammar's queries -- skipped otherwise, and a skip is not a pass). The
suite checks that every corpus file opens in the mode, parses with no error
node, fontifies and re-indents to itself; faces, imenu, defun navigation,
the `auto-mode-alist`/Eglot/`treesit-language-source-alist` registrations, and
the regexp fallback with the grammar missing.

`checkdoc-file` and `batch-byte-compile` (with `byte-compile-error-on-warn`)
should both be silent on `src/litigate-mode.el` before any change lands.

## Examples

`examples/` holds a real rule module (`rule12.lit`, FRCP Rule 12), a real
matter (`acme.case`) and the manifest (`Lit.toml`), copied from litgraph.

## Known limitations

- Needs Emacs 29.1+ built with tree-sitter for anything beyond the regexp
  fallback. The fallback leaves contextual keywords (`p`, `on`, `from`, ...)
  uncolored, since without a parse tree they cannot be told from names.
- Outline folding needs Emacs 30+ (`treesit-outline-predicate`).
- The mode does not call the compiler for diagnostics; that is the language
  server's job.

## Provenance

Seeded on 2026-10-23 from `editors/emacs/litigate-ts-mode.el` in litgraph
(commit `6dbf033`), restructured to the layout of
[bend-mode.el](https://github.com/davidawad/bend-mode.el): `src/`, `test/`,
`examples/`, renamed to `litigate-mode`, with the grammar fetched from the
pinned grammar repo (`litigate-mode-install-grammar`) instead of built by a
Rust tool, and the regexp fallback added. litgraph keeps its in-repo copy.

## License

GPL-3.0-or-later, the license of litgraph, where this was seeded from -- see
[LICENSE](LICENSE).
