<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Design

## Scope

`@deckyard/unraid` is a client for the Unraid API, the GraphQL API that
Unraid 7.2 and newer serve at `/graphql` (older releases with the Unraid
Connect plugin): system information and metrics, services, UPS, logs, the
array, disks, shares and parity checks, Docker containers, virtual machines,
notifications, API keys, plugins, flash backup and rclone remotes. `query`
sends any document.

Not in scope:

- **Live updates.** GraphQL subscriptions over `graphql-ws` wait until the
  subprotocol is confirmed on a server; `websocket.connectOptions` can
  already offer it.
- **The older web UI and SSH.** The deck uses only the documented API; no
  scraping, no `exec`.
- **`jennifer-tiny`.** It has no `net` capability.

## Decisions

- **GraphQL through the bundled module.** The deck builds on the
  interpreter's `graphql` module, which already gets the GraphQL convention
  right (errors in a 200 reply are failures). A fresh `graphql.Client` is
  built per request from the deck's `Client` value (`x-api-key` header, CA
  certificate, insecure flag, timeout, retries).
- **Documents as constants.** Each typed function sends a literal document
  built from per-type field selections (`DISK_FIELDS`, `ARRAY_FIELDS`,
  `CONTAINER_FIELDS`, `NOTIFICATION_FIELDS`, ...), with variables passed
  separately, never spliced into the document.
- **Addresses.** `client` turns a bare host into `https://<host>/graphql` and
  adds `/graphql` to a URL without a path. It refuses whitespace, `?` and
  `#`, schemes other than http and https, and credentials in the URL.
- **Tolerant number reading.** BigInt and capacity fields may arrive as
  numbers or numeric strings; the readers accept both and treat a value with
  more than 18 digits, or beyond about 9e18, as missing rather than wrapping.
- **Ids with or without the server prefix.** Unraid prefixes ids with
  `<server>:` and accepts them either way; lookups compare the bare id.
  Container names are shown without Docker's leading `/` and matched with or
  without it.
- **Allow-lists checked client-side.** `ROLES`, `IMPORTANCE` and `VM_STATES`
  are exported and checked before a request; ids must be non-empty and free
  of control characters.
- **VM actions return once accepted.** A VM mutation answers a bool, and the
  deck fails when it is false. libvirt runs the action afterwards, so
  `waitVm` polls for the wanted state. Its `timeoutMs` is a hard deadline: 0
  fails after the first check.
- **Duplicate-free notifications.** `notifyOnce` uses the server's
  `notifyIfUnique`, so a periodic check does not pile up identical unread
  notifications.
- **Retries for queries only.** Retries are delegated to the `graphql`
  module with a 500 ms backoff, and it retries only queries: a mutation may
  already have taken effect.
- **One module.** All areas share the transport and readers, so the deck is
  a single `src/unraid.j`.

## Errors

- Every error of kind `"unraid"` (`ERROR_KIND`) is an `UnraidError`:
  `status` is the HTTP status of a failed GraphQL request, `codes` each
  GraphQL error's `extensions.code` (`UNAUTHENTICATED`, `FORBIDDEN`, ...).
  Both are empty for the deck's own refusals. The message is
  `unraid: <operation>: <what went wrong>`.
- A reply over its size cap stays kind `"limit"`.
- A transport failure (refused, reset, unreachable, DNS, TLS, a close
  before any reply) is a `net.NetError`, kind `"net"`, passed on unchanged
  so its `reason`, `sent` and `replied` stay readable; its message names
  only the host and port.
- Any other failure from the `graphql` module, such as a timeout, is
  rewrapped as an `UnraidError`, with `status` and `codes` copied from a
  `graphql` error.

## Security and limits

- HTTPS by default. A request carrying the API key to an `http://` URL
  throws before it connects unless the host is this machine (`LOOPBACK`:
  `localhost`, `127.0.0.1`, `[::1]`; any other text before the port or
  path, userinfo included, counts as another host) or `withPlainHttp`
  allows it, as in the `github` and `gitlab` decks. The check runs at every request, because
  `Client.url` is a public field, and the order of the builders does not
  matter. Home servers often serve only HTTP, hence the opt-in; with it the
  key travels unencrypted, so it is for a trusted LAN only. The opt-in
  also sets the `graphql` client's `allowInsecureHttp` where the
  interpreter has it (0.27.0; skipped on a `"runtime"` error before). `startArray`
  refuses an encryption passphrase over `http://` even then.
- `withCaCert` trusts a self-signed certificate; `withInsecure` turns
  verification off.
- `withApiKey` accepts only `[A-Za-z0-9_-]` and never echoes the key in its
  error. The key travels in the `x-api-key` header.
- Caller and server strings are cut and stripped of non-printable characters
  before they appear in a message (60 characters, 300 for a server message).
- Each request has a timeout (`withTimeout`); `waitVm` has a hard deadline.

## Testing and validation

- `src/unraid_test.j` (25 tests) is a white-box overlay against a loopback
  fake GraphQL server built on `httpd`: one canned reply per request, with
  each request's document, variables, API key and `Accept` header recorded.
  Assertions are mostly on the documents and variables sent.
- The fake's wait is bounded: a test that gives more replies than the client
  requests fails after 5 s instead of hanging, and a test covers that.
- One test reads the `graphql.Client` internals to check the settings, so it
  breaks if the module's struct layout changes.
- `examples/status.j` needs a server and an API key, so CI only parses it.

## Known limitations and open questions

- No subscriptions (see Scope).
- `vmByName` and `containerByName` return the first match rather than failing
  on duplicate names.
- The deck strips the `graphql` module's message prefix by text; a change of
  that prefix would show up in messages, not in kinds or fields.

## Dependencies on the interpreter

- Floor `jennifer >=0.26.0`: the first release whose `graphql` module has
  `withRetries`, `withTimeout` and `withBackoff` (the module itself is
  M22.7). The default binary only.
- `graphql.GraphqlError` with `status` and `codes`, and thrown structs
  classified by kind (`jennifer` `6abf345`, the error-struct work of M28.51
  to M28.57); transport failures as `net.NetError` (M28.65).
- The tests use `httpd`, `task.waitTimeout` and `task.discard`.
