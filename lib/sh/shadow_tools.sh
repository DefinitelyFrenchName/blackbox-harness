# shadow_tools.sh — a WRITABLE copy of a tool, inside a throwaway repo root.
# Sourced, not executed. Lineage: VampireSaved tests/lib/shadow_tools.sh
# (14z-94, GitHub #81 there).
#
# WHY. A verdict control proves a substitution site is live by PERTURBING
# the generator and re-running it. The lineage's controls did that by editing
# the TRACKED tool in place and restoring from a snapshot on an exit trap. An
# exit trap covers an ordinary Ctrl-C and nothing else: two of these gates in
# two terminals (or two CI workers on one checkout) restore over each other;
# SIGKILL, a crashed shell or a machine losing power leaves the generator
# perturbed — and it is the file every build runs; a legitimate edit saved
# DURING a long control suite is silently overwritten by the restore. Test
# instrumentation should not be able to damage tracked source at all, so it
# edits a copy.
#
# WHY A SHADOW ROOT AND NOT JUST A COPY OF THE FILE. A tool commonly resolves
# its repository from its own location — `Path(__file__).resolve().parent.parent`
# — to reach its inputs, and inserts its own directory on sys.path to import
# its siblings. A copy in /tmp would find neither. So the shadow is
# `<work>/shadow/<tools_dir>/<tool>` (a real copy) beside SYMLINKS to every
# other tool, under a root whose linked dirs ([project].shadow_link_dirs —
# the lineage's build/, tests/, docs/) are symlinks to the real ones.
# `parent.parent` then lands on the shadow root and every repo-relative read
# resolves through the links to the genuine files. The copy is what gets
# perturbed; the real tree is never written. (The assumption is the tool's
# — documented here, not hidden: a tool that finds its root another way
# needs its own shadow.)
#
# Configuration, by environment (a runner exports them from [project]; the
# defaults are the lineage's):
#   REPO or BBH_ROOT         the real consumer root (one is required)
#   BBH_TOOLS_DIR            the tools dir under it            (default tools)
#   BBH_SHADOW_LINK_DIRS     space-separated dirs to link      (default "build tests docs")
#
# Usage:
#   . "$BBH_HOME/lib/sh/shadow_tools.sh"
#   GEN="$(bbh_shadow_tool "$WORK" gen_patch.py)"
#   python3 "$GEN" ...            # run it
#   ... perturb "$GEN" ...        # edit it freely; nothing tracked is touched
#   bbh_shadow_restore "$WORK" gen_patch.py    # undo: re-copy the pristine tool

# bbh_shadow_tool <workdir> <tool-basename> -> prints the path of the writable copy
bbh_shadow_tool() {
    _st_work="$1"; _st_tool="$2"
    _st_repo="${REPO:-${BBH_ROOT:-}}"
    [ -n "$_st_repo" ] || { echo "bbh_shadow_tool needs REPO or BBH_ROOT set" >&2; return 2; }
    _st_tools="${BBH_TOOLS_DIR:-tools}"
    _st_root="$_st_work/shadow"
    if [ ! -d "$_st_root/$_st_tools" ]; then
        mkdir -p "$_st_root/$_st_tools"
        for _st_f in "$_st_repo/$_st_tools"/*; do
            [ -e "$_st_f" ] || continue
            ln -sf "$_st_f" "$_st_root/$_st_tools/$(basename "$_st_f")"
        done
        # Repo-relative reads resolve through these.
        for _st_d in ${BBH_SHADOW_LINK_DIRS:-build tests docs}; do
            [ -e "$_st_repo/$_st_d" ] && ln -sfn "$_st_repo/$_st_d" "$_st_root/$_st_d"
        done
    fi
    rm -f "$_st_root/$_st_tools/$_st_tool"
    cp "$_st_repo/$_st_tools/$_st_tool" "$_st_root/$_st_tools/$_st_tool"
    printf '%s\n' "$_st_root/$_st_tools/$_st_tool"
}

# bbh_shadow_restore <workdir> <tool-basename> — undo a perturbation by
# re-copying the pristine tool over the shadow. (The real file was never touched.)
bbh_shadow_restore() {
    _st_repo="${REPO:-${BBH_ROOT:?}}"
    cp "$_st_repo/${BBH_TOOLS_DIR:-tools}/$2" "$1/shadow/${BBH_TOOLS_DIR:-tools}/$2"
}
