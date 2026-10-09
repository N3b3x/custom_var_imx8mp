# shellcheck shell=bash
# =============================================================================
#  scripts/lib/common.sh - helpers shared by every build step
# =============================================================================
#
#  This file is sourced (never executed). It provides:
#
#    * logging          : info / warn / die / section
#    * run              : print WHY + the exact command, then execute it
#                         (prints only, when DRY_RUN=1  ->  "explain mode")
#    * git_checkout     : clone/fetch a repo at a pinned branch + commit
#    * fetch            : download a file once and verify its sha256
#    * setup_toolchain  : make CROSS_COMPILE point at a working aarch64 gcc
#    * apply_patches    : apply patches/<component>/*.patch to a source tree
#
#  Directory layout (everything generated lives under build/, git-ignored):
#
#    build/downloads/   tarballs and firmware archives (cached)
#    build/toolchain/   unpacked Arm GNU toolchain
#    build/src/         git checkouts: uboot-imx, imx-atf, imx-mkimage, linux-imx
#    build/work/        intermediate files (staged rootfs, ext4 image...)
#    build/deploy/      FINAL ARTIFACTS: imx-boot.bin, Image.gz, dtbs, sdcard.img
#    build/logs/        one log file per step
# =============================================================================

# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------
# TOP_DIR is the repository root; it is computed from this file's location so
# the scripts work no matter which directory you call them from.
TOP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PATCH_DIR="$TOP_DIR/patches"

# Derived from BUILD_DIR; re-run by load_config so that BUILD_DIR may be set
# in config/local.conf.
set_paths() {
  : "${BUILD_DIR:=$TOP_DIR/build}"
  DL_DIR="$BUILD_DIR/downloads"
  SRC_DIR="$BUILD_DIR/src"
  WORK_DIR="$BUILD_DIR/work"
  DEPLOY_DIR="$BUILD_DIR/deploy"
  LOG_DIR="$BUILD_DIR/logs"
  TOOLCHAIN_DIR="$BUILD_DIR/toolchain"
}
set_paths

# -----------------------------------------------------------------------------
# Global switches (set by build.sh from the command line, or by environment)
# -----------------------------------------------------------------------------
: "${DRY_RUN:=0}"     # 1 = print every command with its explanation, run nothing
: "${VERBOSE:=0}"     # 1 = pass V=1 to make so every compiler call is shown
: "${UPDATE:=0}"      # 1 = re-fetch git sources even if they are already checked out
: "${JOBS:=$(nproc)}" # parallel make jobs
: "${ASSUME_YES:=0}"  # 1 = do not ask for confirmation (DANGEROUS with flash)

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
# Colours only when writing to a terminal, so log files stay clean.
if [[ -t 1 ]]; then
  C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'
  C_RED=$'\e[31m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_BLUE=$'\e[34m'; C_CYAN=$'\e[36m'
else
  C_RESET=; C_BOLD=; C_DIM=; C_RED=; C_GREEN=; C_YELLOW=; C_BLUE=; C_CYAN=
fi

ts()      { date '+%H:%M:%S'; }
info()    { printf '%s[%s]%s %s\n' "$C_GREEN" "$(ts)" "$C_RESET" "$*"; }
warn()    { printf '%s[%s] WARNING:%s %s\n' "$C_YELLOW" "$(ts)" "$C_RESET" "$*" >&2; }
die()     { printf '%s[%s] ERROR:%s %s\n' "$C_RED" "$(ts)" "$C_RESET" "$*" >&2; exit 1; }
section() { printf '\n%s==== %s ====%s\n' "$C_BOLD$C_BLUE" "$*" "$C_RESET"; }

# run "<why this command exists>" cmd arg1 arg2 ...
#
# Prints the explanation and the exact, copy-pasteable command, then runs it.
# With DRY_RUN=1 nothing is executed, so `./build.sh <step> --dry-run` turns
# into a step-by-step manual of how to do the build by hand.
run() {
  local why=$1; shift
  printf '%s  # %s%s\n' "$C_DIM" "$why" "$C_RESET"
  printf '%s  $ %s%s\n' "$C_CYAN" "$(short_paths "$(quote_cmd "$@")")" "$C_RESET"
  [[ $DRY_RUN == 1 ]] && return 0
  "$@"
}

# run_sh "<why>" '<shell command line with pipes/redirections>'
# For commands that need a pipe or redirection: the string is shown verbatim
# (readable!) and executed with bash -c.
run_sh() {
  local why=$1 cmd=$2
  printf '%s  # %s%s\n' "$C_DIM" "$why" "$C_RESET"
  printf '%s  $ %s%s\n' "$C_CYAN" "$(short_paths "$cmd")" "$C_RESET"
  [[ $DRY_RUN == 1 ]] && return 0
  bash -o pipefail -c "$cmd"
}

# Same as run, but for "cd": it changes the directory of the calling script
# (also in dry-run, when the directory exists, so later steps print sensibly).
run_cd() {
  local why=$1 dir=$2
  printf '%s  # %s%s\n' "$C_DIM" "$why" "$C_RESET"
  printf '%s  $ cd %s%s\n' "$C_CYAN" "$(short_paths "$(printf '%q' "$dir")")" "$C_RESET"
  if [[ $DRY_RUN == 1 ]]; then
    cd "$dir" 2>/dev/null || true
  else
    cd "$dir" || die "cannot cd to $dir"
  fi
}

# Display only: write the build directory as $B so commands stay short and
# can still be copy-pasted after `export B=<build dir>` (printed at start).
short_paths() { local s=$1; printf '%s' "${s//"$BUILD_DIR"/\$B}"; }

# Render an argv array as a shell-quoted command line (for display only).
# Prefers readable 'single quotes'; for --option=value only the value is quoted.
quote_cmd() {
  local out='' a
  for a in "$@"; do
    if [[ $a =~ ^[A-Za-z0-9_./:=+,@%-]+$ ]]; then out+="$a "
    elif [[ $a =~ ^(--?[A-Za-z0-9_-]+=)(.*)$ ]]; then out+="${BASH_REMATCH[1]}$(quote_val "${BASH_REMATCH[2]}") "
    else out+="$(quote_val "$a") "; fi
  done
  printf '%s' "${out% }"
}
quote_val() {
  local v=$1
  if [[ $v =~ ^[A-Za-z0-9_./:=+,@%-]*$ && -n $v ]]; then printf '%s' "$v"
  elif [[ $v != *"'"* ]]; then printf "'%s'" "$v"
  else v=${v//\\/\\\\}; v=${v//\"/\\\"}; v=${v//\$/\\\$}; v=${v//\`/\\\`}; printf '"%s"' "$v"; fi
}

# Explain a concept in a few lines, before a group of commands.
explain() { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET" | sed 's/^/  /'; }

# -----------------------------------------------------------------------------
# Error handling: print the failing command and line, plus where the log is.
# -----------------------------------------------------------------------------
on_error() {
  local rc=$? line=$1 cmd=$2 i
  printf '\n%s[%s] FAILED (exit %s)%s\n' "$C_RED" "$(ts)" "$rc" "$C_RESET" >&2
  if [[ $cmd == '"$@"' || $cmd == 'bash -o pipefail -c "$cmd"' ]]; then
    printf '    command: the last "$ ..." line printed above\n' >&2
  else
    printf '    command: %s\n' "$cmd" >&2
  fi
  # Call stack, innermost first, e.g. "run (common.sh:83) <- do_atf (uboot.sh:97)"
  printf '    where:   %s:%s' "${BASH_SOURCE[1]##*/}" "$line" >&2
  for ((i = 1; i < ${#FUNCNAME[@]} - 1; i++)); do
    printf ' <- %s (%s:%s)' "${FUNCNAME[i]}" "${BASH_SOURCE[i+1]##*/}" "${BASH_LINENO[i]}" >&2
  done
  printf '\n' >&2
  [[ -n ${CURRENT_LOG:-} ]] && printf '    log:     %s\n' "$CURRENT_LOG" >&2
  printf '    help:    docs/09-troubleshooting.md\n' >&2
  exit "$rc"
}

# Call at the top of every step script.
#   -E  : ERR trap is inherited by functions
#   -e  : stop at the first failing command
#   -u  : using an unset variable is an error (catches typos)
#   -o pipefail : a pipeline fails if ANY command in it fails, not just the last
strict_mode() {
  set -Eeuo pipefail
  trap 'on_error $LINENO "$BASH_COMMAND"' ERR
}

# Send all further output of the current script to the terminal AND a log file.
start_log() {
  local name=$1
  export B="$BUILD_DIR"
  explain "In the commands below \$B = $BUILD_DIR"
  [[ $DRY_RUN == 1 ]] && return 0
  mkdir -p "$LOG_DIR"
  CURRENT_LOG="$LOG_DIR/$name-$(date +%Y%m%d-%H%M%S).log"
  ln -sfn "$(basename "$CURRENT_LOG")" "$LOG_DIR/$name.log"
  # The terminal keeps its colours; the copy in the log file has them stripped.
  exec > >(tee >(sed -u 's/\x1b\[[0-9;]*m//g' >>"$CURRENT_LOG")) 2>&1
  info "Logging to $CURRENT_LOG"
}

# -----------------------------------------------------------------------------
# Small checks
# -----------------------------------------------------------------------------
need_cmd() {
  local missing=() c
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
  ((${#missing[@]} == 0)) && return 0
  if [[ $DRY_RUN == 1 ]]; then warn "missing host tool(s): ${missing[*]} (ignored in dry-run)"; return 0; fi
  die "missing host tool(s): ${missing[*]}  ->  run: ./build.sh deps"
}

need_file() {
  [[ $DRY_RUN == 1 ]] && return 0
  local f
  for f in "$@"; do [[ -e $f ]] || die "required file not found: $f"; done
}

confirm() {
  [[ $ASSUME_YES == 1 ]] && return 0
  local reply
  read -r -p "$1 [y/N] " reply
  [[ $reply =~ ^[Yy]([Ee][Ss])?$ ]]
}

# Warn early instead of failing an hour into the build.
check_disk_space() {
  local need_gb=$1 free_gb
  mkdir -p "$BUILD_DIR"
  free_gb=$(df -P -BG "$BUILD_DIR" | awk 'NR==2 {gsub("G","",$4); print $4}')
  if (( free_gb < need_gb )); then
    warn "Only ${free_gb} GB free in $BUILD_DIR, the build needs about ${need_gb} GB."
    confirm "Continue anyway?" || die "not enough disk space (set BUILD_DIR to another disk in config/local.conf)"
  fi
}

# Human-readable size of a file.
hsize() { du -h "$1" 2>/dev/null | cut -f1; }

# -----------------------------------------------------------------------------
# git_checkout <name> <url> <branch> <rev> <dest>
#
# First run : shallow-clone only the needed commit (fast, small).
# Later runs: leave the tree alone (your local edits are safe) unless
#             UPDATE=1 (./build.sh --update) is given.
# -----------------------------------------------------------------------------
git_checkout() {
  local name=$1 url=$2 branch=$3 rev=$4 dest=$5
  local want=${rev:-$branch}

  if [[ -d $dest/.git ]]; then
    if [[ $UPDATE != 1 ]]; then
      info "$name: using existing checkout $dest ($(git -C "$dest" rev-parse --short HEAD 2>/dev/null)); pass --update to re-sync"
      return 0
    fi
    if [[ -n $(git -C "$dest" status --porcelain --untracked-files=no 2>/dev/null) ]]; then
      die "$name: $dest has local modifications; commit/stash them (or turn them into patches/, see docs/08-customizing.md) before --update"
    fi
  else
    run "Create an empty git repository for $name" git init -q "$dest"
    run "Point it at the upstream repository" git -C "$dest" remote add origin "$url"
  fi

  # --depth 1 fetches a single commit instead of the full history; for the
  # kernel that is ~250 MB instead of several GB.
  run "Download $name at ${rev:+commit $rev on }branch $branch (history depth 1)" \
    git -C "$dest" fetch --depth 1 origin "$want"
  run "Check out exactly that commit (detached HEAD)" \
    git -C "$dest" checkout -q --force FETCH_HEAD
  # A named local branch makes `git log`/`git status` friendlier to read.
  run "Name the checkout after the upstream branch" \
    git -C "$dest" checkout -q -B "$branch"
}

# -----------------------------------------------------------------------------
# apply_patches <component> <source-dir>
#
# Applies patches/<component>/*.patch in name order, exactly once. A marker
# file inside .git remembers what has been applied.
# -----------------------------------------------------------------------------
apply_patches() {
  local comp=$1 dir=$2 p stamp
  local pdir="$PATCH_DIR/$comp"
  compgen -G "$pdir/*.patch" >/dev/null || return 0
  stamp="$dir/.git/applied-patches"
  [[ $DRY_RUN == 1 ]] || touch "$stamp"
  for p in "$pdir"/*.patch; do
    if [[ $DRY_RUN != 1 ]] && grep -qxF "$(basename "$p")" "$stamp"; then
      info "$comp: patch $(basename "$p") already applied"
      continue
    fi
    run "Apply local patch $(basename "$p") to $comp" git -C "$dir" apply --whitespace=nowarn "$p"
    [[ $DRY_RUN == 1 ]] || basename "$p" >>"$stamp"
  done
}

# -----------------------------------------------------------------------------
# fetch <url> <dest-file> [sha256]
# Download once (resumable) and verify the checksum when one is given.
# -----------------------------------------------------------------------------
fetch() {
  local url=$1 dest=$2 sha=${3:-}
  mkdir -p "$(dirname "$dest")"
  if [[ ! -s $dest ]]; then
    run "Download $(basename "$dest")" \
      wget --no-verbose --show-progress --continue -O "$dest.part" "$url"
    [[ $DRY_RUN == 1 ]] || mv "$dest.part" "$dest"
  else
    info "Already downloaded: $dest"
  fi
  if [[ -n $sha ]]; then
    run_sh "Verify the download against the known sha256 (protects against corrupt/tampered files)" \
      "echo '$sha  $dest' | sha256sum --check --quiet"
  fi
}

# -----------------------------------------------------------------------------
# setup_toolchain
# Exports ARCH and CROSS_COMPILE for the kernel/U-Boot/ATF makefiles.
# -----------------------------------------------------------------------------
setup_toolchain() {
  export ARCH=arm64
  local prefix
  # Arm only publishes this cross toolchain for x86-64 hosts. On an ARM64
  # laptop/board the distro's native gcc already targets aarch64.
  if [[ $TOOLCHAIN == arm && $(uname -m) == aarch64 ]]; then
    info "ARM64 host detected: using the native aarch64-linux-gnu-gcc (TOOLCHAIN=system)"
    TOOLCHAIN=system
  fi
  case $TOOLCHAIN in
    arm)
      local name="arm-gnu-toolchain-${ARM_TOOLCHAIN_VERSION}-x86_64-aarch64-none-linux-gnu"
      local dir="$TOOLCHAIN_DIR/$name"
      if [[ ! -x $dir/bin/aarch64-none-linux-gnu-gcc ]]; then
        section "Installing Arm GNU Toolchain $ARM_TOOLCHAIN_VERSION (one-time)"
        fetch "$ARM_TOOLCHAIN_URL" "$DL_DIR/$name.tar.xz" "$ARM_TOOLCHAIN_SHA256"
        mkdir -p "$TOOLCHAIN_DIR"
        run "Unpack the toolchain into build/toolchain" tar -xJf "$DL_DIR/$name.tar.xz" -C "$TOOLCHAIN_DIR"
      fi
      # Put the toolchain first in PATH so commands below stay short and
      # readable: aarch64-none-linux-gnu-gcc instead of a long absolute path.
      export PATH="$dir/bin:$PATH"
      prefix="aarch64-none-linux-gnu-"
      explain "PATH=$dir/bin:\$PATH"
      ;;
    system)
      prefix="aarch64-linux-gnu-"
      command -v "${prefix}gcc" >/dev/null || die "TOOLCHAIN=system but ${prefix}gcc is not installed (sudo apt install gcc-aarch64-linux-gnu)"
      ;;
    *) die "unknown TOOLCHAIN='$TOOLCHAIN' (use 'arm' or 'system')" ;;
  esac

  CROSS_COMPILE="$prefix"
  # ccache caches compiler output keyed on the preprocessed source, so a
  # rebuild after `make clean` (or of another branch) is mostly cache hits.
  if [[ $USE_CCACHE != 0 && $USE_CCACHE != no ]] && command -v ccache >/dev/null; then
    CC_WRAPPER="ccache "
  else
    CC_WRAPPER=""
  fi
  export CROSS_COMPILE
  if [[ $DRY_RUN != 1 ]]; then
    info "Cross compiler: $("${prefix}gcc" --version | head -n1)${CC_WRAPPER:+ (via ccache)}"
  fi
}

# run_make "<why>" <dir> [make args...]
# Runs `make -C <dir>` with the cross compiler, job count and verbosity filled
# in, and prints the full command line so you can copy-paste it.
# CC is set explicitly only to slip ccache in front of the compiler.
run_make() {
  local why=$1 dir=$2; shift 2
  local args=(make -C "$dir" -j"$JOBS" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE")
  [[ -n $CC_WRAPPER ]] && args+=(CC="${CC_WRAPPER}${CROSS_COMPILE}gcc")
  [[ $VERBOSE == 1 ]] && args+=(V=1)
  run "$why" "${args[@]}" "$@"
}

# Load configuration: optional user overrides first, then the defaults.
load_config() {
  # shellcheck source=/dev/null
  [[ -f $TOP_DIR/config/local.conf ]] && source "$TOP_DIR/config/local.conf"
  # shellcheck source=../../config/imx8mp-var-dart.conf
  source "$TOP_DIR/config/imx8mp-var-dart.conf"
  set_paths
}
