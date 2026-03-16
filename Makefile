.PHONY: setup hooks agents clean help

# ─── Primary target ────────────────────────────────────────────────────────────

setup: agents ## Full setup: agent files
	@echo "Setup complete."

# ─── Agent files ───────────────────────────────────────────────────────────────

AGENTS_SOURCE ?= $(HOME)/git/chasemp/AlpheusCEF/agents
AGENTS_MYCELIUM_SOURCE ?= $(HOME)/git/chasemp/mycelium-agent-framework/agents-mycelium

agents: ## Copy agent files from source repos into .claude/
	@mkdir -p .claude/agents .claude/skills
	@# Copy CLAUDE.md and top-level agent definitions
	@if [ -d "$(AGENTS_SOURCE)" ]; then \
		echo "Copying AlpheusCEF agents from $(AGENTS_SOURCE)..."; \
		cp -f "$(AGENTS_SOURCE)/CLAUDE.md" .claude/ 2>/dev/null || true; \
		cp -f "$(AGENTS_SOURCE)/agents.md" .claude/ 2>/dev/null || true; \
		cp -f "$(AGENTS_SOURCE)/tdd-guardian.md" .claude/agents/ 2>/dev/null || true; \
		cp -f "$(AGENTS_SOURCE)/refactor-scan.md" .claude/agents/ 2>/dev/null || true; \
		cp -f "$(AGENTS_SOURCE)/pr-reviewer.md" .claude/agents/ 2>/dev/null || true; \
		cp -f "$(AGENTS_SOURCE)/progress-guardian.md" .claude/agents/ 2>/dev/null || true; \
		for f in "$(AGENTS_SOURCE)"/skills/*.md; do \
			[ -f "$$f" ] && cp -f "$$f" .claude/skills/; \
		done; \
	else \
		echo "WARNING: AlpheusCEF agents not found at $(AGENTS_SOURCE)"; \
	fi
	@# Copy mycelium-specific agents
	@if [ -d "$(AGENTS_MYCELIUM_SOURCE)" ]; then \
		echo "Copying mycelium agents from $(AGENTS_MYCELIUM_SOURCE)..."; \
		for f in "$(AGENTS_MYCELIUM_SOURCE)"/agents/*.md; do \
			[ -f "$$f" ] && cp -f "$$f" .claude/agents/; \
		done; \
	else \
		echo "WARNING: Mycelium agents not found at $(AGENTS_MYCELIUM_SOURCE)"; \
	fi
	@echo "Agent files copied."

# ─── Clean ─────────────────────────────────────────────────────────────────────

clean: ## Remove agent file copies
	rm -rf .claude/agents .claude/skills .claude/CLAUDE.md .claude/agents.md
	@echo "Cleaned."

# ─── Help ──────────────────────────────────────────────────────────────────────

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'
