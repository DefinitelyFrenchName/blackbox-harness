# config.sh — the sh side of the consumer config. sh has no TOML, so every
# read is one `python3 -m bbh.config` call; a runner reads a dozen keys at
# start and never again.
#
#   bbh_config_init [path]   resolve the config (arg, $BBH_CONFIG, ./bbh.toml),
#                            export BBH_CONFIG (absolute), BBH_ROOT (its dir),
#                            PYTHONPATH (the harness lib)
#   bbh_cfg <section.key> [default]
#                            print the value; a list one item per line; a
#                            missing key with no default is FATAL (exit 3):
#                            a runner never runs on an empty value silently
#
# BBH_HOME must be set by the caller (every bin/ script derives it from $0).

bbh_config_init() {
    _c="${1:-${BBH_CONFIG:-bbh.toml}}"
    if [ ! -f "$_c" ]; then
        echo "bbh: config '$_c' not found (pass --config, set BBH_CONFIG, or run from the consumer root)" >&2
        exit 2
    fi
    BBH_CONFIG="$(cd "$(dirname "$_c")" && pwd)/$(basename "$_c")"
    PYTHONPATH="$BBH_HOME/lib/py${PYTHONPATH:+:$PYTHONPATH}"
    export BBH_CONFIG PYTHONPATH
    # the consumer root is [project].root relative to the config file — so a
    # consumer config may live OUTSIDE the tree it describes (example/consumers/)
    BBH_ROOT="$(python3 -m bbh.config "$BBH_CONFIG" root)" || exit 2
    [ -d "$BBH_ROOT" ] || { echo "bbh: consumer root '$BBH_ROOT' (from [project].root) is not a directory" >&2; exit 2; }
    export BBH_ROOT
}

bbh_cfg() {
    if [ $# -ge 2 ]; then
        python3 -m bbh.config "$BBH_CONFIG" get "$1" --default "$2" || exit 3
    else
        python3 -m bbh.config "$BBH_CONFIG" get "$1" || exit 3
    fi
}
