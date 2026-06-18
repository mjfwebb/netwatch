# netwatch

A live terminal monitor for **network throughput** that tries to **blame
traffic spikes on the programs that caused them**. Reads only `/proc` and `ss`,
so no root is required.

Refreshing on an interval, it shows:

- **Download & upload rates** (summed across every interface except loopback),
  each with a **trend arrow** (`▲` rising, `▼` falling, `—` steady) vs the
  previous sample, and the **combined total**.
- A **sparkline** of recent total throughput (last 40 samples), **log-scaled**
  between the window's min and max so the shape is visible whatever the absolute
  speed — and so a single spike doesn't flatten the rest of the history to the
  baseline.
- A **culprit callout** whenever total throughput jumps by ≥ `NETWATCH_RISE`
  KB/s (default 500) between samples, naming the programs responsible **and the
  remote host each one is talking to**:
  `└─ ▲ +80.0 MB/s  busiest: curl → speed.hetzner.de (78.1 MB) · firefox → dns.google (612 KB)`.

Rates are **colour-coded** by how busy the link is: green below 100 KB/s, cyan
to 2 MB/s, yellow to 10 MB/s, red above.

## How it attributes spikes

Counting connections is misleading — a browser idling on 30 QUIC sockets would
always outvote the one socket doing a 1 GB download. So on a spike netwatch
takes two snapshots of `ss -tinp` a third of a second apart and diffs each TCP
socket's cumulative byte counters (`bytes_sent` / `bytes_received`, which
`ss -i` exposes), blaming programs by **bytes actually moved** in that window.

Because throughput is reported in aggregate (like temperature lags load), the
culprit is whatever has been moving bytes over the last moment. This
investigation runs **only on a spike**, so the steady-state loop stays cheap.

It also names the **remote host** each program moved the most bytes to,
reverse-resolving the busiest peer IP via `getent` (NSS, behind a 1 s timeout),
and falling back to the bare IP when there is no PTR record. This is what turns
a vague `firefox` into `firefox → r5.googlevideo.com` — the answer to "what is
it actually pulling". A browser owns the socket in its parent/network process,
not the per-tab process, so a *tab title* isn't recoverable from a socket; the
remote host is as specific as the kernel can tell you, and usually the more
useful of the two anyway.

Without root, `ss -p` still attributes the **user's own** sockets — browsers,
sync clients, `ssh`, `apt`, downloads — which is almost always what drives a
desktop's traffic. Sockets owned by other users need root to attribute.

> Note: TCP byte counters come from the kernel's `tcp_info`, so a burst carried
> over **QUIC/UDP** (much streaming, some browser traffic) has no per-socket
> counters. When no TCP bytes moved in the window, netwatch falls back to
> naming the programs holding the most live connections instead (shown as
> `name (N)` connection counts rather than byte totals).

## Install

One line, no clone needed — and re-running the same line updates an existing
install in place:

```bash
curl -fsSL https://raw.githubusercontent.com/mjfwebb/netwatch/main/install.sh | bash
```

It installs to `~/.local/bin` (override with `NETWATCH_BIN_DIR`), which must be
on your PATH. netwatch only reads `/proc` and runs `ss` (from `iproute2`, present
on essentially every Linux), so no root or udev setup is needed.

From a checkout instead:

```bash
install -Dm755 netwatch ~/.local/bin/netwatch
```

The installed copy is a snapshot; re-run either line after pulling or editing
the script to update it. Once installed, `netwatch update` does this for you,
re-running the installer in place. `NETWATCH_RAW_URL` selects a fork or branch.

## Usage

```bash
netwatch        # refresh every 2 s (default)
netwatch 5      # refresh every 5 s
netwatch 0.5    # fractional intervals are fine on bursty links
netwatch update # self-update in place
```

Press `Ctrl+C` to quit. No root required.

The spike threshold that triggers culprit attribution is configurable:

```bash
NETWATCH_RISE=2000 netwatch    # only investigate jumps of ≥ 2 MB/s
```

## How it reads things

| Value | Source |
|-------|--------|
| RX / TX bytes | `/proc/net/dev` (field 1 and field 9 per interface, loopback excluded) |
| per-second rate | counter delta ÷ interval, negatives (counter reset/wrap) clamped to 0 |
| spike culprit | two `ss -tinp` snapshots 0.3 s apart, per-socket `bytes_sent`/`bytes_received` deltas summed by program |
| remote host | reverse DNS of each program's busiest peer IP via `getent hosts` (1 s timeout, falls back to the IP) |
| fallback culprit | `ss -tunp state connected` connection counts per program (when no TCP bytes moved) |

## Contributing

Tests live in `tests/` and run with
[bats](https://github.com/bats-core/bats-core) (`bats tests`); CI also runs
`shellcheck`. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and conventions.
