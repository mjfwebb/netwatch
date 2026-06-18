#!/usr/bin/env bats
# Unit tests for netwatch's pure logic. The script returns early when sourced
# (the guard sits just above the trap/header section), so each test sources it
# fresh — bats isolates tests in subshells — and calls its functions directly.

setup() {
  NW="$BATS_TEST_DIRNAME/../netwatch"
}

# --- fmt_rate: bytes/s to a human string -------------------------------------

@test "fmt_rate uses B/s under 1 KiB" {
  source "$NW"
  run fmt_rate 500
  [ "$output" = "500 B/s" ]
}

@test "fmt_rate switches to KB/s, MB/s and GB/s at the right boundaries" {
  source "$NW"
  run fmt_rate 2048;       [ "$output" = "2.0 KB/s" ]
  run fmt_rate 1572864;    [ "$output" = "1.5 MB/s" ]
  run fmt_rate 2147483648; [ "$output" = "2.00 GB/s" ]
}

# --- fmt_size: cumulative bytes (no /s), for the spike callout ---------------

@test "fmt_size formats a byte count without a per-second suffix" {
  source "$NW"
  run fmt_size 524;     [ "$output" = "524 B" ]
  run fmt_size 1572864; [ "$output" = "1.5 MB" ]
}

# --- arrow: trend glyph vs the previous sample -------------------------------
# Colours are empty without a TTY, so the output is the bare glyph.

@test "arrow shows a rising glyph when current exceeds previous" {
  source "$NW"
  run arrow 70 60
  [ "$output" = "▲" ]
}

@test "arrow shows a falling glyph when current is below previous" {
  source "$NW"
  run arrow 60 70
  [ "$output" = "▼" ]
}

@test "arrow shows a steady glyph when current equals previous" {
  source "$NW"
  run arrow 65 65
  [ "$output" = "—" ]
}

@test "arrow is a blank space when there is no previous sample" {
  source "$NW"
  run arrow 65 ""
  [ "$output" = " " ]   # a single space, to hold the column's width
}

# --- sparkline: log-scale the throughput history to block glyphs -------------

@test "sparkline log-scales between the window min and max" {
  source "$NW"
  hist=(0 50 100)         # min 0 -> ▁, max 100 -> █, 50 high on the log scale
  run sparkline
  [ "$output" = "▁▇█" ]
}

@test "sparkline renders a flat (all-equal, incl. all-zero) window as ▁" {
  source "$NW"
  hist=(0 0 0)            # no range -> flat run of the lowest block
  run sparkline
  [ "$output" = "▁▁▁" ]
}

@test "sparkline shows even steps for geometric growth" {
  source "$NW"
  hist=(100 200 400 800)  # doubling reads as roughly even rises on a log scale
  run sparkline
  [ "$output" = "▁▃▆█" ]
}

# Regression: a single spike must not flatten the rest of the window to ▁ (a
# linear scale made the spike the max and collapsed every other sample, so the
# history appeared to reset the moment a spike landed).
@test "sparkline keeps ordinary traffic visible alongside a spike" {
  source "$NW"
  hist=(200 700 158 92000 12400 10000 20000)
  run sparkline
  [ "$output" = "▁▃▁█▆▆▆" ]   # the post-spike KB/s samples stay mid-height, not ▁
}

@test "sparkline emits nothing for an empty history" {
  source "$NW"
  hist=()
  run sparkline
  [ "$output" = "" ]
}

# --- rcolor: colour throughput by how busy the link is -----------------------
# Force the colour vars after sourcing (empty without a TTY) so the bucket each
# rate lands in is observable.

@test "rcolor picks the right bucket for each band" {
  source "$NW"
  G=GREEN C=CYAN Y=YELLOW R=RED
  run rcolor 1024;     [ "$output" = "GREEN" ]   # < 100 KB/s
  run rcolor 500000;   [ "$output" = "CYAN" ]    # 100 KB/s .. 2 MB/s
  run rcolor 5000000;  [ "$output" = "YELLOW" ]  # 2 .. 10 MB/s
  run rcolor 20000000; [ "$output" = "RED" ]     # > 10 MB/s
}

# --- parse_dev_totals: sum RX/TX across interfaces, skipping loopback --------

write_net_dev() {
  cat >"$BATS_TEST_TMPDIR/net_dev" <<'EOF'
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo: 6640828   51197    0    0    0     0          0         0  6640828   51197    0    0    0     0       0          0
  eth0: 1000   10    0    0    0     0          0         0   2000   20    0    0    0     0       0          0
wlan0: 3000   30    0    0    0     0          0         0   4000   40    0    0    0     0       0          0
EOF
}

@test "parse_dev_totals sums RX field 1 and TX field 9 across non-loopback ifaces" {
  write_net_dev
  source "$NW"
  run parse_dev_totals "$BATS_TEST_TMPDIR/net_dev"
  [ "$output" = "4000 6000" ]   # rx 1000+3000, tx 2000+4000; lo excluded
}

@test "parse_dev_totals splits a byte count glued to the interface name" {
  # The kernel's fixed-width format can stick a large RX count onto the name.
  printf 'h1\nh2\nwlp9s0:2742420328 2307997 0 0 0 0 0 0 341059075 576215 0 0 0 0 0 0\n' \
    >"$BATS_TEST_TMPDIR/glued"
  source "$NW"
  run parse_dev_totals "$BATS_TEST_TMPDIR/glued"
  [ "$output" = "2742420328 341059075" ]
}

# --- parse_ss_snapshot: one "key bytes name" line per TCP socket -------------

@test "parse_ss_snapshot pairs the header line with its bytes info line" {
  source "$NW"
  run parse_ss_snapshot <<'EOF'
State Recv-Q Send-Q Local Address:Port Peer Address:Port Process
ESTAB 0 0 10.0.0.1:5000 1.2.3.4:443 users:(("curl",pid=10,fd=3))
	 cubic rto:200 bytes_sent:1000 bytes_acked:1001 bytes_received:2000 segs_in:1
EOF
  [ "$output" = "10.0.0.1:5000|1.2.3.4:443 3000 curl" ]
}

@test "parse_ss_snapshot skips sockets with no attributable process" {
  # No users:(()) field (e.g. owned by another user without root) -> not emitted.
  source "$NW"
  run parse_ss_snapshot <<'EOF'
ESTAB 0 0 10.0.0.1:5000 1.2.3.4:443
	 cubic bytes_sent:1000 bytes_received:2000
EOF
  [ "$output" = "" ]
}

# --- diff_ss_bytes: rank programs by bytes moved, with each one's busiest peer

@test "diff_ss_bytes emits 'bytes name peer-ip' triples, busiest first" {
  source "$NW"
  run diff_ss_bytes <<'EOF'
10.0.0.1:5000|1.2.3.4:443 3000 curl
10.0.0.1:5001|5.6.7.8:443 1000 brave
10.0.0.1:5002|9.9.9.9:443 200 firefox
===
10.0.0.1:5000|1.2.3.4:443 52431000 curl
10.0.0.1:5001|5.6.7.8:443 1524 brave
10.0.0.1:5002|9.9.9.9:443 200 firefox
EOF
  # curl moved ~50 MB to 1.2.3.4, brave 524 B to 5.6.7.8; firefox unchanged.
  # The peer IP is the key's remote half with its :port stripped.
  [ "${lines[0]}" = "52428000 curl 1.2.3.4" ]
  [ "${lines[1]}" = "524 brave 5.6.7.8" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "diff_ss_bytes credits each program to the peer it moved the most to" {
  source "$NW"
  run diff_ss_bytes <<'EOF'
a:1|11.0.0.1:443 0 firefox
a:2|22.0.0.2:443 0 firefox
===
a:1|11.0.0.1:443 1000 firefox
a:2|22.0.0.2:443 9000 firefox
EOF
  # 10 KB total, but 22.0.0.2 carried 9 KB of it -> that's the named peer.
  [ "$output" = "10000 firefox 22.0.0.2" ]
}

@test "diff_ss_bytes emits nothing when no socket moved" {
  source "$NW"
  run diff_ss_bytes <<'EOF'
10.0.0.1:5000|1.2.3.4:443 3000 curl
===
10.0.0.1:5000|1.2.3.4:443 3000 curl
EOF
  [ "$output" = "" ]
}

# --- parse_ss_culprit: connection-count fallback -----------------------------

@test "parse_ss_culprit counts one connection per socket line, busiest first" {
  source "$NW"
  run parse_ss_culprit <<'EOF'
udp ESTAB 0 0 1.2.3.4:5 6.7.8.9:443 users:(("brave",pid=5872,fd=47))
tcp ESTAB 0 0 1.2.3.4:6 6.7.8.9:443 users:(("brave",pid=5872,fd=30))
tcp ESTAB 0 0 1.2.3.4:7 6.7.8.9:443 users:(("spotify",pid=84577,fd=22))
EOF
  [ "$output" = "brave (2) · spotify (1)" ]
}

# --- smoke: the script is syntactically sound and sources cleanly ------------

@test "script sources without error" {
  source "$NW"
}
