# needs_fake.sh — a sourced lib that drives the fake machine (slice H3 ships
# drivers/fake.sh; until then this stands in). Any gate sourcing it NEEDS THE
# DRIVER, which the tier classifier sees transitively.
fake_frames() {  # fake_frames <n> — placeholder until drivers/fake.sh lands
    FAKE_BIN="${FAKE_BIN:-python3 fakesys/fakesys.py}"
    echo "would run: $FAKE_BIN --frames $1"
}
