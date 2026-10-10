# Dead and unreachable upstreams

Packages whose official upstream source cannot be probed, or no longer exists at
all. Recorded so that an **unverifiable** package is never mistaken for a
**verified** one, and so that a future sweep does not raise a package as
"behind" when there is nothing left to be behind of.

## Why this file and not `packages.toml`

`packages.toml` maps **overlay** packages, and every record there is a promise
that some endpoint answers — `url` plus a working `parser`. That promise cannot
be kept for anything listed here, for one of two reasons:

- **There is no reachable endpoint.** Sections A and B. Authoring a record whose
  fetch is guaranteed to fail would break that file's own contract, and
  `enabled = false` is for a record that *once* worked, not for one that never
  can. None of those packages is a `bentoo` package either — all are installed
  from `::gentoo`, so the overlay has no record to disable and no maintenance
  duty over them.
- **There is no upstream at all.** Section C, added 2026-08-16. These *are*
  `bentoo` packages, which is exactly why they need saying: a `bentoo` package
  with no record looks identical to one nobody has got around to yet. Their
  versions are assigned by the packager, not published by anyone, so there is
  nothing to compare against and no probe to write.

So the register lives here: a plain tracked file, next to the thing it
complements, visible to a fresh clone and to a second maintainer.

Its sibling `not-packageable.md` records the opposite failure: an upstream that
probes perfectly well, but whose artifact cannot be turned into an ebuild.

## A. Unreachable — the current upstream version cannot be confirmed

The package may or may not be behind. Nobody can tell, and that is the point:
these must **not** be counted as up to date.

| Package | Installed | Source | Why it cannot be probed |
|---|---|---|---|
| `app-dicts/aspell-pt` | `20251001` | `natura.di.uminho.pt` | DNS resolves, TCP 80/443 never answers (timeout). No alternative source found. |
| `app-dicts/myspell-pt` | `20120420` | `darkstar.ist.utl.pt` | No DNS record. The fallback, `natura.di.uminho.pt`, is the host above. Upstream files carry no version anyway. |
| `net-print/epson-inkjet-printer-escpr` | `1.8.8` | `download.ebz.epson.net` | HTTP 403 to every request — an Akamai IP-level block, browser User-Agent included. Debian's own watch file declares upstream untrackable; sid is also on 1.8.8. |

## B. Dead but complete — the installed version is the last ever published

Upstream is gone and will publish nothing further. These are **not** bump
candidates and must never be raised as such.

| Package | Installed | Source | Evidence that it is the last |
|---|---|---|---|
| `app-cdr/cdrtools` | `3.02_alpha09` | SourceForge `cdrtools` | Last file in `/alpha` and `/ALPHA`; a10 and a11 are 404. Jörg Schilling died in 2021 and the project stopped with him. |
| `x11-misc/wmctrl` | `1.07` | `github.com/Conservatory/wmctrl` | Upstream's last release was January 2005. The repo is only the Conservatory's archive copy — no tags, last push 2018-09-10. |
| `app-containers/docker-swarm` | `1.2.9` | `github.com/docker/classicswarm` | Redirects to `docker-archive/classicswarm`, `archived=true`, last push 2020-06-11. Its newest release is `v1.2.9` (2018-06-05) — the installed version. Succeeded by `docker/swarmkit`. |
| `app-dicts/myspell-nn` | `2.0.10` | `alioth.debian.org` + SF `spell-norwegian` | alioth.debian.org was retired and no longer resolves; the SourceForge project returns 404; freshmeat is shut down. |
| `sys-firmware/sgabios` | `0.1_pre10` | `gitlab.com/qemu-project/sgabios` | **No confirmable last version.** code.google.com is extinct; the QEMU repo has **zero tags** (GitLab tags API returns an empty array), HEAD `72f39d4` from 2018-07-15. The ebuild pins commit `23d4749` from 2010. |
| `app-dicts/myspell-mi` | `20190630` | `github.com/scardracs/gentoo-packages` | **No confirmable last version.** The source repo was deleted (API: `Not Found`), the distfile is absent from the Gentoo mirrors, and there is no upstream feed left. |

## C. No upstream by construction — nothing to probe, by design

These are `bentoo` packages whose version nobody publishes. They are listed so
that a package with no `packages.toml` record is never mistaken for one that was
overlooked: every ebuild in this overlay is now either in `packages.toml` or in
this file.

| Package | Version | Why there is nothing to probe |
|---|---|---|
| `acct-user/lemonade` | `0` | Account package. `acct-user`/`acct-group` ebuilds declare a system user; the version is an ordinal the packager picks, and upstream ships no such concept. Bumps only when the UID/GID or the account's shape changes. |
| `acct-group/lemonade` | `0` | As above. |
| `acct-user/ntpd-rs` | `0` | As above. |
| `acct-group/ntpd-rs` | `0` | As above. |
| `acct-user/ntpd-rs-observe` | `0` | As above. |
| `acct-group/ntpd-rs-observe` | `0` | As above. |
| `app-eselect/eselect-nodejs` | `2-r1` | Written for this overlay (story 005) to arbitrate the `net-libs/nodejs` slots. `HOMEPAGE` is Gentoo's "no homepage" placeholder because there is genuinely none: bentoo is the upstream. It moves when the slot contract does, which `check-slot-naming-contract.sh` asserts. |
| `sec-keys/openpgp-keys-kamilaszewczyk` | `20260910` | OpenPGP key package for the current GNU Automake release manager, needed because 1.19 is the first tarball NOT signed by Karl Berry. `SRC_URI` is a keyserver lookup by fingerprint, which returns the key's *current* state and publishes no version at all: the `PV` is the date the packager snapshotted it. Bumps when the key gains a signing subkey or the old one expires, which only a failing `verify-sig` will tell you. |
| `media-video/ffmpeg-chromium` | `155` | **Deliberately unrecorded, not overlooked.** The SLOT is a Chromium major, and the one that matters is whatever bentoo's `www-client/chromium` (USE="bindist ffmpeg-chromium") depends on -- not the newest ffmpeg. Its "version" is derived, not published: chromium/src's `DEPS` at the chromium tag gives `ffmpeg_revision`, and the tarball is a `git archive` of that commit hosted on distfiles.obentoo.org (the ebuild header has the command). Bump it together with chromium's major, and drop each SLOT once `::gentoo` ships it. SLOT 153 left on 2026-10-10: it served only `www-client/opera`, and `::gentoo` now ships both opera-137 and ffmpeg-chromium:153. |
| `sys-libs/binutils-libs` | `2.47` | **Deliberately unrecorded, not overlooked.** Upstream is probeable — it is the same GNU release directory `sys-devel/binutils` tracks. It has no record of its own precisely so automation cannot move it independently: the two must be bumped together against bentoo's own patchset, and a record here would invite exactly the drift it is meant to prevent. See the `sys-devel/binutils` comment in `packages.toml`. |

The account packages are the reason this section is a table rather than a
sentence. Six of them look like an omission at a glance, and the temptation on
each sweep is to "fix" it by writing six records against endpoints that do not
exist.

## How to re-verify

Nothing here is taken on trust — every line above was re-probed on **2026-08-03**
and each claim is reproducible:

```bash
# A: the four dead hosts. DNS state and HTTP status, separately —
# a host can resolve and still refuse every connection.
for h in natura.di.uminho.pt darkstar.ist.utl.pt \
         download.ebz.epson.net alioth.debian.org; do
  printf '%-28s dns=' "$h"
  getent hosts "$h" >/dev/null 2>&1 && printf 'OK  ' || printf 'NXDOMAIN  '
  curl -sS -m 15 -o /dev/null -w 'http=%{http_code}\n' "https://$h/"
done
# observed: natura 000 (timeout) · darkstar NXDOMAIN
#           epson 403 (Akamai) · alioth NXDOMAIN

# B: the archived repositories. -L matters — classicswarm moved.
curl -sSL -H 'User-Agent: bentoo-autoupdate' \
  https://api.github.com/repos/docker/classicswarm \
  | jq -r '"\(.full_name) archived=\(.archived) pushed=\(.pushed_at)"'

# sgabios: an empty array is the finding, not an error.
curl -sS 'https://gitlab.com/api/v4/projects/qemu-project%2Fsgabios/repository/tags' \
  | jq 'length'
```

**Beware the inverted User-Agent** (the same trap `packages.toml` documents):
SourceForge answers 403 and `gitlab.freedesktop.org` serves an Anubis challenge
when the UA looks like a *browser*; a CLI UA passes. Anubis replies **HTTP 200**
with an HTML body, so a status code alone never proves an artifact is real.

---

Source: story 006 (full-system upstream sweep, 2026-08-01), requirements R3.1
and R3.3. The per-package sweep evidence lives in that story's `sweep-data.tsv`
and `sweep-report.md`.
