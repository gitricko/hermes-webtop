#!/usr/bin/env bash
# free-disk-space.sh
# Replicates jlumbroso/free-disk-space GitHub Action + adds Codespace-specific cleanup
# Run as: sudo bash free-disk-space.sh [--dry-run]
#
# Options:
#   --dry-run      Show what would be removed without deleting anything
#   --force        Skip confirmation prompts
#   --keep-go      Skip Go cleanup
#   --keep-llvm    Skip LLVM/Clang cleanup
#   --keep-conda   Skip Conda cleanup
#   --keep-nvm     Skip Node.js/NVM cleanup
#   --keep-java    Skip Java cleanup
#   --keep-ruby    Skip Ruby/RVM cleanup
#   --skip <step>  Skip a specific step (android, dotnet, haskell, apt-large,
#                  docker-images, swap, conda, llvm, go, valgrind, cmake,
#                  tmp, python-dev, gcc, nvm, java, ruby)

set -eo pipefail

# --- Helpers ---

print_sep() {
  local ch="${1:-=}" width="${2:-80}"
  printf '%*s\n' "$width" '' | tr ' ' "$ch"
}

get_available_kb() {
  df -a "$1" | awk 'NR > 1 {sum += $4} END {print sum+0}'
}

# Human-readable byte formatter — pure awk, no numfmt/bc required
format_human() {
  local kb=$1
  awk -v kb="$kb" '
    BEGIN {
      if (kb >= 1048576)      { printf "%.1f GB", kb/1048576 }
      else if (kb >= 1024)    { printf "%.1f MB", kb/1024    }
      else if (kb > 0)        { printf "%.0f KB", kb          }
      else                    { printf "0 KB"                 }
    }'
}

# Estimate size of a path in KB before deleting it
estimate_size_kb() {
  local path=$1
  if [[ -d "$path" ]]; then
    du -sk "$path" 2>/dev/null | awk '{print $1}'
  elif [[ -f "$path" ]]; then
    stat -c%s "$path" 2>/dev/null | awk '{print int($1/1024)}'
  else
    echo 0
  fi
}

saved() {
  local before=$1 title="${2:-}"
  local after end_saved
  [[ -z "$before" ]] && return
  after=$(get_available_kb '/')
  end_saved=$((after - before))
  if [[ -n "$title" ]]; then
    print_sep '*'
    printf "=> %s: Saved %s\n" "$title" "$(format_human $end_saved)"
    print_sep '*'
    echo
  fi
}

warn()  { echo "[WARN]  $*" >&2; }
info()  { echo "[INFO]  $*"; }
die()   { echo "[ERROR] $*" >&2; exit 1; }

remove() {
  local label="$1"; shift
  local target="$1"
  local estimated

  if [[ ! -e "$target" ]] && [[ ! -e $(dirname "$target" 2>/dev/null) ]]; then
    info "[skip] $label — not found"
    return 0
  fi

  estimated=$(estimate_size_kb "$target")
  if [[ "$DRY_RUN" == "1" ]]; then
    info "[DRY-RUN] Would remove: $target ($(format_human $estimated))"
    return 0
  fi

  if [[ "$FORCE" != "1" ]] && [[ "$estimated" -gt 0 ]]; then
    info "Removing $label ($(format_human $estimated))..."
  fi
  sudo rm -rf "$target" 2>/dev/null || warn "Failed to remove: $target"
}

snapshot_kb() { get_available_kb '/'; }

# --- Argument parsing ---

DRY_RUN="0"
FORCE="0"
SKIP_DOCKER="0"
SKIP_GO="0"
SKIP_LLVM="0"
SKIP_CONDA="0"
SKIP_NVM="0"
SKIP_JAVA="0"
SKIP_RUBY="0"
SKIP_OTHERS=""

should_skip() {
  local step=$1
  for s in $SKIP_OTHERS; do
    [[ "$s" == "$step" ]] && return 0
  done
  case "$step" in
    docker-images) [[ "$SKIP_DOCKER" == "1" ]] && return 0 ;;
    go)             [[ "$SKIP_GO" == "1" ]]       && return 0 ;;
    llvm)           [[ "$SKIP_LLVM" == "1" ]]     && return 0 ;;
    conda)          [[ "$SKIP_CONDA" == "1" ]]    && return 0 ;;
    nvm)            [[ "$SKIP_NVM" == "1" ]]       && return 0 ;;
    java)           [[ "$SKIP_JAVA" == "1" ]]      && return 0 ;;
    ruby)           [[ "$SKIP_RUBY" == "1" ]]      && return 0 ;;
  esac
  return 1
}

for arg in "$@"; do
  case "$arg" in
    --dry-run)      DRY_RUN="1"   ;;
    --force)        FORCE="1"     ;;
    --keep-docker)  SKIP_DOCKER="1" ;;
    --keep-go)      SKIP_GO="1"     ;;
    --keep-llvm)    SKIP_LLVM="1"   ;;
    --keep-conda)   SKIP_CONDA="1"  ;;
    --keep-nvm)     SKIP_NVM="1"    ;;
    --keep-java)    SKIP_JAVA="1"   ;;
    --keep-ruby)    SKIP_RUBY="1"   ;;
    --skip)
      # handled in next iteration; accumulate following args as skip targets
      ;;
    --skip=*)
      SKIP_OTHERS="${SKIP_OTHERS} ${arg#--skip=}"
      ;;
    --help)
      echo "Usage: $0 [--dry-run] [--force] [--keep-docker] [--keep-go]"
      echo "              [--keep-llvm] [--keep-conda] [--keep-nvm] [--keep-java]"
      echo "              [--keep-ruby] [--skip <step>]"
      echo ""
      echo "Options:"
      echo "  --dry-run      Preview what would be removed (no deletions)"
      echo "  --force        Skip confirmation prompts"
      echo "  --keep-docker  Skip Docker image prune"
      echo "  --keep-go      Skip Go cleanup"
      echo "  --keep-llvm    Skip LLVM/Clang cleanup"
      echo "  --keep-conda   Skip Conda cleanup"
      echo "  --keep-nvm     Skip Node.js/NVM cleanup"
      echo "  --keep-java    Skip Java cleanup"
      echo "  --keep-ruby    Skip Ruby/RVM cleanup"
      echo "  --skip <step>  Skip a specific step (see script header for list)"
      exit 0
      ;;
    *)
      # collect positional skip targets (after --skip flag)
      if [[ "$prev_arg" == "--skip" ]]; then
        SKIP_OTHERS="${SKIP_OTHERS} $arg"
      fi
      ;;
  esac
  prev_arg="$arg"
done

# =============================================================================
# PRE-CLEANUP REPORT
# =============================================================================

echo ""
print_sep '='
echo "DISK SPACE BEFORE CLEAN-UP:"
echo ""
df -h /
echo ""
print_sep '='

BEFORE_TOTAL=$(snapshot_kb)
TOTAL_SAVED=0

# =============================================================================
# STEP 1: GitHub Actions runner cleanup (jlumbroso/free-disk-space)
# =============================================================================

echo ""
echo "=== GitHub Actions Runner Cleanup ==="

# 1a. Android SDK
STEP_BEFORE=$(snapshot_kb)
remove "Android SDK" "/usr/local/lib/android"
saved $STEP_BEFORE "Android SDK"
[[ $? -eq 0 ]] && TOTAL_SAVED=$((TOTAL_SAVED + $(snapshot_kb) - STEP_BEFORE)) || true

# 1b. .NET runtime
STEP_BEFORE=$(snapshot_kb)
remove ".NET runtime" "/usr/share/dotnet"
saved $STEP_BEFORE ".NET runtime"

# 1c. Haskell GHC + GHCup
STEP_BEFORE=$(snapshot_kb)
remove "Haskell GHC" "/opt/ghc"
remove "GHCup"       "/usr/local/.ghcup"
saved $STEP_BEFORE "Haskell GHC"

# 1d. Large apt packages (regex-matched toolchains)
STEP_BEFORE=$(snapshot_kb)
if [[ "$DRY_RUN" == "1" ]]; then
  info "[DRY-RUN] Would apt-get remove:"
  info "  aspnetcore-*, dotnet-*, llvm-*, php*, mongodb-*, mysql-*"
  info "  azure-cli, google-chrome-stable, firefox, powershell"
  info "  mono-devel, libgl1-mesa-dri, google-cloud-sdk, google-cloud-cli"
else
  info "Removing large apt packages..."
  sudo apt-get remove -y \
    '^aspnetcore-.*' \
    '^dotnet-.*'    \
    '^llvm-.*'      \
    'php.*'         \
    '^mongodb-.*'   \
    '^mysql-.*'     \
    azure-cli \
    google-chrome-stable \
    firefox \
    powershell \
    mono-devel \
    libgl1-mesa-dri \
    google-cloud-sdk \
    google-cloud-cli \
    --fix-missing 2>/dev/null || true
  sudo apt-get autoremove -y 2>/dev/null || true
  sudo apt-get clean -y 2>/dev/null || true
fi
saved $STEP_BEFORE "Large apt packages"

# 1e. Docker images prune (non-destructive — just unused images)
if command -v docker &>/dev/null && ! should_skip docker-images; then
  STEP_BEFORE=$(snapshot_kb)
  if [[ "$DRY_RUN" == "1" ]]; then
    info "[DRY-RUN] Would prune all Docker images"
  else
    info "Pruning Docker images..."
    sudo docker image prune --all --force 2>/dev/null || true
  fi
  saved $STEP_BEFORE "Docker images"
elif should_skip docker-images; then
  info "[skip] Docker images — disabled via --keep-docker / --skip docker-images"
fi

# 1f. Tool cache ($AGENT_TOOLSDIRECTORY)
if [[ -n "${AGENT_TOOLSDIRECTORY:-}" ]]; then
  STEP_BEFORE=$(snapshot_kb)
  remove "Tool cache" "$AGENT_TOOLSDIRECTORY"
  saved $STEP_BEFORE "Tool cache"
fi

# 1g. Swap
STEP_BEFORE=$(snapshot_kb)
if [[ "$DRY_RUN" == "1" ]]; then
  info "[DRY-RUN] Would disable swap and remove /mnt/swapfile"
else
  sudo swapoff -a 2>/dev/null || true
  sudo rm -f /mnt/swapfile 2>/dev/null || true
fi
saved $STEP_BEFORE "Swap storage"

# =============================================================================
# STEP 2: Codespace-specific cleanup
# =============================================================================

echo ""
echo "=== Codespace/GitHub Codespaces Cleanup ==="

# 2a. Conda
if ! should_skip conda; then
  STEP_BEFORE=$(snapshot_kb)
  remove "Conda" "/opt/conda"
  saved $STEP_BEFORE "Conda (/opt/conda)"
else
  info "[skip] Conda — disabled via --keep-conda / --skip conda"
fi

# 2b. LLVM/Clang
if ! should_skip llvm; then
  STEP_BEFORE=$(snapshot_kb)
  remove "LLVM-18 toolchain" "/usr/lib/llvm-18"
  saved $STEP_BEFORE "LLVM-18 toolchain"
else
  info "[skip] LLVM-18 toolchain — disabled via --keep-llvm / --skip llvm"
fi

# 2c. Docker/Moby packages
#   By default: SKIPPED (user needs docker)
#   To remove:  --skip docker-images (removes moby packages, keeps daemon)
#   To skip (keep): already default — use --keep-docker or --skip docker-images
if command -v docker &>/dev/null; then
  if should_skip docker-images; then
    info "[skip] Docker/Moby packages — preserved via --keep-docker / --skip docker-images"
  fi
fi

# 2d. Go
if ! should_skip go; then
  STEP_BEFORE=$(snapshot_kb)
  remove "Go" "/usr/local/go"
  saved $STEP_BEFORE "Go (/usr/local/go)"
else
  info "[skip] Go — disabled via --keep-go / --skip go"
fi

# 2e. Valgrind
if ! should_skip valgrind; then
  STEP_BEFORE=$(snapshot_kb)
  if [[ "$DRY_RUN" == "1" ]]; then
    info "[DRY-RUN] Would remove valgrind packages"
  else
    info "Removing valgrind..."
    sudo apt-get remove -y valgrind 2>/dev/null || true
    sudo apt-get autoremove -y 2>/dev/null || true
  fi
  saved $STEP_BEFORE "Valgrind"
else
  info "[skip] Valgrind — disabled via --skip valgrind"
fi

# 2f. vim-runtime (full vim docs — use vim-tiny or neovim instead)
STEP_BEFORE=$(snapshot_kb)
remove "vim-runtime" "/usr/share/vim/vimfiles" 2>/dev/null || true
remove "vim-runtime" "/usr/share/vim/addons"   2>/dev/null || true
# Only remove the docs, keep the binary
if [[ -d /usr/share/vim/vim91/doc ]] || [[ -d /usr/share/vim/vim90/doc ]]; then
  if [[ "$DRY_RUN" != "1" ]]; then
    sudo rm -rf /usr/share/vim/*/doc/*.txt /usr/share/vim/*/doc/*.help 2>/dev/null || true
  else
    info "[DRY-RUN] Would trim vim runtime docs"
  fi
fi
saved $STEP_BEFORE "vim runtime docs"

# 2g. cmake
if ! should_skip cmake; then
  STEP_BEFORE=$(snapshot_kb)
  if [[ "$DRY_RUN" == "1" ]]; then
    info "[DRY-RUN] Would remove cmake"
  else
    sudo apt-get remove -y cmake 2>/dev/null || true
    sudo apt-get autoremove -y 2>/dev/null || true
  fi
  saved $STEP_BEFORE "cmake"
else
  info "[skip] cmake — disabled via --skip cmake"
fi

# 2h. /tmp cleanup
if ! should_skip tmp; then
  STEP_BEFORE=$(snapshot_kb)
  if [[ "$DRY_RUN" == "1" ]]; then
    info "[DRY-RUN] Would clean /tmp (excluding tmpfs)"
  else
    if [[ -d /tmp ]] && ! mountpoint -q /tmp 2>/dev/null; then
      sudo rm -rf /tmp/* 2>/dev/null || true
    fi
  fi
  saved $STEP_BEFORE "/tmp files"
else
  info "[skip] /tmp — disabled via --skip tmp"
fi

# 2i. Python dev headers
if ! should_skip python-dev; then
  STEP_BEFORE=$(snapshot_kb)
  if [[ "$DRY_RUN" == "1" ]]; then
    info "[DRY-RUN] Would remove libpython3.12-dev"
  else
    sudo apt-get remove -y libpython3.12-dev 2>/dev/null || true
    sudo apt-get autoremove -y 2>/dev/null || true
  fi
  saved $STEP_BEFORE "Python dev headers"
else
  info "[skip] Python dev headers — disabled via --skip python-dev"
fi

# 2j. GCC/G++ dev packages
if ! should_skip gcc; then
  STEP_BEFORE=$(snapshot_kb)
  if [[ "$DRY_RUN" == "1" ]]; then
    info "[DRY-RUN] Would remove GCC/G++ dev packages"
  else
    sudo apt-get remove -y gcc-13 g++-13 cpp-13 gcc-13-x86-64-linux-gnu 2>/dev/null || true
    sudo apt-get autoremove -y 2>/dev/null || true
  fi
  saved $STEP_BEFORE "GCC/G++ dev packages"
else
  info "[skip] GCC/G++ dev packages — disabled via --skip gcc"
fi

# 2k. Node.js / NVM (Node Version Manager)
#     NVM stores versions under /usr/local/share/nvm/versions/node (~426 MB for v24)
#     Also clean ~/.cache/node to recover npm cache
if ! should_skip nvm; then
  STEP_BEFORE=$(snapshot_kb)
  if [[ "$DRY_RUN" == "1" ]]; then
    nvm_size=$(du -sk /usr/local/share/nvm 2>/dev/null | awk '{print $1}' || echo 0)
    info "[DRY-RUN] Would remove NVM (${nvm_size} KB)"
  else
    info "Removing NVM..."
    sudo rm -rf /usr/local/share/nvm 2>/dev/null || true
    sudo rm -rf ~/.nvm ~/.cache/node 2>/dev/null || true
    # Clean up shell integration
    sudo sed -i '/NVM_DIR/d' ~/.bashrc 2>/dev/null || true
    info "NVM removed. Re-install with: curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash"
  fi
  saved $STEP_BEFORE "Node.js / NVM"
else
  info "[skip] Node.js / NVM — disabled via --keep-nvm / --skip nvm"
fi

# 2l. Java / JDK
#     Codespaces uses /home/codespace/java/current as the managed JDK path
#     Also remove /usr/lib/jvm (system-wide OpenJDK packages)
if ! should_skip java; then
  STEP_BEFORE=$(snapshot_kb)
  if [[ "$DRY_RUN" == "1" ]]; then
    java_size=$(du -sk /home/codespace/java 2>/dev/null | awk '{print $1}' || echo 0)
    info "[DRY-RUN] Would remove Java (${java_size} KB)"
  else
    info "Removing Java..."
    sudo rm -rf /home/codespace/java 2>/dev/null || true
    sudo apt-get remove -y --allow-change-held-packages \
      openjdk-.*-jre-headless openjdk-.*-jdk-headless 2>/dev/null || true
    sudo apt-get autoremove -y 2>/dev/null || true
  fi
  saved $STEP_BEFORE "Java / JDK"
else
  info "[skip] Java / JDK — disabled via --keep-java / --skip java"
fi

# 2m. Ruby / RVM
#     RVM installs rubies under /usr/local/rvm/rubies (~152 MB for ruby-3.4.7)
#     Also removes gem cache and gemsets
if ! should_skip ruby; then
  STEP_BEFORE=$(snapshot_kb)
  if [[ "$DRY_RUN" == "1" ]]; then
    ruby_size=$(du -sk /usr/local/rvm 2>/dev/null | awk '{print $1}' || echo 0)
    info "[DRY-RUN] Would remove Ruby/RVM (${ruby_size} KB)"
  else
    info "Removing Ruby/RVM..."
    sudo rm -rf /usr/local/rvm 2>/dev/null || true
    sudo rm -rf /usr/local/rvm /var/lib/gems/2.7 /var/lib/gems/3.0 /var/lib/gems/3.4 2>/dev/null || true
    sudo rm -rf ~/.rvm 2>/dev/null || true
    # Clean up shell integration
    sudo sed -i '/rvm\/scripts\/rvm/d' ~/.bashrc 2>/dev/null || true
    sudo rm -f /etc/profile.d/rvm.sh 2>/dev/null || true
  fi
  saved $STEP_BEFORE "Ruby / RVM"
else
  info "[skip] Ruby / RVM — disabled via --keep-ruby / --skip ruby"
fi

# =============================================================================
# SUMMARY
# =============================================================================

AFTER_TOTAL=$(snapshot_kb)
TOTAL_FREED=$((AFTER_TOTAL - BEFORE_TOTAL))

echo ""
print_sep '='
echo "DISK SPACE AFTER CLEAN-UP:"
echo ""
df -h /
echo ""
print_sep '='
echo ""
echo "Total space recovered: $(format_human $TOTAL_FREED)"
echo ""
echo "Done."
