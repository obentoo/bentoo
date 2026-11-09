# bentoo

A Gentoo overlay that serves as the base of an **operating system project**.
`masters = gentoo`; ~330 packages.

## Guiding principle

**bentoo is a distribution, not a machine.** The maintainer (`lucascouts`) is
only the person who packages it — not the target audience.

Practical consequences, binding on every packaging decision:

- **Never size a package by the maintainer's hardware.** That hardware is
  irrelevant to the decision to port, to the USE flags exposed, and to the
  defaults chosen.
- **Cover third-party hardware by default, within the platform baseline
  below:** NVIDIA (every generation still found in that window, Pascal
  included), AMD (ROCm/Vulkan), Intel (SYCL/oneAPI), NPUs (XDNA2 and the like),
  and CPU-only — not just a machine with a discrete GPU.
- **Cover third-party use cases:** desktop, workstation, server, headless,
  container, edge.
- Acceleration backends ship as **optional USE flags**, never hardcoded. Nobody
  should be forced to pull in CUDA to use a package on CPU.
- **Platform baseline: `amd64` only, x86-64-v3 or newer (hardware from 2017
  onward).** `KEYWORDS="~amd64"` — no other architecture, because none can be
  tested here and a keyword is a promise that the package works there.
  Excluding pre-v3 CPUs is distribution policy, not the maintainer's hardware,
  so binaries may be built for v3 with no generic x86-64 variant. Exception:
  `::gentoo` mirrors keep upstream's `KEYWORDS`, so they stay byte-close to the
  ebuild they mirror.
- "It is not useful to me" is **not** an exclusion criterion. "Upstream
  abandoned", "does not build", "no clear license" are.

## Overlay conventions

- `thin-manifests = true` — a `Manifest` records only `DIST` entries. Ebuilds,
  patches and metadata are covered by git, not by the Manifest.
- Autoupdate is configured in `.autoupdate/packages.toml`. Every record is a
  promise that some endpoint answers: `url` plus a working `parser`.
- A package removed from the overlay becomes `enabled = false` in
  `packages.toml`; the entry is never deleted, which preserves the probe that
  was already verified.
- An upstream that cannot be probed at all gets **no** record. Those are listed
  in `.autoupdate/dead-upstreams.md`, so an unverifiable package is never
  mistaken for a verified one.
  - Exception: a **declaration-only** record — `enabled = false`, a
    `disabled_by` that says so, and a `patched` field — for a package that
    diverges from `::gentoo` and has no upstream that can be probed: no
    upstream of its own (`virtual/*`, a script living in `::gentoo`'s
    `files/`) or one listed in `dead-upstreams.md`. The `url` is `::gentoo`'s
    gitweb atom for the package, never polled while disabled.
    `bentoo overlay compare` reads a divergence as declared only from
    `patched`, never from the ebuild's `BENTOO-DIVERGENCE` tag, so without the
    record the package stays `Unknown` on every run.
- An upstream that was assessed and **rejected** goes in
  `.autoupdate/not-packageable.md`, with the evidence and the condition that
  would reopen the decision — otherwise the same investigation is redone on
  every sweep.

### Every daemon must be startable without systemd

Any package that installs a systemd unit also installs an OpenRC init script of
the **same scope** — system in `/etc/init.d`, user in `/etc/user/init.d`.

The asymmetry is deliberate: the unit is gated behind `USE=systemd`, the init
script **never** is. It costs a systemd user nothing, and it is the only way to
run the daemon for someone who does not use systemd. This follows from "cover
third-party use cases" above: a systemd-only service is the maintainer's init
system mistaken for the audience's.

## Repository layout

`metadata/layout.conf` sets `profile-formats = portage-2 profile-repo-deps
profile-bashrcs profile-set profile-license` (each token's reason is commented
there), and
`profiles/eapi` is `5` (slot deps in profile files). This changes how atoms in
`profiles/package.{mask,unmask}` must be written, in opposite directions:

- Portage stamps **every** repo-level atom with the repository being processed,
  i.e. rewrites it as `<atom>::bentoo`.
- To mask something in a **master**, qualify it explicitly:
  `net-libs/nodejs:0::gentoo`. A bare atom would only ever reach this overlay's
  own ebuilds — masks flow down the masters chain, never up.
- To unmask this overlay's own ebuild against a mask inherited from a master,
  use a **bare** atom. The inherited mask lands twice (`::gentoo` and
  `::bentoo`); only the `::bentoo` copy masks our ebuild, and only a bare atom
  cancels it.

Both entries currently in the tree carry that reasoning in their comment. Read
it before editing either file.

### Composable profiles

A system is **one preset plus optional layers**, all plain profiles of this
overlay; nothing is generated and no ebuild is touched.

- **Presets** — the 27 `profiles/default/linux/amd64/23.0/*` entries of
  `profiles.desc` (each `gentoo:<same path>` + `:features/branding`): 20 glibc
  and 7 musl (`23.0/musl/*`, merged-/usr only, no-multilib, no desktop). They
  carry every Gentoo variant on seven axes: init, multilib, desktop, hardened,
  selinux, `toolchain` (`gcc`/`llvm`) and `libc` (`glibc`/`musl`).
- **Layers** — `profiles/targets/<flavor>` (workstation, server, headless,
  container; at most one), `profiles/features/<mix-in>` (games) and
  `profiles/features/hardware/<hw>` (nvidia, nvidia-legacy, amd, intel; any
  number). A layer directory is one holding `eapi`; `features/branding` is the
  exception, inherited by every preset.
- **`profiles/catalog.toml`** — the contract (`schema = 2`) read by
  `scripts/check-profile-matrix.sh`, by `bentoo profile`
  (app-portage/bentoolkit, Go) and by `shidashi order` (Python): each preset's
  attributes, each layer's type, `base` constraints, `conflicts`, `requires`,
  `has_files` and `services`. The `parent` order is type rank, then
  declaration order. An incompatible change bumps `schema`. The NVIDIA layers
  carry `base = { libc = ["glibc"] }`: ::gentoo masks nvidia-drivers on musl.
- **`profiles/catalog-vectors.toml`** — the composition rule as conformance
  vectors (same `schema`): a selection and either its exact `parent` lines or
  the set of rules it breaks. Every consumer above runs them, so no
  implementation of the rule drifts from the others; a change to the rule
  changes a vector first.
- **`layers/<layer-id>/etc/**/<x>.d/<bentoo-...>`** — `/etc` drop-ins a layer
  installs through `bentoo profile`; regular files only, no symlink, no execute
  bit, a `bentoo-` name.

Four Portage behaviours shaped the layers, all measured, all easy to undo by
accident:

- A wildcard (`sys-boot/*`) in a profile `package.mask` is **silently
  ignored**: `targets/container` spells every atom out, so a new kernel,
  bootloader or firmware package needs a line there.
- `ACCEPT_LICENSE` in a profile's `make.defaults` **replaces** the inherited
  value (it is not incremental): a layer accepts its licence through
  `package.license` (`profile-license`), for its own packages only.
- `VIDEO_CARDS` **is** incremental: hardware layers add to it and never reset
  it with `-*`, or hybrid machines lose their other driver.
- Bare atoms in a layer's `packages` join `@profile` only with `profile-set`;
  `*atom` (branding) joins `@system`.

## Verification scripts

Each one exits `1` on a gap and names what diverged. They exist because the
failure they catch is silent — it passes `pkgcheck`, merges cleanly, and only
surfaces on a user's machine.

| Script | Asserts |
|---|---|
| `check-openrc-coverage.sh [cat[/pkg]]` | every systemd unit has an OpenRC counterpart at the same scope |
| `gentoo-parity.sh [cat[/pkg]]` | names every axis on which a package diverges from its `::gentoo` counterpart; strictly read-only, writes reports under `.epic/` |
| `check-slot-naming-contract.sh` | `net-libs/nodejs` and `app-eselect/eselect-nodejs` agree on where a slot lives |
| `check-foldingathome-image.sh <ebuild>` | properties of the installed *image*, not of the ebuild text (loader fix + `RDEPEND` reconciliation) |
| `check-edk2-dbx-freshness.sh` | `sys-firmware/edk2`'s `SBO_VER` still names the newest Secure Boot revocation list; exits `2`, not `1`, when the network is the problem |
| `go-vendor.sh [--check] <cat/pkg>` | a Go package's `*-vendor.tar.xz` on distfiles.obentoo.org still matches its `go.mod`; without `--check` it regenerates the tarball into DISTDIR and prints the R2 upload (never uploads). Needs the network; run it after autoupdate bumps one of these |
| `test-eselect-nodejs.sh` | slot ordering (`node9` vs `node10`) and directory replacement in the eselect module |
| `check-profile-matrix.sh --static\|--vectors\|--staged\|--full\|--compose <preset> [layer…]\|--self-test` | `profiles/catalog.toml` (schema 2), `profiles/catalog-vectors.toml`, the layers and their `layers/` drop-ins agree (`--static`, seconds); `--vectors` runs every conformance vector through `--compose` (~0.13 s, no Portage); every allowed layer combination resolves in an isolated root and every forbidden one is rejected (`--staged`: `--vectors`, then layers touched by the index over 6 reference presets, one musl, ~25 s per touched layer; `--full`: each of the 27 presets alone, then its layer selections, 524 resolutions: 6m24s measured on a loaded host, 3m38s idle for the 497 before the preset-alone pass); `--compose` prints the `parent` lines `bentoo profile` must also produce. Resolution needs `bwrap` and `emerge`, never root |

`check-openrc-coverage.sh`, `gentoo-parity.sh`,
`check-edk2-dbx-freshness.sh` and `check-profile-matrix.sh` also take
`--self-test`, which runs their assertions without touching the tree. The
real-tree half of `check-profile-matrix.sh`'s suite is
`bats scripts/tests/check-profile-matrix/integration/` (add
`--filter-tags '!slow'` to skip the every-layer cases).

`check-profile-matrix.sh --staged` runs from `.git/hooks/pre-commit`, but only
when the commit stages a path under `profiles/`, `layers/` or
`metadata/layout.conf`; every other commit pays nothing for it.
Run `--full` by hand after a batch of layer edits, before you push them:
the hook resolves 6 reference presets, `--full` all 27.

`check-edk2-dbx-freshness.sh` and `go-vendor.sh` are the ones that need the
network, which is why they are deliberately absent from `.git/hooks/pre-commit`:
a guard that turns red offline is a guard people learn to skip. Run the first
in upstream sweeps, the second after a bump of a vendor-tarball Go package.

`gentoo-parity.sh` is absent from the hook for a different reason, and it is
not cost — a full sweep is ~7s. It is scope. The sweep compares against
`/var/db/repos/gentoo`, which moves independently of anything being committed
here, so the most common way a new row appears is `::gentoo` bumping a package,
not an edit in this tree. A hook that fails the commit for that blames the
wrong change, and the hook is `--staged` anyway. Run it at the two moments
where the comparison actually means something:

- **after `emaint sync -r gentoo`** — the `::gentoo` half of the divergence,
  the half no commit here can produce; and
- **after a batch of bumps**, before pushing them.

Two of the sweep's sections report litter rather than divergence, and neither
fails the run. Both were emptied on 2026-09-07 and both have a floor worth
knowing:

- **orphan files** under `files/` that no ebuild names -- went 50 to 4. It will
  not reach 0: `app-office/libreoffice-l10n/files/lo_gen_langs.sh` is a
  maintainer tool, never referenced by design, and the three LibreWolf entries
  sit beside `## Disabled for` blocks that document why they are kept. A fifth,
  `sys-firmware/seabios/files/seabios/config.seabios-128k`, is unused in
  `::gentoo` too: bentoo carries seabios only for `PYTHON_COMPAT`, so its
  `files/` stays identical to `::gentoo`'s rather than diverging. It leaves
  with the package. **Treat 5 as the floor, not as a backlog.**
- **md5-cache entries with no ebuild** -- went 548 of 916 to 0. This one's
  floor IS 0, and it climbs on its own: every bump leaves the previous entry
  behind unless `egencache` is re-run for that package.

A third section reports the opposite of the orphan one and is **not** litter:
**`${FILESDIR}` references matching no file**, on the `[missing]` line. Those
die at install under EAPI 8, so the package cannot merge at all. It is at 0 and
must stay there -- `dev-util/antigravity-hub-bin` sat broken with exactly this
until 2026-09-07, and was found only because the mismatch happened to leave an
orphan behind on the other side.

Since 2026-09-07 the sweep exits `0` with all 222 lines `JUSTIFIED`. That
changes how a red reads: any `ALIGN` is divergence that *arrived*, not backlog
that was never worked down. `--self-test` (34 assertions) covers the script
itself and needs neither the tree nor the network -- except for the handful of
SLOT probes that pin an exact PVR on purpose. When one of those subjects is not
in the tree, the assertion reports **SKIP**, never FAIL: a vanished subject says
nothing about the rule. A skip is printed even on the success path and counted
apart from the passes, because it IS lost coverage.

## Working rules

- **The checkout is not what Portage reads.** Portage reads
  `/var/db/repos/bentoo`. A fix only takes effect after commit + push +
  `emaint sync -r bentoo`.
- **This host has no `sudo`.** Validate with `emerge -pv`, or run build phases
  with a `PORTAGE_TMPDIR` of your own. A "PASS" that never merged anything is a
  false pass — say so explicitly.
- **Always pass an explicit target to `pkgdev manifest`.** Without one it
  rewrites the Manifest of the entire overlay.
- **`md5-cache` for the checkout needs `egencache
  --repositories-configuration`.** `PORTAGE_CONFIGROOT` and
  `PORTAGE_REPOSITORIES` are ignored, and it will try to delete the cache under
  `/var/db/repos/bentoo`.
- **One git worktree per concurrent session.** `bentoo overlay add` with no
  paths is `git add .`, so anything sitting in the tree when it runs gets
  committed and pushed — including another session's work in progress. Explicit
  paths are not enough; this has been observed repeatedly.
