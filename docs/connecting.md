<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Connecting

Make an API key under Settings > Management Access > API Keys, or on the
server:

```sh
unraid-api apikey --create --name automation --roles VIEWER
```

`VIEWER` reads everything. Starting containers, virtual machines or the
array needs `ADMIN`, or a key with permissions for those resources.

```jennifer
def c as unraid.Client init unraid.client("tower.local");
$c = unraid.withApiKey($c, strings.trim(fs.readString("/run/secrets/unraid")));
$c = unraid.withCaCert($c, fs.readBytes("tower.pem"));
```

`client` takes a host (`tower.local` becomes
`https://tower.local/graphql`), `host:port`, or a full URL. An address with
credentials, a query or a fragment is refused.

## Plain HTTP

A request carrying the API key goes over `https://`, or over `http://` to
this machine (`localhost`, `127.0.0.1`, `[::1]`). Plain `http://` to any
other host throws an `UnraidError` before it connects. Many home servers
answer only on HTTP; `withPlainHttp` allows it:

```jennifer
def c as unraid.Client init unraid.withPlainHttp(unraid.client("http://tower.lan"));
$c = unraid.withApiKey($c, $key);
```

**The API key then travels unencrypted**: anyone on the network path can
read it and use it with the key's roles. Use `withPlainHttp` on a trusted
LAN only, with a `VIEWER` key where reading is enough, and prefer HTTPS
with `withCaCert`. `startArray` refuses an encryption passphrase over
`http://` even then.

Unraid uses a self-signed certificate until one is set up. Trust it with
`withCaCert` (export it from the browser, or copy
`/boot/config/ssl/certs/` from the server); `withInsecure` turns checking
off.

| Setting | Default |
|---|---|
| `withTimeout(c, ms)` | 30 s idle timeout per request |
| `withRetries(c, n)` | no retries; queries only |
| `withPollInterval(c, ms)` | 1 s between `waitVm` checks |
| `withPlainHttp(c)` | the key over `http://` only to loopback |

## Any query

`query` sends a document and returns the reply's `data`, for anything the
typed functions leave out. The schema is browsable in the server's GraphQL
sandbox (Settings > Management Access, Developer Sandbox).

```jennifer
def vars as json.Value init json.set(json.map(), "/id", $id);
def d as json.Value init unraid.query($c, 'query($id: PrefixedID!) { docker { container(id: $id) { labels } } }', $vars);
```

GraphQL braces need a raw `'...'` string, or `\{` in a `"..."` one.
