<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# @deckyard/unraid

A client for the [Unraid API](https://docs.unraid.net/API/), the GraphQL API
Unraid 7.2 and newer serve at `/graphql` (older releases with the Unraid
Connect plugin). `query` sends any document; typed functions cover the
system, the array and its disks, shares, parity checks, Docker containers,
virtual machines, notifications, logs and API keys.

The API manages what exists: it cannot create containers or virtual
machines (Unraid's web UI does that from templates) and does not move
files (use SMB or NFS).

## Conventions

Snippets assume this import and a client:

```jennifer
import "@deckyard/unraid/" as unraid;

def c as unraid.Client init unraid.withApiKey(unraid.client("tower.local"), $key);
io.printf("%s\n", unraid.version($c).unraid);
```

A `Client` is a value: the `with*` functions return a changed copy. An id
is one the API returned (`Container.id`, `Vm.id`); Unraid prefixes them with
the server's id (`abc:`) and accepts them with or without it.

Sizes follow the API: array disks and shares in kilobytes (`sizeKb`),
physical disks, containers and memory in bytes. Times are ISO 8601 strings
in UTC.

## Errors

Every failure is an `unraid.UnraidError` (kind `"unraid"`), with a message
that starts with `unraid:` and names the operation. Its `status` field holds
the HTTP status of a failed request and `codes` the GraphQL error codes, so
`lists.contains($e.codes, "FORBIDDEN")` tells a missing role apart without
reading the message. A reply over its size cap is `Error{kind: "limit"}`.
The failures:

- a GraphQL error, with the server's message and code:
  `unraid: startContainer "abc:9f2": Forbidden resource [FORBIDDEN]`. A key
  without the role for an operation gets `FORBIDDEN`; no key or a wrong one,
  `UNAUTHENTICATED`.
- an HTTP failure: `unraid: online: HTTP 502: ...`.
- a network failure or timeout, with the `http` module's message.
- a bad argument, before anything is sent: an address with credentials, a
  query or a fragment, an unknown role, importance or VM state, an empty id,
  a negative offset or a limit below 1, a passphrase that would go over
  `http://`.

The API key never appears in a message.

```jennifer
try {
    unraid.startVm($c, unraid.vmByName($c, "win11").id);
} catch (e) {
    io.printf("%s\n", $e.message);
}
```

Mutations are never retried. `withRetries` retries only queries answered 429
or 5xx.

## Requirements

Jennifer 0.26.0 or newer, default `jennifer` binary: the deck needs the
`net` capability, which `jennifer-tiny` lacks. The server needs Unraid 7.2
or newer, or the Unraid Connect plugin.
