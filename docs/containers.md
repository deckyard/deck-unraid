<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Containers

```jennifer
for (def ct in unraid.containers($c)) {
    io.printf("%s %s %s\n", $ct.name, $ct.state, $ct.image);
}
def plex as unraid.Container init unraid.containerByName($c, "plex");
$plex = unraid.restartContainer($c, $plex.id);
```

`name` is the container's first name without Docker's leading `/`;
`containerByName` accepts either form. `state` is `RUNNING`, `PAUSED` or
`EXITED`.

`startContainer`, `stopContainer`, `restartContainer`, `pauseContainer`,
`unpauseContainer` and `updateContainer` return the container afterwards.
`updateContainer` pulls a newer image and recreates the container from its
template; `updateAllContainers` does that for every one with
`updateAvailable`. `removeContainer(c, id, withImage)` removes it.

The API cannot create containers: Unraid makes them from templates in the
web UI.

## Logs

`containerLogs(c, id, since, tail)` returns lines and a `cursor`. Pass the
cursor as `since` next time to get only what came after:

```jennifer
def logs as unraid.ContainerLogs init unraid.containerLogs($c, $plex.id, "", 100);
for (def line in $logs.lines) {
    io.printf("%s %s\n", $line.timestamp, $line.message);
}
def newer as unraid.ContainerLogs init unraid.containerLogs($c, $plex.id, $logs.cursor, 0);
```

## Autostart

`setAutostart` takes one `Autostart` per container, in start order, with
a delay in seconds before the next one starts:

```jennifer
unraid.setAutostart($c, [
    unraid.Autostart{id: $db.id, autoStart: true, wait: 10},
    unraid.Autostart{id: $app.id, autoStart: true, wait: 0}
]);
```
