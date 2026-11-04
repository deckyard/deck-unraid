# @deckyard/unraid

[![test](https://github.com/deckyard/deck-unraid/actions/workflows/test.yml/badge.svg)](https://github.com/deckyard/deck-unraid/actions/workflows/test.yml)
[![Documentation](https://img.shields.io/badge/docs-github%20pages-blue)](https://deckyard.github.io/deck-unraid/)
[![release](https://img.shields.io/github/v/release/deckyard/deck-unraid)](https://github.com/deckyard/deck-unraid/releases/latest)

A [Jennifer](https://jennifer-lang.dev/) client for the
[Unraid API](https://docs.unraid.net/API/), the GraphQL API of Unraid 7.2 and
newer: system and metrics, the array, disks, shares and parity checks, Docker
containers, virtual machines, notifications, logs and API keys.

**[Documentation](https://deckyard.github.io/deck-unraid/)**

## Install

```sh
jvc add @deckyard/unraid
```

This vendors the deck to `vendor/<scope>/unraid/`. Without `jvc`, unpack the
`src/` subtree of a release archive (`<scope>-unraid-<version>.tar.gz`) there.

## Usage

```jennifer
import "@deckyard/unraid/" as unraid;

def c as unraid.Client init unraid.withApiKey(unraid.client("tower.local"), $key);
for (def ct in unraid.containers($c)) {
    io.printf("%s %s\n", $ct.name, $ct.state);
}
unraid.startVm($c, unraid.vmByName($c, "win11").id);
```

## Requirements

Jennifer 0.26.0 or newer, default `jennifer` binary (`net`; not
`jennifer-tiny`). An Unraid server running 7.2 or newer, or the Unraid
Connect plugin, and an API key.

## Development

```sh
tools/check-all.sh                   # the full gate, as CI runs it
jennifer test src/unraid_test.j      # the test overlay
tools/check-docs.sh                  # docs against the code
tools/pack.sh dist                   # build the release archive
```

## Licence

LGPL-3.0-only, see [LICENSE](LICENSE). Copyright (C) 2026 mplx &lt;mplx@jennifer-lang.dev&gt;.

`tools/check-headers.sh` checks every source file's SPDX header against
`deck.toml`.
