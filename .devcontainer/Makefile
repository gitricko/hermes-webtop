# Makefile for hermes-codespace (inside .devcontainer/)

# === Upstream Sync Configuration ===
# Update these to match your upstream template repository
EXTERNAL_DIR := /tmp/vendor/hermes-codespace$(shell bash -c 'echo $$RANDOM')
EXTERNAL_REPO := https://github.com/gitricko/hermes-codespace
EXTERNAL_DEVC := $(EXTERNAL_DIR)/.devcontainer

# === Development Commands ===

install:
	@echo "Installing dependencies..."
	@bash post-create-cmd.sh

ext-install:
	@echo "Installing external dependencies..."
	mkdir -p ~/.cline/data
	cp globalState.json ~/.cline/data/
	cp secrets.json ~/.cline/data/
	code --force --install-extension saoudrizwan.claude-dev
# === Template Update Commands ===

# Use this command to update your .devcontainer folder with latest from upstream
# After you've converted your forked repo to private (Settings → Danger Zone → Leave fork network)
.PHONY: update-deps

update-deps:
	@echo "Syncing .devcontainer from upstream..."
	@if [ ! -f "$(EXTERNAL_DEVC)" ]; then \
		echo "Cloning external dependency..."; \
		mkdir -p $(dir $(EXTERNAL_DEVC)); \
		git clone --depth 1 --branch main $(EXTERNAL_REPO) $(EXTERNAL_DIR); \
	fi
	rsync -av --exclude='.*' "$(EXTERNAL_DEVC)/" "."
	@echo ""
	@echo "Done! Review changes with: git diff .devcontainer/"
	@echo "If satisfied, commit: git add -A && git commit -m 'Update .devcontainer from upstream'"
