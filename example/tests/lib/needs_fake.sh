# needs_fake.sh — a sourced lib that drives the fake machine through
# drivers/fake.sh. Any gate sourcing it NEEDS THE DRIVER, which the tier
# classifier sees transitively (the source line, not the gate's own text).
#
#   fake_replay <build-dir> <replay.rpl> <out.log>   one run through the contract
# $0 is the SOURCING gate (example/tests/<gate>.sh), so the harness root is two
# levels up, not three. This resolved one directory too high and only worked
# because every bin/bbh-* exports BBH_HOME into the gate's environment — it
# surfaced as the single F14 delta in the BBX extraction (their gotcha G11).
BBH_HOME="${BBH_HOME:-$(cd "$(dirname "$0")/../.." && pwd)}"
fake_replay() {
    FAKE_ROMPATH="$1" "$BBH_HOME/drivers/fake.sh" fake "$2" "$3"
}
