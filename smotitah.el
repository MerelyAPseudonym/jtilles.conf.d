;; Super-modular
;; Probably a preloading of certain modules is necessary for some profiles
;; consider giving a hook for module loading

(require 'cl)

;;;; ------------------------------------- Variables -------------------------------------

(defvar sm-profile nil
  "The name of the currently loaded profile")

(defvar sm-unmanaged-profile nil
  "If this is set to T, just load the profile file")

(defvar sm-profile-functions-format "sm-profile-%s-%s"
  "Format string used to calculate the names of the init and post functions for a profile.
  - init function: sm-profile-<profile-name>-init
  - post function: sm-profile-<profile-name>-post")

(defvar sm-active-modules nil
  "List of the modules to be activated by the profile.")

(defvar sm-module-table (make-hash-table :test 'equal)
  "Table of loaded modules. Each module is represented as a property list.")

(defvar  sm-module-functions-format "sm-module-%s-%s"
  "Format string used to calculate the names of the init and post functions for a module.
  - init function: sm-profile-<module name>-init
  - post function: sm-profile-<module name>-post")

(defvar sm-profile-module-integration-file-name-format "%s-%s-%s.el"
  "Format string used to calculate the name of the integration
  files relative to a given module and profile.")

(defvar sm-supported-package-managers '("el-get" "package")
  "Supported package managers.")

(defvar sm-profiles-dir (concat user-emacs-directory "profiles/")
  "Profiles directory.")

(defvar sm-modules-dir (concat user-emacs-directory "modules/")
  "Modules directory.")

(defvar sm-packages-dir (concat user-emacs-directory "packages/")
  "Packages directory")

(defvar sm-directory (file-name-directory load-file-name)
  "Smotitah installation directory.")

(defvar sm-base-profile-file-name (concat sm-profiles-dir "sm-base-profile.el")
  "Base profile file name.")


;;;; ------------------------------------- Utilities -------------------------------------

(defun sm-load-file-if-exists (filename)
  "Loads a file if exists."
  (when (file-exists-p filename)
    (load filename)))

(defun sm-as-string (obj)
  "Converts a symbol or a keyword into a string, or returns OBJ
if it is a string"
  (etypecase obj
    (string obj)
    (symbol (let ((name (symbol-name obj)))
	      (if (= (elt name 0) ?:)
		  (subseq name 1)
		name)))))

(defun sm-as-symbol (obj)
  "Converts a string to a symbol, or returns OBJ if ir is a
symbol."
  (etypecase obj
    (string (intern obj))
    (symbol obj)))


;;;; --------------------------------- Name -> Filename ----------------------------------

(defun sm-profile-filename (profile-name)
  "Returns the file path for a profile named PROFILE-NAME."
  (concat sm-profiles-dir (sm-as-string profile-name) ".el"))

(defun sm-module-filename (module-name)
  "Returns the file path for a module named MODULE-NAME."
  (concat sm-modules-dir (sm-as-string  module-name) ".el"))

(defun sm-package-filename (package-name)
  "Returns the file path for a package named PACKAGE-NAME."
  (concat sm-packages-dir "sm-package-" (sm-as-string package-name) ".el"))

(defun sm-module-package-integration-file (package-name module-name)
  "Returns the file path for the integration file for a package
named PACKAGE-NAME in a module named MODULE-NAME."
  (format "%s/%s/%s-integration.el"
          sm-modules-dir
	  (sm-as-string module-name)
          (sm-as-string package-name)))


;;;; -------------------------------------- Profile --------------------------------------

(defun sm-profile-init-fn (profile-name)
  "Returns a symbol whose name is the name of the intialiation
function for a profile named PROFILE-NAME."
  (intern (format sm-profile-functions-format profile-name "init")))

(defun sm-profile-post-fn (profile-name)
  "Returns a symbol whose name is the name of the post-module-loading
function for a profile named PROFILE-NAME."
  (intern (format sm-profile-functions-format profile-name "post")))

(defun sm-load-profile (profile-name)
  "Loads the profile. This function is part of the framework
startup, and is not meant to be called directly by the user."
  ;; Use the profile file as custom file
  (setq custom-file (sm-profile-filename profile-name))
  ;; Load the base profile
  (load sm-base-profile-file-name)
  ;; Load profile file
  (unless (equal (sm-profile-filename profile-name) sm-base-profile-file-name)
    (load (sm-profile-filename profile-name)))
  (unless sm-unmanaged-profile
    (condition-case nil
	(funcall (sm-profile-init-fn profile-name))
      (error (message "smotitah: no profile initialization function")))
    (dolist (module sm-active-modules)
      (sm-load-module module))
    (condition-case nil
	(funcall (sm-profile-post-fn profile-name))
      (error (message "smotitah: no profile initialization function")))))

(defun sm-profile-list ()
  "Returns a list of profile files."
  (mapcar 'file-name-sans-extension (directory-files sm-profiles-dir nil ".*.el")))

(defun sm-profile-integrate-module (stage module-name)
  (sm-load-file-if-exists (format sm-profile-module-integration-file-name-format
				  sm-profile
				  module-name
				  stage)))

(defun sm-require-modules (&rest module-names)
  (setf sm-active-modules (append sm-active-modules module-names)))

;;;; -------------------------------------- Modules --------------------------------------


(defun* sm-module (module-name &key unmanaged-p require-packages)
  (setf (sm-unmanaged-module-p module-name) unmanaged-p)
  (setf (sm-module-packages module-name) require-packages))

(defmacro sm-get-module (module-name)
  `(gethash ,module-name sm-module-table))

(defmacro sm-unmanaged-module-p (module-name)
  `(getf (sm-get-module ,module-name) 'unmanaged-p))

(defun  sm-load-module (module-name)
  "Loads the module named MODULE-NAME."
  (interactive "sModule: ")
  (sm-profile-integrate-module :init module-name)
  (sm-do-load-module module-name)
  (sm-profile-integrate-module :post module-name))

(defun sm-module-init-fn (module-name)
  (intern (format sm-module-functions-format module-name "init")))

(defun sm-module-post-fn (module-name)
  (intern (format sm-module-functions-format module-name "post")))

(defun sm-do-load-module (module-name)
  (interactive "sModule: ")
  (load (sm-module-filename module-name))
  (unless (sm-unmanaged-module-p module-name)
    (funcall (sm-module-init-fn module-name))
    (dolist (package-name (sm-module-packages module-name))
      (sm-package-initialize package-name module-name))
    (funcall (sm-module-post-fn module-name))))

(defmacro sm-module-packages (module-name)
  `(getf (sm-get-module ,module-name) :packages))

(defun sm-module-integrate-package (package-name module-name)
  (sm-load-file-if-exists (sm-module-package-integration-file package-name module-name)))

(defun sm-module-list ()
  "Returns the list of modules in .emacs.d/modules"
  (mapcar 'file-name-sans-extension (directory-files sm-modules-dir nil ".*.el")))


;;;; ------------------------------------- Packages --------------------------------------

(defun sm-package-installed-packages ()
  "Returns the list of packages installed with package.el."
  (mapcar #'car package-alist))

(defun sm-el-get-installed-packages ()
  "Returns the list of packages installed with el-get."
  (if (fboundp 'el-get-package-is-installed)
      (remove-if-not 'el-get-package-is-installed (el-get-read-all-recipe-names))
    nil))

(defun sm-all-installed-packages ()
  (remove-duplicates (append (sm-package-installed-packages)
			     (sm-el-get-installed-packages))
		     :test 'equal))

(defun sm-package-installed-p (package-name)
  (member (sm-as-symbol package-name) (sm-all-installed-packages)))

(defun* sm-package-initialize (package-name &optional module-name user-managed-p)
  (unless user-managed-p
    (sm-install-package-if-needed package-name))
  (sm-load-package-file-if-exists (sm-package-filename package-name))
  (when module-name
    (sm-module-integrate-package package-name module-name)))


(defun sm-install-package-if-needed (package-name)
  (interactive "sPackage-name: ")
  (while (not (sm-package-installed-p package-name))
    (let ((package-manager (sm-as-symbol
			    (ido-completing-read (format "Install %s with: "
							 (sm-as-string package-name))
						 sm-supported-package-managers))))

      (case package-manager
	(el-get (el-get-install package-name))
	(package (package-install package-name))))))

(defun sm-load-package-file-if-exists (package-file-name)
  (sm-load-file-if-exists
   package-file-name))


;;;; ---------------------------------- Initialization -----------------------------------
(defun sm-create-directories-if-needed ()
  (ignore-errors (make-directory (concat sm-profiles-dir))
                 (make-directory (concat sm-modules-dir))
                 (make-directory (concat sm-packages-dir)))
  (assert (every 'file-exists-p (list sm-profiles-dir sm-modules-dir sm-packages-dir))
          nil "smotitah: Cannot create profiles, modules, packages directories in %s"
          user-emacs-directory))

(defun sm-create-base-profile-file-if-needed ()
  (unless (file-exists-p sm-base-profile-file-name)
    (copy-file (concat sm-directory "sm-base-profile-template.el")
               sm-base-profile-file-name)))

(defun sm-initialize ()
  (interactive)
  (sm-create-directories-if-needed)
  (sm-create-base-profile-file-if-needed)
  (setq sm-profile (getenv "EMACS_PROFILE"))
  (unless sm-profile
    (setq sm-profile (sm-select-profile-interactively)))
  (sm-load-profile sm-profile))


(defun sm-select-profile-interactively ()
  (interactive)
  (ido-completing-read "Load Profile: " (sm-profile-list)))

;;;; ----------------------------------- User commands -----------------------------------

;; (defun sm-integrate-module (profile-name module-name)
;;   (interactive (let ((pname (ido-completing-read "Integrate in profile: " (sm-profile-list) nil t)))
;;                  (module-name

(provide 'smotitah)
