<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Administration

## API keys

`apiKeys` lists the keys without their secrets. `createApiKey` returns the
new key's secret in `key`, the only time it is shown:

```jennifer
def k as unraid.ApiKey init unraid.createApiKey($c, "grafana", "dashboards", ["VIEWER"]);
fs.writeString("grafana.key", $k.key);
```

Roles are `ADMIN` (anything), `VIEWER` (read everything), `CONNECT` and
`GUEST` (`ROLES`). `deleteApiKey` deletes one; clients using it are refused
from then on.

## Plugins, flash and rclone

`plugins` lists the installed plugins, `flash` the USB device Unraid boots
from. `backupFlash(c, remoteName, sourcePath, destinationPath)` copies the
flash device to an rclone remote (`rcloneRemotes`, `createRcloneRemote`,
`deleteRcloneRemote`); the copy runs on the server and the result names its
job.

`createRcloneRemote` takes the backend's settings as a JSON object of rclone's
option names:

```jennifer
def p as json.Value init json.map({"provider": "Backblaze", "access_key_id": $id, "secret_access_key": $secret});
unraid.createRcloneRemote($c, "b2", "s3", $p);
```

## Identity

`setServerIdentity(c, name, comment)` renames the server.
