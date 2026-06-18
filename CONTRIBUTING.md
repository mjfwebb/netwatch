# Contributing

netwatch is a single bash script (`netwatch`) plus an installer and tests. Bug
reports, fixes, and tweaks are welcome.

## Dev setup

There is nothing to build. Clone, edit `netwatch`, and run it straight from the
working tree:

```bash
./netwatch 1
```

The installed copy under `~/.local/bin` is a snapshot; re-run
`install -Dm755 netwatch ~/.local/bin/netwatch` to update it, or `netwatch
update` once it is installed (see the README).

Tools needed:

| Tool | Used for |
|------|----------|
| `bash` | the script itself |
| `ss` (`iproute2`) | live network attribution |
| [`bats`](https://github.com/bats-core/bats-core) | running the tests |
| [`shellcheck`](https://www.shellcheck.net/) | linting |

On Debian/Ubuntu: `sudo apt install bats shellcheck iproute2`.

## Tests

```bash
bats tests
```

The suite lives in `tests/netwatch.bats`. The script returns early when sourced
(the guard sits just above the `trap`/header section), so the tests source it
and call its functions directly. This puts a constraint on new code: above the
guard, only definitions and read-only discovery; anything that prints or loops
goes below it.

The tests cover the pure logic — the rate formatting, trend arrows, the
auto-scaled sparkline, the rate colouring, the `/proc/net/dev` parse, and the
two attribution paths (the per-socket byte diff and the connection-count
fallback), exercised by feeding the parsers captured `ss` output. The live loop
that reads `/proc` and shells out to `ss` is exercised by hand on the machine
rather than in CI. Add a test for new pure logic where you can — factoring a
parser so it reads from stdin (as `parse_ss_snapshot`, `diff_ss_bytes`, and
`parse_ss_culprit` do) makes it testable without live sockets.

## Linting

```bash
shellcheck netwatch install.sh
```

The script is shellcheck-clean and CI enforces that. If shellcheck flags
something intentional, add a `# shellcheck disable=SCxxxx` directive on the line
above it with a short reason. Don't add global ignore lists.

## CI

`.github/workflows/ci.yml` runs bats and shellcheck on every push to `main` and
on every pull request. Both jobs must pass.

## Style

Match the existing code:

- bash, `printf` over `echo`.
- Comments explain why (the byte-vs-connection attribution choice, counter-wrap
  clamping, the QUIC/UDP fallback), not what the next line does.
- Missing sensors or commands (no `ss`, an unreadable `/proc/net/dev`) must
  reduce functionality gracefully, never crash.

## Pull requests

- Keep PRs focused; separate refactors from behavior changes.
- Update the README when flags, env vars, or output change.
- **Don't touch the `VERSION=` line in a feature or fix PR.** It is bumped once
  per release in its own commit on `main` (see Releases). Two open PRs that both
  edit it would otherwise conflict on the version, and merge order would
  silently decide the number.

## Releases

The version lives in one place: the `VERSION=` line in `netwatch` (read, not
executed, by `install.sh` to report what an update did). It is owned by `main`,
not by PRs, so that parallel PRs never contend over the number. CI enforces this
from both sides:

- The `no-version-change` job fails any PR whose diff touches the `VERSION=`
  line.
- The `release` job runs on every push to `main` (after tests and lint pass).
  When `netwatch` changed since the last tag, it cuts a release.

Nobody edits the `VERSION=` line by hand. The `release` job computes the next
number from the last tag and the bump level, writes it, commits, and tags
`vX.Y.Z`. The bump level comes from a label on the PR, and every PR must carry
exactly one (the `bump-label` check fails and comments otherwise):

| PR label | Effect | Use for |
|----------|--------|---------|
| `bump:patch` | patch release | bug fixes, internal changes |
| `bump:minor` | minor release | new user-facing behavior |
| `bump:major` | major release | breaking changes |
| `bump:none` | no release | docs, CI, comments — nothing users run |

`major` wins over `minor` over `patch` if several are somehow present. The
`bump-label` check re-runs when you add or change the label, so a red check goes
green once you pick one.
