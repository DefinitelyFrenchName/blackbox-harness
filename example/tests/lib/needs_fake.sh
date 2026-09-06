# needs_fake.sh — a sourced lib that drives the fake machine through
# drivers/fake.sh. Any gate sourcing it NEEDS THE DRIVER, which the tier
# classifier sees transitively (the source line, not the gate's own text).
#
#   fake_replay <build-dir> <replay.rpl> <out.log>   one run through the contract
BBH_HOME="${BBH_HOME:-$(cd "$(dirname "$0")/../../.." && pwd)}"
fake_replay() {
    FAKE_ROMPATH="$1" "$BBH_HOME/drivers/fake.sh" fake "$2" "$3"
}
