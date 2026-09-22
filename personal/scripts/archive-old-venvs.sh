#!/usr/bin/env bash
#
# archive-dirs.sh — find directories of given names living under an ancestor
# directory of a given name, and tar.gz them in place.
#
# Dry run by default. Nothing is written until you pass --go.
#
# Usage:
#   ./archive-dirs.sh [ROOT] [options]
#
# Options:
#   --under NAME    ancestor directory name to search within (repeatable,
#                   or comma-separated). Default: old
#   --name NAME     directory name to archive (repeatable, or comma-separated)
#                   Default: venv,.venv,env,.env,virtualenv,.git
#   --go            actually create the archives (default is dry run)
#   --delete        remove the directory after a verified archive
#   --force         overwrite an existing .tar.gz instead of skipping
#   --outdir DIR    write archives to DIR instead of beside the target
#   --gc            run 'git gc' on .git dirs before archiving (smaller output)
#   --loose         skip the sanity checks that confirm a dir is what it claims
#   -h, --help      this
#
# Examples:
#   ./archive-dirs.sh ~/code
#   ./archive-dirs.sh ~/code --name .git --under old,archive --go
#
set -euo pipefail

ROOT="."
GO=0; DELETE=0; FORCE=0; LOOSE=0; GC=0
OUTDIR=""
NAMES=(); UNDERS=()

usage() { sed -n '3,28p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

# split on commas so --name a,b works as well as --name a --name b
add_list() {
  local -n _arr="$1"; local IFS=','
  read -ra _tmp <<< "$2"
  local v; for v in "${_tmp[@]}"; do [[ -n "$v" ]] && _arr+=("$v"); done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --under)   add_list UNDERS "${2:?--under needs a value}"; shift ;;
    --name)    add_list NAMES  "${2:?--name needs a value}";  shift ;;
    --outdir)  OUTDIR="${2:?--outdir needs a path}"; shift ;;
    --go)      GO=1 ;;
    --delete)  DELETE=1 ;;
    --force)   FORCE=1 ;;
    --gc)      GC=1 ;;
    --loose)   LOOSE=1 ;;
    -h|--help) usage 0 ;;
    -*)        echo "unknown option: $1" >&2; usage 1 ;;
    *)         ROOT="$1" ;;
  esac
  shift
done

[[ ${#NAMES[@]}  -eq 0 ]] && NAMES=(venv .venv env .env virtualenv .git)
[[ ${#UNDERS[@]} -eq 0 ]] && UNDERS=(old)
[[ -d "$ROOT" ]] || { echo "not a directory: $ROOT" >&2; exit 1; }
# so a bare 'old' becomes './old' and still matches the */old/* patterns
[[ "$ROOT" != /* && "$ROOT" != ./* && "$ROOT" != "." ]] && ROOT="./$ROOT"
if [[ -n "$OUTDIR" && $GO -eq 1 ]]; then mkdir -p "$OUTDIR"; fi

# \( -path */old/* -o -path */archive/* \)
under_args=()
for u in "${UNDERS[@]}"; do
  [[ ${#under_args[@]} -gt 0 ]] && under_args+=(-o)
  under_args+=(-path "*/${u%/}/*")
done

# \( -name venv -o -name .git \)
name_args=()
for n in "${NAMES[@]}"; do
  [[ ${#name_args[@]} -gt 0 ]] && name_args+=(-o)
  name_args+=(-name "$n")
done

# Is this directory actually the thing its name says it is?
sanity_ok() {
  local d="$1" base="$2"
  [[ $LOOSE -eq 1 ]] && return 0
  case "$base" in
    .git|*.git)
      [[ -e "$d/HEAD" && -d "$d/objects" && -d "$d/refs" ]] ;;
    venv|.venv|env|.env|virtualenv|.virtualenv)
      [[ -f "$d/pyvenv.cfg" || -f "$d/bin/activate" || -f "$d/Scripts/activate" ]] ;;
    *)  return 0 ;;   # unknown name, nothing sensible to check
  esac
}

found=0; archived=0; skipped=0; failed=0

# -prune so find doesn't crawl the target's contents once it's matched
while IFS= read -r -d '' target; do
  found=$((found + 1))

  parent="$(dirname "$target")"
  base="$(basename "$target")"

  if ! sanity_ok "$target" "$base"; then
    echo "skip (failed check): $target"
    skipped=$((skipped + 1))
    continue
  fi

  dest_dir="${OUTDIR:-$parent}"
  # drop any leading dot so '.git' doesn't become a hidden '.git.tar.gz'
  arch_base="${base#.}"

  if [[ -n "$OUTDIR" ]]; then
    # flatten the path so two 'old/.git' dirs don't collide in one outdir
    tag="$(printf '%s' "${parent#./}" | tr '/' '_')"
    archive="$dest_dir/${tag}_${arch_base}.tar.gz"
  else
    archive="$dest_dir/${arch_base}.tar.gz"
  fi

  if [[ -e "$archive" && $FORCE -eq 0 ]]; then
    echo "skip (exists):       $archive"
    skipped=$((skipped + 1))
    continue
  fi

  size="$(du -sh "$target" 2>/dev/null | cut -f1)"

  if [[ $GO -eq 0 ]]; then
    echo "would archive:       $target  (${size})  ->  $archive"
    continue
  fi

  if [[ $GC -eq 1 && "$base" == *.git || $GC -eq 1 && "$base" == .git ]]; then
    if command -v git >/dev/null; then
      echo "gc:                  $target"
      git --git-dir="$target" gc --quiet 2>/dev/null || echo "  (gc failed, archiving as-is)"
      size="$(du -sh "$target" 2>/dev/null | cut -f1)"
    fi
  fi

  echo "archiving:           $target  (${size})"
  # -C parent keeps the archive relative: it unpacks as ./git-dir, not /home/you/...
  if tar -czf "$archive.part" -C "$parent" "$base" && tar -tzf "$archive.part" >/dev/null; then
    mv "$archive.part" "$archive"
    echo "  -> $archive ($(du -sh "$archive" | cut -f1))"
    archived=$((archived + 1))
    if [[ $DELETE -eq 1 ]]; then
      rm -rf -- "$target"
      echo "  removed $target"
    fi
  else
    echo "  FAILED: $target" >&2
    rm -f -- "$archive.part"
    failed=$((failed + 1))
  fi
done < <(find "$ROOT" -type d \( "${under_args[@]}" \) \( "${name_args[@]}" \) -prune -print0)

echo
echo "matched: $found  archived: $archived  skipped: $skipped  failed: $failed"
if [[ $GO -eq 0 ]]; then echo "(dry run — re-run with --go to actually do it)"; fi
exit $(( failed > 0 ? 1 : 0 ))
