;;; litigate-mode-test.el --- ERT suite for litigate-mode  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with
;;
;;   emacs -Q --batch -L src -l src/litigate-mode.el \
;;     -l test/litigate-mode-test.el -f ert-run-tests-batch-and-exit
;;
;; Environment (all optional):
;;   LITIGATE_TS_GRAMMAR_DIR  directory holding libtree-sitter-litigate
;;                            (default: wherever `treesit' already looks)
;;   LITIGATE_CORPUS          directory walked for every .lit/.case file
;;                            (default: this repo's examples/)
;;   LITIGATE_GRAMMAR_SRC     a tree-sitter-litigate checkout; enables the
;;                            tests that compare the mode's keyword and indent
;;                            lists with its queries (skipped otherwise)

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'imenu)
(require 'litigate-mode)

(defvar litigate-test--repo
  (file-name-as-directory
   (expand-file-name ".." (file-name-directory
                           (or load-file-name buffer-file-name))))
  "Repository root.")

(defvar litigate-test--corpus-root
  (file-name-as-directory
   (or (getenv "LITIGATE_CORPUS")
       (expand-file-name "examples" litigate-test--repo)))
  "Directory the corpus walk starts from.")

(when-let* ((dir (getenv "LITIGATE_TS_GRAMMAR_DIR")))
  (add-to-list 'treesit-extra-load-path dir))

(defconst litigate-test--skipped-dirs '(".git" "target" "node_modules" ".worktrees")
  "Directories the corpus walk skips.")

(defun litigate-test--corpus ()
  "Every .lit and .case file under `litigate-test--corpus-root'."
  (let (files)
    (cl-labels ((walk (dir)
                  (dolist (entry (directory-files dir t directory-files-no-dot-files-regexp))
                    (cond
                     ((file-directory-p entry)
                      (unless (or (file-symlink-p entry)
                                  (member (file-name-nondirectory entry)
                                          litigate-test--skipped-dirs))
                        (walk entry)))
                     ((string-match-p (rx "." (or "lit" "case") eos) entry)
                      (push entry files))))))
      (walk litigate-test--corpus-root))
    (sort files #'string<)))

(defun litigate-test--query-strings (file capture)
  "Return the quoted tokens and node types tagged CAPTURE in query FILE.
Only patterns written as a bracketed list followed by @CAPTURE count.
FILE is read from the grammar checkout in LITIGATE_GRAMMAR_SRC."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name (concat "queries/litigate/" file)
                       (getenv "LITIGATE_GRAMMAR_SRC")))
    (let (items)
      (goto-char (point-min))
      (while (re-search-forward
              (rx "[" (group (* (not (any "[]")))) "]" (* space) "@" (literal capture)
                  (or space eol))
              nil t)
        (let ((body (match-string 1)))
          (with-temp-buffer
            ;; Drop comments inside the list.
            (insert (replace-regexp-in-string (rx ";" (* nonl)) "" body))
            (goto-char (point-min))
            (while (re-search-forward
                    (rx (or (seq "\"" (group-n 1 (+ (not "\""))) "\"")
                            (seq "(" (group-n 1 (+ (any "a-z_"))) ")")))
                    nil t)
              (push (match-string 1) items)))))
      (sort (delete-dups items) #'string<))))

(defmacro litigate-test--with-file (file &rest body)
  "Visit FILE through `auto-mode-alist' and run BODY in its buffer."
  (declare (indent 1))
  `(let ((buffer (find-file-noselect ,file t)))
     (unwind-protect
         (with-current-buffer buffer ,@body)
       (kill-buffer buffer))))

(defun litigate-test--face-at (text &optional nth)
  "Return the face at the NTH (default 1st) occurrence of TEXT."
  (goto-char (point-min))
  (search-forward text nil nil (or nth 1))
  (get-text-property (match-beginning 0) 'face))

(ert-deftest litigate-mode-grammar-ready ()
  (should (treesit-ready-p 'litigate)))

(ert-deftest litigate-mode-corpus-is-nonempty ()
  (let ((corpus (litigate-test--corpus)))
    (message "litigate corpus: %d files" (length corpus))
    (should (>= (length corpus) 2))))

(ert-deftest litigate-mode-every-corpus-file ()
  "Every corpus file opens in the mode, parses clean and fontifies."
  (dolist (file (litigate-test--corpus))
    (ert-info ((format "file: %s" (file-relative-name file litigate-test--corpus-root)))
      (litigate-test--with-file file
        (should (eq major-mode 'litigate-mode))
        (should (treesit-parser-list))
        (let ((root (treesit-buffer-root-node 'litigate)))
          (should (equal (treesit-node-type root) "source_file"))
          (should-not (treesit-node-check root 'has-error)))
        ;; Every font-lock query must compile and run against this tree.
        (let ((root (treesit-buffer-root-node 'litigate)))
          (dolist (setting treesit-font-lock-settings)
            (treesit-query-capture root (car setting))))
        (let ((font-lock-maximum-decoration t)
              (treesit-font-lock-level 4)
              (debug-on-error t))
          (treesit-font-lock-recompute-features)
          (font-lock-ensure))
        (should (text-property-not-all (point-min) (point-max) 'face nil))
        (imenu--make-index-alist t)
        (should imenu--index-alist)))))

(ert-deftest litigate-mode-indentation-is-canonical ()
  "Reindenting a canonically formatted corpus file changes nothing."
  (dolist (file (litigate-test--corpus))
    (ert-info ((format "file: %s" (file-relative-name file litigate-test--corpus-root)))
      (litigate-test--with-file file
        (let ((before (buffer-string)))
          (indent-region (point-min) (point-max))
          (should (equal (buffer-string) before)))))))

(ert-deftest litigate-mode-indents-new-lines ()
  (with-temp-buffer
    (litigate-mode)
    (insert "module m\n\nstate answered: \"Answer filed\" {\ngroup pleadings\n_ \"Go\" -> done {\neffort 1.hours\n}\n}\n")
    (indent-region (point-min) (point-max))
    (should (equal (buffer-substring-no-properties (point-min) (point-max))
                   "module m\n\nstate answered: \"Answer filed\" {\n  group pleadings\n  _ \"Go\" -> done {\n    effort 1.hours\n  }\n}\n"))))

(ert-deftest litigate-mode-faces ()
  (litigate-test--with-file (expand-file-name "examples/rule12.lit" litigate-test--repo)
    (let ((treesit-font-lock-level 4))
      (treesit-font-lock-recompute-features)
      (font-lock-ensure))
    (should (eq (litigate-test--face-at "module") 'font-lock-keyword-face))
    (should (eq (litigate-test--face-at "frcp.rule12") 'font-lock-constant-face))
    (should (eq (litigate-test--face-at "/// Service") 'font-lock-doc-face))
    (should (eq (litigate-test--face-at "time-barred:") 'font-lock-function-name-face))
    (should (eq (litigate-test--face-at "\"Is the claim") 'font-lock-string-face))
    (should (eq (litigate-test--face-at "cite FRCP 8") 'font-lock-preprocessor-face))
    (should (eq (litigate-test--face-at "FRCP 8(c)(1)") 'font-lock-doc-markup-face))
    (should (eq (litigate-test--face-at "barred \"Barred\"") 'font-lock-property-name-face))
    (should (eq (litigate-test--face-at "->") 'font-lock-operator-face))
    (should (eq (litigate-test--face-at "21.days") 'font-lock-number-face))
    (should (eq (litigate-test--face-at "2025-03-24") 'font-lock-number-face))
    (should (eq (litigate-test--face-at "deadline(answer") 'font-lock-builtin-face))
    (should (eq (litigate-test--face-at "Served(complaint)") 'font-lock-function-call-face))
    (should (eq (litigate-test--face-at "Document)") 'font-lock-type-face))
    (should (eq (litigate-test--face-at "discretion") 'font-lock-keyword-face))
    (should (eq (litigate-test--face-at "? }") 'font-lock-constant-face))))

(ert-deftest litigate-mode-faces-case ()
  (litigate-test--with-file (expand-file-name "examples/acme.case" litigate-test--repo)
    (font-lock-ensure)
    (should (eq (litigate-test--face-at "case") 'font-lock-keyword-face))
    (should (eq (litigate-test--face-at "acme-v-widget") 'font-lock-function-name-face))
    (should (eq (litigate-test--face-at "^0.1.0") 'font-lock-constant-face))
    (should (eq (litigate-test--face-at "Plaintiff") 'font-lock-type-face))
    (should (eq (litigate-test--face-at "parties") 'font-lock-keyword-face))))

(ert-deftest litigate-mode-imenu ()
  (litigate-test--with-file (expand-file-name "examples/rule12.lit" litigate-test--repo)
    (let* ((index (imenu--make-index-alist t))
           (names (lambda (category) (mapcar #'car (cdr (assoc category index))))))
      (should (member "frcp.rule12" (funcall names "Module")))
      (should (member "time-barred" (funcall names "Node")))
      (should (member "judgment-entered" (funcall names "Node")))
      (should (member "answer-duty" (funcall names "Rule")))
      (should (member "answer-period" (funcall names "Deadline")))
      (should (member "frcp6" (funcall names "Counting")))
      (should (member "federal-holidays" (funcall names "Calendar")))
      (should (member "Served" (funcall names "Event")))
      (should (member "Document" (funcall names "Type")))
      (should (member "answer due 21 days after personal service"
                      (funcall names "Test"))))))

(ert-deftest litigate-mode-defun-navigation ()
  (litigate-test--with-file (expand-file-name "examples/rule12.lit" litigate-test--repo)
    (goto-char (point-min))
    (search-forward "barred \"Barred\"")
    (should (equal (treesit-defun-name (treesit-defun-at-point)) "time-barred"))
    (beginning-of-defun)
    (should (looking-at-p "chance time-barred"))))

(ert-deftest litigate-mode-fallback-without-grammar ()
  "Without the grammar the mode still loads and highlights keywords."
  (cl-letf (((symbol-function 'treesit-ready-p) (lambda (&rest _) nil)))
    (with-temp-buffer
      (insert "module m // note\nrule r { when a == 1 }\n")
      (litigate-mode)
      (should (eq major-mode 'litigate-mode))
      (should-not (treesit-parser-list))
      (font-lock-ensure)
      (should (eq (litigate-test--face-at "module") 'font-lock-keyword-face))
      (should (eq (litigate-test--face-at "note") 'font-lock-comment-face))
      (should (eq (litigate-test--face-at "when") 'font-lock-keyword-face)))))

(ert-deftest litigate-mode-alias ()
  (should (eq (indirect-function 'litigate-ts-mode) (indirect-function 'litigate-mode))))

(ert-deftest litigate-mode-grammar-pin ()
  (should (string-match-p (rx bos (= 40 xdigit) eos) litigate-mode-grammar-rev))
  (should (equal (nth 6 litigate-mode-grammar-recipe) litigate-mode-grammar-rev)))

(ert-deftest litigate-mode-registrations ()
  (should (eq (assoc-default "x/y.lit" auto-mode-alist #'string-match-p) 'litigate-mode))
  (should (eq (assoc-default "x/y.case" auto-mode-alist #'string-match-p) 'litigate-mode))
  (should (equal (assq 'litigate treesit-language-source-alist)
                 litigate-mode-grammar-recipe))
  (require 'eglot)
  (let ((entry (assoc 'litigate-mode eglot-server-programs)))
    (should entry)
    (should (equal (funcall (cdr entry)) '("litigate" "lsp" "--stdio")))))

(ert-deftest litigate-mode-keywords-match-highlights-scm ()
  "The mode's keyword lists equal the @keyword lists of highlights.scm."
  (skip-unless (getenv "LITIGATE_GRAMMAR_SRC"))
  (should (equal (litigate-test--query-strings "highlights.scm" "keyword")
                 (sort (append (copy-sequence litigate-mode--declaration-keywords)
                               (copy-sequence litigate-mode--clause-keywords))
                       #'string<)))
  (should (equal (litigate-test--query-strings "highlights.scm" "keyword.conditional")
                 (sort (copy-sequence litigate-mode--conditional-keywords) #'string<)))
  (should (equal (litigate-test--query-strings "highlights.scm" "operator")
                 (sort (copy-sequence litigate-mode--operators) #'string<))))

(ert-deftest litigate-mode-indent-types-match-indents-scm ()
  (skip-unless (getenv "LITIGATE_GRAMMAR_SRC"))
  (should (equal (litigate-test--query-strings "indents.scm" "indent.begin")
                 (sort (copy-sequence litigate-mode--indent-body-types) #'string<))))

(provide 'litigate-mode-test)
;;; litigate-mode-test.el ends here
