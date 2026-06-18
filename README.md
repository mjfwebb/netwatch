# netwatch

A live terminal monitor for **network throughput** that **blames traffic spikes
on the programs that caused them**. Reads only `/proc` and `ss`, so no root is
required.

Each refresh shows:

- **Download & upload rates** (summed across every interface but loopback), each
  with a **trend arrow** (`▲` rising, `▼` falling, `—` steady) and the
  **combined total**.
- A **sparkline** of the last 40 throughput samples, **log-scaled** so the shape
  stays readable at any speed and one spike doesn't flatten the rest.
- A **culprit callout** when total throughput jumps by ≥ `NETWATCH_RISE` KB/s
  (default 500), naming the programs responsible **and the remote host each is
  talking to**:
  `└─ ▲ +80.0 MB/s  busiest: curl → speed.hetzner.de (78.1 MB) · firefox → dns.google (612 KB)`.

Rates are **colour-coded** by load: green below 100 KB/s, cyan to 2 MB/s, yellow
to 10 MB/s, red above.

## Install

One line, no clone needed, and re-running the same line updates an existing
install in place:

```bash
curl -fsSL https://raw.githubusercontent.com/mjfwebb/netwatch/main/install.sh | bash
```

It installs to `~/.local/bin` (override with `NETWATCH_BIN_DIR`), which must be
on your PATH. netwatch only reads `/proc` and runs `ss` (from `iproute2`, on
essentially every Linux), so no root or udev setup is needed.

From a checkout instead:

```bash
install -Dm755 netwatch ~/.local/bin/netwatch
```

The installed copy is a snapshot; re-run either line to update it, or just
`netwatch update`, which re-runs the installer in place. `NETWATCH_RAW_URL`
selects a fork or branch.

## Usage

```bash
netwatch        # refresh every 2 s (default)
netwatch 5      # refresh every 5 s
netwatch 0.5    # fractional intervals are fine on bursty links
netwatch update # self-update in place
```

Press `Ctrl+C` to quit. No root required.

The spike threshold for culprit attribution is configurable:

```bash
NETWATCH_RISE=2000 netwatch    # only investigate jumps of ≥ 2 MB/s
```

## How it attributes spikes

Counting connections is misleading: a browser idling on 30 QUIC sockets would
outvote the one socket doing a 1 GB download. So on a spike netwatch takes two
snapshots of `ss -tinp` a third of a second apart and diffs each TCP socket's
cumulative byte counters (`bytes_sent` / `bytes_received`), blaming programs by
**bytes actually moved** in that window. This runs **only on a spike**, so the
steady-state loop stays cheap.

It also names the **remote host** each program moved the most bytes to,
reverse-resolving the busiest peer IP via `getent` (1 s timeout) and falling
back to the bare IP when there's no PTR record. That turns a vague `firefox` into
`firefox → r5.googlevideo.com`, what it's actually pulling. A browser owns the
socket in its network process, not the per-tab one, so a *tab title* isn't
recoverable; the remote host is as specific as the kernel can tell you, and
usually the more useful answer anyway.

Without root, `ss -p` still attributes the **user's own** sockets (browsers,
sync clients, `ssh`, `apt`, downloads), which is almost always what drives a
desktop's traffic. Other users' sockets need root.

> Note: TCP byte counters come from the kernel's `tcp_info`, so a burst over
> **QUIC/UDP** (much streaming, some browser traffic) has no per-socket counters.
> When no TCP bytes moved, netwatch falls back to naming the programs holding the
> most live connections (shown as `name (N)` counts rather than byte totals).

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
`shellcheck`. See [CONTRIBUTING.md](CONTRIBUTING.md) for conventions.
