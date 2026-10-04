#!/usr/bin/env bash
# ci_lint_check.sh — Run full CI lint validation locally before committing
# Mirrors the lint-check job in .github/workflows/ci.yml (see ci.yml Phase 29).
# Adapted for .minions: upstream hermes-codespace used .devcontainer/ paths;
# this repo uses repo-root skills/ wiki/ mnemon/ memories/ + install.sh/boot.sh.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}" )" && pwd)"
# This script lives at skills/ci-lint-check/scripts/ → repo root is 3 up
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default: run all checks
RUN_MARKDOWN=1
RUN_SKILLS=1
RUN_WIKI=1
RUN_MNEMON=1
RUN_SHELL_ROOT=1
RUN_SHELL_SKILLS=1
RUN_SYMLINK=1

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --markdown-only) RUN_MARKDOWN=1; RUN_SKILLS=0; RUN_WIKI=0; RUN_MNEMON=0; RUN_SHELL_ROOT=0; RUN_SHELL_SKILLS=0; RUN_SYMLINK=0 ;;
    --skills-only) RUN_MARKDOWN=0; RUN_SKILLS=1; RUN_WIKI=0; RUN_MNEMON=0; RUN_SHELL_ROOT=0; RUN_SHELL_SKILLS=0; RUN_SYMLINK=0 ;;
    --wiki-only) RUN_MARKDOWN=0; RUN_SKILLS=0; RUN_WIKI=1; RUN_MNEMON=0; RUN_SHELL_ROOT=0; RUN_SHELL_SKILLS=0; RUN_SYMLINK=0 ;;
    --mnemon-only) RUN_MARKDOWN=0; RUN_SKILLS=0; RUN_WIKI=0; RUN_MNEMON=1; RUN_SHELL_ROOT=0; RUN_SHELL_SKILLS=0; RUN_SYMLINK=0 ;;
    --shell-only) RUN_MARKDOWN=0; RUN_SKILLS=0; RUN_WIKI=0; RUN_MNEMON=0; RUN_SHELL_ROOT=1; RUN_SHELL_SKILLS=1; RUN_SYMLINK=0 ;;
    --symlink-only) RUN_MARKDOWN=0; RUN_SKILLS=0; RUN_WIKI=0; RUN_MNEMON=0; RUN_SHELL_ROOT=0; RUN_SHELL_SKILLS=0; RUN_SYMLINK=1 ;;
    -h|--help)
      cat <<EOF
Usage: $0 [OPTION]
Run CI lint validation locally (mirrors GitHub Actions lint-check job).

Options:
  --markdown-only    Run only markdown lint
  --skills-only      Run only SKILL.md validation
  --wiki-only        Run only wiki INDEX.md consistency
  --mnemon-only      Run only Mnemon seed.json validation
  --shell-only       Run only shell script syntax checks
  --symlink-only     Run only symlink persistence contract
  -h, --help         Show this help

No args: run all checks (default).
EOF
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

echo "=== CI Lint Check ==="
echo "Repo: $REPO_ROOT"
echo ""

cd "$REPO_ROOT"

# 1. Markdown lint
if [[ $RUN_MARKDOWN -eq 1 ]]; then
  echo -e "${YELLOW}[1/7] Markdown lint...${NC}"
  
  # Create markdownlint config matching CI
  cat > /tmp/.markdownlint.json << 'LINTCONF'
{
  "default": true,
  "MD001": false,
  "MD012": false,
  "MD013": false,
  "MD022": false,
  "MD024": { "siblings_only": true },
  "MD026": false,
  "MD031": false,
  "MD032": false,
  "MD033": false,
  "MD036": false,
  "MD040": false,
  "MD041": false,
  "MD047": false,
  "MD058": false,
  "MD060": false
}
LINTCONF
  
  markdownlint \
    wiki/*.md \
    skills/*/SKILL.md \
    README.md \
    --config /tmp/.markdownlint.json
  
  echo -e "  ${GREEN}✅ Markdown lint passed${NC}"
  echo ""
fi

# 2. SKILL.md validation
if [[ $RUN_SKILLS -eq 1 ]]; then
  echo -e "${YELLOW}[2/7] SKILL.md validation...${NC}"
  
  errors=0
  for skill in skills/*/SKILL.md; do
    [ -f "$skill" ] || continue
    name=$(basename "$(dirname "$skill")")
    
    # Check YAML frontmatter exists
    if ! head -1 "$skill" | grep -q "^---\$"; then
      echo -e "  ${RED}❌ $skill: missing YAML frontmatter (must start with ---)${NC}"
      errors=$((errors + 1))
      continue
    fi
    
    # Check frontmatter closes (look in first 20 lines)
    if ! sed -n "2,20p" "$skill" | grep -q "^---\$"; then
      echo -e "  ${RED}❌ $skill: unclosed YAML frontmatter${NC}"
      errors=$((errors + 1))
      continue
    fi
    
    # Check has name field
    if ! sed -n "2,/^---$/p" "$skill" | grep -q "^name:"; then
      echo -e "  ${RED}❌ $skill: missing 'name' field in frontmatter${NC}"
      errors=$((errors + 1))
      continue
    fi
    
    echo -e "  ${GREEN}✅ $name${NC}"
  done
  
  if [ $errors -gt 0 ]; then
    echo -e "  ${RED}❌ $errors skill(s) failed validation${NC}"
    exit 1
  fi
  
  echo -e "  ${GREEN}✅ All skills valid${NC}"
  echo ""
fi

# 3. Wiki INDEX.md consistency
if [[ $RUN_WIKI -eq 1 ]]; then
  echo -e "${YELLOW}[3/7] Wiki INDEX.md consistency...${NC}"
  
  errors=0
  for article in wiki/*.md; do
    basename=$(basename "$article")
    [ "$basename" = "INDEX.md" ] && continue
    
    if ! grep -q "$basename" wiki/INDEX.md; then
      echo -e "  ${RED}❌ $basename not listed in INDEX.md${NC}"
      errors=$((errors + 1))
    else
      echo -e "  ${GREEN}✅ $basename referenced in INDEX.md${NC}"
    fi
  done
  
  if [ $errors -gt 0 ]; then
    echo -e "  ${RED}❌ $errors article(s) missing from INDEX.md${NC}"
    exit 1
  fi
  
  echo -e "  ${GREEN}✅ Wiki INDEX.md is consistent${NC}"
  echo ""
fi

# 4. Mnemon seed.json validation
if [[ $RUN_MNEMON -eq 1 ]]; then
  echo -e "${YELLOW}[4/7] Mnemon seed.json validation...${NC}"
  
  SEED="mnemon/seed.json"
  if [ ! -f "$SEED" ]; then
    echo -e "  ${YELLOW}No seed.json found — skipping${NC}"
  else
    python3 mnemon/validate-seed.py "$SEED"
    echo -e "  ${GREEN}✅ Mnemon seed.json valid${NC}"
  fi
  echo ""
fi

# 5. Root shell script syntax
if [[ $RUN_SHELL_ROOT -eq 1 ]]; then
  echo -e "${YELLOW}[5/7] Root shell scripts syntax...${NC}"
  
  for script in install.sh boot.sh stop.sh lib/*.sh; do
    [ -f "$script" ] || continue
    if bash -n "$script" 2>&1; then
      echo -e "  ${GREEN}✅ $(basename "$script")${NC}"
    else
      echo -e "  ${RED}❌ $(basename "$script"): syntax error${NC}"
      exit 1
    fi
  done
  
  echo -e "  ${GREEN}✅ All root shell scripts valid${NC}"
  echo ""
fi

# 6. Skill shell script syntax
if [[ $RUN_SHELL_SKILLS -eq 1 ]]; then
  echo -e "${YELLOW}[6/7] Skill shell scripts syntax...${NC}"
  
  for script in skills/*/scripts/*.sh; do
    [ -f "$script" ] || continue
    if bash -n "$script" 2>&1; then
      echo -e "  ${GREEN}✅ $(basename "$script")${NC}"
    else
      echo -e "  ${RED}❌ $(basename "$script"): syntax error${NC}"
      exit 1
    fi
  done
  
  echo -e "  ${GREEN}✅ All skill shell scripts valid${NC}"
  echo ""
fi

# 7. Symlink persistence contract
if [[ $RUN_SYMLINK -eq 1 ]]; then
  echo -e "${YELLOW}[7/7] Symlink persistence contract...${NC}"
  
  FAIL=0
  
  MEM_TRACKED="$REPO_ROOT/memories"
  SKILLS_TRACKED="$REPO_ROOT/skills"
  
  if [ -d "$MEM_TRACKED" ]; then
    echo -e "  ${GREEN}✅ Tracked memories dir exists -> $MEM_TRACKED${NC}"
  else
    echo -e "  ${RED}❌ Tracked memories dir missing: $MEM_TRACKED${NC}"
    FAIL=1
  fi
  
  if [ -d "$SKILLS_TRACKED" ]; then
    echo -e "  ${GREEN}✅ Tracked skills dir exists -> $SKILLS_TRACKED${NC}"
  else
    echo -e "  ${RED}❌ Tracked skills dir missing: $SKILLS_TRACKED${NC}"
    FAIL=1
  fi
  
  # .minions wires symlinks in boot.sh (knowledge section), not
  # post-create-cmd.sh / start-hermes.sh like upstream. Grep boot.sh for the
  # readlink-guarded symlink pattern.
  if grep -q "ln -s.*HERMES_SKILLS_DIR.*MINIONS_SKILLS_LINK\|MINIONS_SKILLS_LINK.*ln -s \|ln -s .*skills" boot.sh; then
    echo -e "  ${GREEN}✅ boot.sh creates skills symlink${NC}"
  else
    echo -e "  ${RED}❌ boot.sh missing skills symlink${NC}"
    FAIL=1
  fi
  
  if grep -q "HERMES_MEMORIES.*ln -s\|ln -s.*memories\|MEMORIES_LINK.*ln -s " boot.sh; then
    echo -e "  ${GREEN}✅ boot.sh repair guard covers memories${NC}"
  else
    echo -e "  ${RED}❌ boot.sh missing memories repair guard${NC}"
    FAIL=1
  fi
  
  if [ "$FAIL" -eq 0 ]; then
    echo -e "  ${GREEN}✅ Symlink persistence contract valid${NC}"
  else
    exit 1
  fi
  echo ""
fi

echo -e "${GREEN}=== ALL CHECKS PASSED ===${NC}"