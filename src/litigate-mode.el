;;; litigate-mode.el --- Major mode for litigate (.lit/.case) using tree-sitter  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad
;; URL: https://github.com/davidawad/litigate-mode.el
;; Version: 0.3.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: languages, tree-sitter, litigate
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;;; Commentary:

;; A major mode for litigate rule modules (`.lit') and matters (`.case'),
;; built on Emacs's built-in tree-sitter support (`treesit', Emacs 29+) and
;; the grammar at https://github.com/davidawad/tree-sitter-litigate.  It
;; provides:
;;
;; - font-lock mirroring the grammar's `queries/highlights.scm' (four levels),
;; - indentation mirroring `queries/indents.scm' (two spaces),
;; - imenu and defun navigation from the declarations `queries/locals.scm'
;;   defines,
;; - outline (Emacs 30+) over top-level declarations,
;; - an `eglot' entry for `litigate lsp --stdio',
;; - a `treesit-language-source-alist' entry and `auto-mode-alist' entries
;;   for `.lit' and `.case'.
;;
;; Install the grammar with `M-x litigate-mode-install-grammar', which
;; builds the pinned grammar revision with the `tree-sitter' CLI and picks
;; the parser ABI your Emacs loads.  Without the grammar the mode still
;; works: it falls back to regexp font-lock.  See README.md.

;;; Code:

(require 'treesit)
(require 'subr-x)
(require 'seq)
(eval-when-compile (require 'rx))

(declare-function treesit-parser-create "treesit.c")
(declare-function treesit-node-type "treesit.c")
(declare-function treesit-node-text "treesit.c")
(declare-function treesit-node-child-by-field-name "treesit.c")
(declare-function treesit-node-parent "treesit.c")

(defgroup litigate nil
  "Major mode for the litigate legal-procedure language."
  :group 'languages
  :prefix "litigate-mode-")

(defcustom litigate-mode-indent-offset 2
  "Number of spaces per indentation level in `litigate-mode'.
The canonical format (`litigate fmt') uses two."
  :type 'integer
  :safe #'integerp)

(defcustom litigate-mode-lsp-command '("litigate" "lsp" "--stdio")
  "Command that starts the litigate language server, for `eglot'."
  :type '(repeat string))

(defconst litigate-mode-grammar-url
  "https://github.com/davidawad/tree-sitter-litigate"
  "Git URL of the litigate tree-sitter grammar.")

(defconst litigate-mode-grammar-rev "ceb16e66552f524fde0c47ef6ffcf86dda2499af"
  "Grammar commit this mode is verified against.
Pinned on purpose: an unpinned grammar can silently change how files
highlight and indent.  Bump it deliberately, together with any keyword or
indent-type list that changed.")

;;;###autoload
(defconst litigate-mode-grammar-recipe
  `(litigate ,litigate-mode-grammar-url nil "src" nil nil
             ,litigate-mode-grammar-rev)
  "`treesit-language-source-alist' entry for the litigate grammar.
The seventh element pins the commit (Emacs 30 and later honour it).")

;;;###autoload
(with-eval-after-load 'treesit
  (add-to-list 'treesit-language-source-alist litigate-mode-grammar-recipe))

;;; Keywords (kept equal to queries/highlights.scm by the ERT suite).

(defconst litigate-mode--declaration-keywords
  '("module" "import" "package" "start" "group" "type" "enum" "event"
    "state" "decision" "chance" "terminal" "link" "instance" "rule"
    "deadline" "counting" "calendar" "transition" "authority" "default"
    "exception" "test"
    "case" "uses" "as_of" "known_at" "summary" "notes" "source" "perspective"
    "parties" "events" "facts" "stakes" "beliefs" "observe" "analysis")
  "Keywords that open a declaration.")

(defconst litigate-mode--clause-keywords
  '("forum" "by" "outcome" "p" "effort" "cost" "within" "duration" "min" "mode"
    "max" "sets" "clears" "requires" "forbids" "replaces" "tags" "attrs" "note"
    "valence" "court_listener_url" "action_id" "extendable" "extension_authority"
    "payoff" "payoff_by_flag" "pack" "remove_edges" "probabilities" "roles"
    "payoff_transform" "patch" "duty" "power" "liability" "from" "after" "before"
    "counted_by" "exclude_trigger_day" "include_last_day" "roll_forward_on"
    "service_extension" "holidays" "anchor" "short_period" "below" "count"
    "allow_hours" "effective" "observed" "amends" "subject_to" "notwithstanding"
    "supersedes" "revives" "override" "delegable_to" "rebuts" "undercuts"
    "priority" "url"
    "given" "expect" "on")
  "Clause, field and test keywords.")

(defconst litigate-mode--conditional-keywords
  '("when" "unless" "otherwise" "match")
  "Conditional keywords.")

(defconst litigate-mode--operators
  '("->" "=>" "==" "!=" "<=" ">=" "&&" "||" "+" "-" "*" "/" "%" "!" "=")
  "Operator tokens.")

(defconst litigate-mode--builtins
  '("deadline" "has_event" "prob" "given" "in" "intersect" "disjoint" "len"
    "contains" "fixed" "nth" "last" "every" "once")
  "Builtin functions and holiday rules.")

;;; Font-lock.

(defvar litigate-mode--font-lock-settings
  (treesit-font-lock-rules
   :language 'litigate
   :feature 'comment
   '((doc_comment) @font-lock-doc-face
     [(line_comment) (block_comment)] @font-lock-comment-face)

   :language 'litigate
   :feature 'definition
   '((module_decl path: (module_path (identifier) @font-lock-constant-face))
     (import_decl path: (module_path (identifier) @font-lock-constant-face))
     (import_list (identifier) @font-lock-variable-name-face)
     (package_decl name: (identifier) @font-lock-constant-face)
     (package_decl forum: (identifier) @font-lock-constant-face)
     (package_decl authority: (identifier) @font-lock-type-face)
     (use_item package: (identifier) @font-lock-constant-face)
     (case_file name: (identifier) @font-lock-function-name-face)
     (type_decl name: (identifier) @font-lock-type-face)
     (enum_decl name: (identifier) @font-lock-type-face)
     (variant_list (identifier) @font-lock-constant-face)
     (event_decl name: (identifier) @font-lock-type-face)
     (param name: (identifier) @font-lock-variable-name-face)
     (authority_decl level: (identifier) @font-lock-type-face)
     (node_decl name: (identifier) @font-lock-function-name-face)
     (group_decl name: (identifier) @font-lock-function-name-face)
     (edge_decl name: (identifier) @font-lock-property-name-face)
     (link_decl name: (identifier) @font-lock-property-name-face)
     (holiday_decl name: (identifier) @font-lock-property-name-face)
     (party_decl name: (identifier) @font-lock-variable-name-face)
     ([(rule_decl) (deadline_decl) (counting_decl) (calendar_decl)
       (transition_decl) (default_decl) (exception_decl)]
      name: (identifier) @font-lock-function-name-face)
     (instance_decl base: (identifier) @font-lock-constant-face)
     (instance_decl origin: (identifier) @font-lock-constant-face)
     (test_decl name: (string) @font-lock-doc-face))

   :language 'litigate
   :feature 'string
   '((escape_sequence) @font-lock-escape-face
     (string) @font-lock-string-face
     (cite_text) @font-lock-doc-markup-face
     (version_req) @font-lock-constant-face)

   :language 'litigate
   :feature 'keyword
   `([,@litigate-mode--conditional-keywords] @font-lock-keyword-face
     "cite" @font-lock-preprocessor-face
     (discretion) @font-lock-keyword-face
     [,@litigate-mode--declaration-keywords] @font-lock-keyword-face
     [,@litigate-mode--clause-keywords] @font-lock-keyword-face)

   :language 'litigate
   :feature 'type
   '((type name: (identifier) @font-lock-type-face)
     (by_clause actor: (ref (identifier) @font-lock-type-face))
     (party_decl actor: (identifier) @font-lock-type-face)
     (party_decl entity: (identifier) @font-lock-type-face))

   :language 'litigate
   :feature 'number
   '([(number) (money) (duration) (date)] @font-lock-number-face)

   :language 'litigate
   :feature 'constant
   '([(boolean) (unit) (unset) (unvalued) (hole) (open_end)]
     @font-lock-constant-face
     [(anonymous) (wildcard)] @font-lock-builtin-face)

   :language 'litigate
   :feature 'property
   '([(num_entry key: (identifier) @font-lock-property-name-face)
      (money_entry key: (identifier) @font-lock-property-name-face)
      (json_entry key: (_) @font-lock-property-name-face)
      (record_field key: (identifier) @font-lock-property-name-face)
      (probability_entry key: (identifier) @font-lock-property-name-face)
      (role_entry key: (identifier) @font-lock-property-name-face)
      (service_entry method: (identifier) @font-lock-constant-face)]
     (field_expression field: (identifier) @font-lock-property-use-face))

   :language 'litigate
   :feature 'builtin
   `(((call_expression
       function: (ref :anchor (identifier) @font-lock-builtin-face :anchor))
      (:match ,(rx-to-string `(seq bos (or ,@litigate-mode--builtins) eos))
              @font-lock-builtin-face)))

   :language 'litigate
   :feature 'function
   '((call_expression
      function: (ref (identifier) @font-lock-function-call-face :anchor)))

   :language 'litigate
   :feature 'operator
   `([,@litigate-mode--operators] @font-lock-operator-face)

   :language 'litigate
   :feature 'bracket
   '(["(" ")" "[" "]" "{" "}"] @font-lock-bracket-face)

   :language 'litigate
   :feature 'delimiter
   '(["," ":" "::" "." "@"] @font-lock-delimiter-face)

   :language 'litigate
   :feature 'variable
   '((identifier) @font-lock-variable-use-face)

   :language 'litigate
   :feature 'error
   :override t
   '((ERROR) @font-lock-warning-face))
  "Tree-sitter font-lock settings for `litigate-mode'.")

(defconst litigate-mode--font-lock-feature-list
  '((comment definition)
    (keyword string type)
    (number constant property builtin function)
    (operator bracket delimiter variable error))
  "Font-lock features by level, for `treesit-font-lock-feature-list'.")

;;; Indentation (kept equal to queries/indents.scm by the ERT suite).

(defconst litigate-mode--indent-body-types
  '("package_decl" "variant_list" "param_list" "node_body" "edge_fields"
    "duration_range" "deadline_opts" "instance_decl" "probability_map"
    "role_map" "rule_body" "counting_body" "service_map" "short_period"
    "calendar_body" "transition_body" "test_body" "source_body"
    "parties_block" "events_block" "facts_block" "stakes_block"
    "beliefs_block" "count_map" "num_record" "money_record" "json_record"
    "json_list" "id_list" "import_list" "record_expression"
    "list_expression" "arguments" "match_expression")
  "Node types whose contents indent one level (`@indent.begin').")

(defconst litigate-mode--delimited-types
  (seq-difference litigate-mode--indent-body-types
                  '("package_decl" "instance_decl" "match_expression"))
  "Indenting node types that open with a delimiter, not a keyword.
On a line of their own they stay at their parent's indentation.")

(defvar litigate-mode--indent-rules
  `((litigate
     ((parent-is ,(rx bos (or "source_file" "lit_file" "case_file") eos))
      column-0 0)
     ((node-is ,(rx bos (or "}" "]" ")" "{") eos)) parent-bol 0)
     ((parent-is ,(rx bos "block_comment" eos)) prev-adaptive-prefix 0)
     ((parent-is ,(rx bos (or "string" "string_content") eos)) no-indent 0)
     ((node-is ,(rx-to-string
                 `(seq bos (or ,@litigate-mode--delimited-types) eos)))
      parent-bol 0)
     ((parent-is ,(rx-to-string
                   `(seq bos (or ,@litigate-mode--indent-body-types) eos)))
      parent-bol litigate-mode-indent-offset)
     (no-node parent-bol 0)
     ;; A comment between a header and its body stays with the header.
     ((node-is ,(rx bos (or "line_comment" "doc_comment" "block_comment") eos))
      parent-bol 0)
     ;; Anything else on a line of its own continues the construct above
     ;; it (a clause after a header line, an operand after an operator).
     (catch-all parent-bol litigate-mode-indent-offset)))
  "Tree-sitter indent rules for `litigate-mode'.")

;;; Navigation and imenu.

(defconst litigate-mode--defun-types
  '("module_decl" "package_decl" "group_decl" "type_decl" "enum_decl"
    "event_decl" "authority_decl" "node_decl" "link_decl" "instance_decl"
    "rule_decl" "counting_decl" "calendar_decl" "transition_decl"
    "test_decl" "case_file" "source_decl" "parties_block" "events_block"
    "facts_block" "stakes_block" "beliefs_block" "analysis_block")
  "Top-level declaration node types (defuns).")

(defun litigate-mode--defun-name (node)
  "Return the declared name of NODE, or nil."
  (pcase (treesit-node-type node)
    ((or "module_decl" "import_decl")
     (when-let* ((path (treesit-node-child-by-field-name node "path")))
       (treesit-node-text path t)))
    ("test_decl"
     (when-let* ((name (treesit-node-child-by-field-name node "name")))
       (string-trim (treesit-node-text name t) "\"" "\"")))
    (_
     (when-let* ((name (treesit-node-child-by-field-name node "name")))
       (treesit-node-text name t)))))

(defun litigate-mode--top-level-p (node)
  "Return non-nil when NODE is a direct item of a file."
  (when-let* ((parent (treesit-node-parent node)))
    (member (treesit-node-type parent) '("lit_file" "case_file"))))

(defun litigate-mode--imenu-entry (type &optional pred)
  "Return a `treesit-simple-imenu-settings' regexp for node TYPE.
PRED, when given, further filters matching nodes."
  (list (rx-to-string `(seq bos (or ,@(ensure-list type)) eos)) pred))

(defconst litigate-mode--imenu-categories
  '(("Module" "module_decl") ("Case" "case_file")
    ("Node" "node_decl") ("Edge" "edge_decl" "link_decl")
    ("Group" "group_decl")
    ("Type" "type_decl" "enum_decl") ("Event" "event_decl")
    ("Rule" "rule_decl") ("Deadline" "deadline_decl")
    ("Counting" "counting_decl") ("Calendar" "calendar_decl")
    ("Holiday" "holiday_decl")
    ("Transition" "transition_decl")
    ("Default" "default_decl") ("Exception" "exception_decl")
    ("Test" "test_decl") ("Party" "party_decl"))
  "Imenu categories and the node types listed under each.")

(defun litigate-mode--imenu-settings ()
  "Build `treesit-simple-imenu-settings' for litigate."
  (mapcar (lambda (category)
            (cons (car category)
                  (litigate-mode--imenu-entry
                   (cdr category)
                   (lambda (node) (litigate-mode--defun-name node)))))
          litigate-mode--imenu-categories))

;;; Syntax table.

(defvar litigate-mode--syntax-table
  (let ((table (make-syntax-table)))
    (modify-syntax-entry ?/ ". 124b" table)
    (modify-syntax-entry ?* ". 23" table)
    (modify-syntax-entry ?\n "> b" table)
    (modify-syntax-entry ?\" "\"" table)
    (modify-syntax-entry ?\\ "\\" table)
    (modify-syntax-entry ?- "_" table)
    (modify-syntax-entry ?_ "_" table)
    (modify-syntax-entry ?' "." table)
    (dolist (c '(?+ ?% ?< ?> ?= ?! ?& ?| ?^ ?@ ?? ?:))
      (modify-syntax-entry c "." table))
    table)
  "Syntax table for `litigate-mode'.")

;;; Fallback font-lock (no grammar installed).

(defconst litigate-mode--fallback-font-lock-keywords
  `((,(rx-to-string
       `(seq symbol-start
             (or ,@litigate-mode--declaration-keywords
                 ,@litigate-mode--conditional-keywords)
             symbol-end))
     0 'font-lock-keyword-face)
    (,(rx symbol-start "cite" symbol-end) 0 'font-lock-preprocessor-face)
    (,(rx symbol-start (or "true" "false") symbol-end) 0 'font-lock-constant-face)
    (,(rx symbol-start (+ digit) "-" (= 2 digit) "-" (= 2 digit) symbol-end)
     0 'font-lock-number-face)
    (,(rx symbol-start (+ digit) (* (any digit "_")) (? "." (+ digit))
          (? "." (or "usd" "days" "court_days" "business_days" "hours"))
          symbol-end)
     0 'font-lock-number-face))
  "Regexp font-lock used when the tree-sitter grammar is unavailable.
Contextual keywords such as `p' or `on' are left alone: without a parse
tree they cannot be told apart from names.")

;;; Grammar installation.

(defun litigate-mode--run (dir program &rest args)
  "Run PROGRAM with ARGS in DIR; signal an error with its output on failure."
  (let ((default-directory (file-name-as-directory dir)))
    (with-temp-buffer
      (unless (zerop (apply #'call-process program nil t nil args))
        (error "litigate-mode: `%s %s' failed:\n%s"
               program (string-join args " ") (buffer-string))))))

;;;###autoload
(defun litigate-mode-install-grammar (&optional out-dir)
  "Build the pinned litigate grammar and install it for Emacs.
Clones `litigate-mode-grammar-url' at `litigate-mode-grammar-rev', builds
it with the `tree-sitter' CLI, and writes libtree-sitter-litigate to
OUT-DIR (default: the tree-sitter directory under `user-emacs-directory',
which `treesit' searches).  When this Emacs loads only a tree-sitter ABI
older than the committed parser's (15), the parser is regenerated at the
ABI Emacs reports, which needs node.  Needs git and a C compiler."
  (interactive)
  (let* ((git (or (executable-find "git") (user-error "The git program is not on `exec-path'")))
         (cli (or (executable-find "tree-sitter")
                  (user-error "The tree-sitter CLI is not on `exec-path' (cargo install tree-sitter-cli)")))
         (abi (if (fboundp 'treesit-library-abi-version) (treesit-library-abi-version) 14))
         (out (expand-file-name (or out-dir "tree-sitter") user-emacs-directory))
         (lib (expand-file-name
               (concat "libtree-sitter-litigate" (car dynamic-library-suffixes)) out))
         (tmp (make-temp-file "litigate-grammar" t))
         (src (expand-file-name "grammar" tmp)))
    (unwind-protect
        (progn
          (litigate-mode--run tmp git "clone" "--quiet" "--no-checkout"
                              litigate-mode-grammar-url src)
          (litigate-mode--run src git "checkout" "--quiet" litigate-mode-grammar-rev)
          (when (< abi 15)
            (litigate-mode--run src cli "generate" "--abi" (number-to-string abi)))
          (make-directory out t)
          (litigate-mode--run src cli "build" "-o" lib src)
          (message "Built litigate grammar %s (ABI %d) from %s @ %s"
                   lib (min abi 15) litigate-mode-grammar-url
                   (substring litigate-mode-grammar-rev 0 12))
          lib)
      (delete-directory tmp t))))

;;; Mode.

;;;###autoload
(define-derived-mode litigate-mode prog-mode "litigate"
  "Major mode for litigate rule modules (.lit) and matters (.case).

Uses the tree-sitter grammar `litigate'; install it with
\\[litigate-mode-install-grammar].  Without it, the mode falls back to
regexp font-lock.

\\{litigate-mode-map}"
  :group 'litigate
  :syntax-table litigate-mode--syntax-table
  (setq-local comment-start "// ")
  (setq-local comment-end "")
  (setq-local comment-start-skip (rx (or (seq "/" (+ "/")) (seq "/" (+ "*"))) (* space)))
  (setq-local comment-end-skip (rx (* space) (group (or (syntax comment-end) (seq (+ "*") "/")))))
  (setq-local indent-tabs-mode nil)
  (setq-local tab-width litigate-mode-indent-offset)
  (setq-local electric-indent-chars (append "{}[]()" electric-indent-chars))
  (when (treesit-ready-p 'litigate)
    (treesit-parser-create 'litigate)
    (setq-local treesit-font-lock-settings litigate-mode--font-lock-settings)
    (setq-local treesit-font-lock-feature-list litigate-mode--font-lock-feature-list)
    (setq-local treesit-simple-indent-rules litigate-mode--indent-rules)
    (setq-local treesit-defun-type-regexp
                (cons (rx-to-string `(seq bos (or ,@litigate-mode--defun-types) eos))
                      #'litigate-mode--top-level-p))
    (setq-local treesit-defun-name-function #'litigate-mode--defun-name)
    (setq-local treesit-simple-imenu-settings (litigate-mode--imenu-settings))
    (when (boundp 'treesit-outline-predicate)
      (setq-local treesit-outline-predicate
                  (cons (rx-to-string `(seq bos (or ,@litigate-mode--defun-types) eos))
                        #'litigate-mode--top-level-p)))
    (treesit-major-mode-setup))
  (unless (treesit-ready-p 'litigate t)
    (setq-local font-lock-defaults
                '(litigate-mode--fallback-font-lock-keywords nil nil))))

;;;###autoload
(defalias 'litigate-ts-mode #'litigate-mode
  "Compatibility alias: the mode was `litigate-ts-mode' in litgraph.")

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.lit\\'" . litigate-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.case\\'" . litigate-mode))

;;;###autoload
(with-eval-after-load 'eglot
  (defvar eglot-server-programs)
  (add-to-list 'eglot-server-programs
               `(litigate-mode . ,(lambda (&rest _) litigate-mode-lsp-command))))

(provide 'litigate-mode)
;;; litigate-mode.el ends here
