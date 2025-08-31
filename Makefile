# Convenience developer Makefile (not an OpenWrt package Makefile)
# Usage examples:
#   make bump-version VERSION=2.0.0
#   make bump-version VERSION=2.0.0-beta
# Optional (after reviewing CHANGELOG stub):
#   git add service/rrm_nr.init docs/CHANGELOG.md && git commit -m "chore: bump init version to v2.0.0"

SHELL := /bin/sh

.PHONY: bump-version show-version show-pkg-version bump-pkg-version sync-pkg-version-from-init

INIT_FILE := service/rrm_nr.init
CHANGELOG := docs/CHANGELOG.md
PKG_FILE := package/rrm-nr-distributor/Makefile

show-version:
	@grep -E '^RRM_NR_INIT_VERSION=' $(INIT_FILE) || echo 'Version variable not found.'

show-pkg-version:
	@if [ -f $(PKG_FILE) ]; then grep -E '^PKG_VERSION:=' $(PKG_FILE); else echo 'Package Makefile missing'; fi

# bump-version updates init script version and optionally (UPDATE_PKG=1) package PKG_VERSION.
bump-version:
	@if [ -z "$(VERSION)" ]; then \\
	  echo "ERROR: Provide VERSION= (e.g. make bump-version VERSION=2.0.0)" >&2; exit 1; \\
	fi
	@if ! grep -q '^RRM_NR_INIT_VERSION="' $(INIT_FILE); then \\
	  echo "ERROR: RRM_NR_INIT_VERSION= line not found in $(INIT_FILE)" >&2; exit 1; \\
	fi
	@echo "Updating RRM_NR_INIT_VERSION to $(VERSION)";
	@# BSD/macOS compatible in-place edit
	sed -i'' -E 's/^(RRM_NR_INIT_VERSION=")[^"]+("$$)/\\1$(VERSION)\\2/' $(INIT_FILE)
	@grep -E '^RRM_NR_INIT_VERSION=' $(INIT_FILE)
	@if [ "$(UPDATE_PKG)" = 1 ] && [ -f $(PKG_FILE) ]; then \\
	  echo "Also updating PKG_VERSION in $(PKG_FILE)"; \\
	  sed -i'' -E 's/^(PKG_VERSION:=).*/\\1$(VERSION)/' $(PKG_FILE); \\
	  grep -E '^PKG_VERSION:=' $(PKG_FILE); \\
	fi
	@if [ -f $(CHANGELOG) ]; then \\
	  if ! grep -q "^## \\[$(VERSION)\\]" $(CHANGELOG); then \\
	    echo "Inserting stub section into $(CHANGELOG)"; \\
	    tmp=$$(mktemp 2>/dev/null || echo /tmp/rrm_nr_changelog.$$); \\
	    awk -v ver="$(VERSION)" -v d="$$(date -u +%Y-%m-%d)" 'BEGIN{inserted=0} NR==1{print;next} NR==2 && !inserted{print "## ["ver"] - "d"\n### Added\n- TBD\n"; inserted=1} {print}' $(CHANGELOG) > $$tmp && mv $$tmp $(CHANGELOG); \\
	  else \\
	    echo "CHANGELOG already has entry for $(VERSION), leaving unchanged"; \\
	  fi; \\
	else \\
	  echo "NOTE: $(CHANGELOG) not found; skipping changelog stub"; \\
	fi
	@echo "Done. Remember to review CHANGELOG and commit changes."

# bump-pkg-version only changes the package PKG_VERSION (date or semantic) without touching init script.
bump-pkg-version:
	@if [ -z "$(VERSION)" ]; then \\
	  echo "ERROR: Provide VERSION= (e.g. make bump-pkg-version VERSION=2025-09-01)" >&2; exit 1; \\
	fi
	@if [ ! -f $(PKG_FILE) ]; then echo "ERROR: $(PKG_FILE) missing" >&2; exit 1; fi
	@echo "Updating PKG_VERSION to $(VERSION)";
	sed -i'' -E 's/^(PKG_VERSION:=).*/\\1$(VERSION)/' $(PKG_FILE)
	@grep -E '^PKG_VERSION:=' $(PKG_FILE)

# sync-pkg-version-from-init reads init script version and applies it to PKG_VERSION.
sync-pkg-version-from-init:
	@if [ ! -f $(PKG_FILE) ]; then echo "ERROR: $(PKG_FILE) missing" >&2; exit 1; fi
	@if ! grep -q '^RRM_NR_INIT_VERSION=' $(INIT_FILE); then echo "ERROR: version not found in init" >&2; exit 1; fi
	@v=$$(grep -E '^RRM_NR_INIT_VERSION=' $(INIT_FILE) | sed -E 's/^[^=]+="?([^" ]+)"?/\1/'); \\
	 echo "Syncing PKG_VERSION to $$v"; \\
	 sed -i'' -E "s/^(PKG_VERSION:=).*/\\1$$v/" $(PKG_FILE); \\
	 grep -E '^PKG_VERSION:=' $(PKG_FILE)
