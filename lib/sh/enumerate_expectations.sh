# enumerate_expectations.sh — shared expectation-KIND enumeration. Source it.
#
# WHY IT EXISTS (lineage 14z-90, GitHub #17). An audit evaluated
# `"$EXPECT"/*.masked` and said nothing about anything else in the
# directory. `.pending` marks a replay with NO ratified class in any
# expectation set — exactly the state the audit existed to detect — so two
# dropped replays put its blind spot precisely over the one open regression.
#
# It REPORTS, it does not INCLUDE. A `.pending` file is prose, not a
# `<class> <baseset> <args>` line, so there is nothing to compare against.
# A new expectation KIND is registered HERE, and nowhere else.
#
# enumerate_expectations <expect-dir> <consumer-root> [<replays-dir>]
#   prints one `<name>|<kind>|<disposition>` line per expectation whose stem
#   is a real replay (<consumer-root>/<replays-dir>/<stem>.rpl; the dir
#   defaults to $BBH_REPLAYS_DIR, then tests/replays), and returns non-zero
#   if any is pending or of an unknown kind.
enumerate_expectations() {
    _ee_dir="$1"; _ee_repo="$2"; _ee_rpl="${3:-${BBH_REPLAYS_DIR:-tests/replays}}"; _ee_bad=0
    for _ee_f in "$_ee_dir"/*; do
        [ -f "$_ee_f" ] || continue
        _ee_b="$(basename "$_ee_f")"
        _ee_stem="${_ee_b%.*}"; _ee_ext="${_ee_b##*.}"
        [ -f "$_ee_repo/$_ee_rpl/$_ee_stem.rpl" ] || continue
        case "$_ee_ext" in
            masked)  echo "$_ee_stem|masked|EVAL" ;;
            skip)    echo "$_ee_stem|skip|SKIP" ;;
            # self-frozen to ONE image; another image differs by construction,
            # so these are never a reference-comparison leg.
            sha1)    echo "$_ee_stem|sha1|N/A" ;;
            # the frozen first-divergence constant against a FULL base log
            # (H3: the lineage's copy had no case for it — it carried zero
            # live .diverge files and would have reported one UNKNOWN-KIND)
            diverge) echo "$_ee_stem|diverge|EVAL" ;;
            pending) echo "$_ee_stem|pending|NOT-EVALUATED"; _ee_bad=1 ;;
            *)       echo "$_ee_stem|$_ee_ext|UNKNOWN-KIND"; _ee_bad=1 ;;
        esac
    done
    return "$_ee_bad"
}
