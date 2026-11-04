<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# unraid cheatsheet

Every export of `@deckyard/unraid`. Guides are listed in
[the introduction](index.md).

```jennifer
import "@deckyard/unraid/" as unraid;
```

Every function that sends a request throws `Error{kind: "unraid"}` when it
fails. An `id` is one the API returned, such as `Container.id`; the server
prefix (`abc:`) may be left out.

## Constants

| Constant | Value | Meaning |
|---|---|---|
| `ERROR_KIND` | `"unraid"` | the `kind` of every error the deck throws |
| `ROLES` | `["ADMIN", "CONNECT", "GUEST", "VIEWER"]` | the roles an API key can hold |
| `IMPORTANCE` | `["INFO", "WARNING", "ALERT"]` | the importance levels of a notification |
| `VM_STATES` | `["NOSTATE", "RUNNING", "IDLE", "PAUSED", "SHUTDOWN", "SHUTOFF", "CRASHED", "PMSUSPENDED"]` | the states a virtual machine reports |

## Client

| Function | Returns | Does |
|---|---|---|
| `unraid.client(address as string)` | `Client` | a client for `host`, `host:port` or a URL; a bare host gets `https://` and `/graphql` |
| `unraid.withApiKey(c as Client, key as string)` | `Client` | send `x-api-key`; letters, digits, `-` and `_` only |
| `unraid.withCaCert(c as Client, pem as bytes)` | `Client` | trust a certificate besides the system's |
| `unraid.withInsecure(c as Client)` | `Client` | accept any certificate |
| `unraid.withTimeout(c as Client, ms as int)` | `Client` | idle timeout per request; 0 for 30 s |
| `unraid.withRetries(c as Client, n as int)` | `Client` | retry a query answered 429 or 5xx; never a mutation |
| `unraid.withPollInterval(c as Client, ms as int)` | `Client` | how often `waitVm` checks |
| `unraid.query(c as Client, document as string, variables as json.Value)` | `json.Value` | any query or mutation; the reply's `data` |

## System

| Function | Returns | Does |
|---|---|---|
| `unraid.online(c as Client)` | `bool` | whether the server reports itself online |
| `unraid.version(c as Client)` | `Versions` | Unraid, API and kernel versions |
| `unraid.info(c as Client)` | `SystemInfo` | name, OS, CPU, boot time |
| `unraid.metrics(c as Client)` | `Metrics` | CPU load and memory use |
| `unraid.services(c as Client)` | `list of Service` | the services the API reports on |
| `unraid.upsDevices(c as Client)` | `list of UpsDevice` | monitored power supplies |
| `unraid.logFiles(c as Client)` | `list of LogFile` | log files under `/var/log` |
| `unraid.readLog(c as Client, path as string, lines as int, startLine as int)` | `LogChunk` | lines of a log; 0 for the defaults |

## Array, disks and shares

| Function | Returns | Does |
|---|---|---|
| `unraid.array(c as Client)` | `StorageArray` | state, capacity, disks, parity check |
| `unraid.startArray(c as Client, passphrase as string)` | `StorageArray` | start it; passphrase over https:// only, "" for none |
| `unraid.stopArray(c as Client)` | `StorageArray` | stop it |
| `unraid.mountDisk(c as Client, id as string)` | `ArrayDisk` | mount a disk |
| `unraid.unmountDisk(c as Client, id as string)` | `ArrayDisk` | unmount a disk |
| `unraid.addDiskToArray(c as Client, id as string, slot as int)` | `StorageArray` | add a disk; slot -1 lets Unraid choose |
| `unraid.clearDiskStats(c as Client, id as string)` | | reset a disk's counters |
| `unraid.disks(c as Client)` | `list of Disk` | every physical disk |
| `unraid.assignableDisks(c as Client)` | `list of Disk` | disks in no array or pool |
| `unraid.disk(c as Client, id as string)` | `Disk` | one physical disk |
| `unraid.shares(c as Client)` | `list of Share` | the user shares |
| `unraid.parityStatus(c as Client)` | `ParityCheck` | the current or last check |
| `unraid.parityHistory(c as Client)` | `list of ParityCheck` | past checks |
| `unraid.startParityCheck(c as Client, correct as bool)` | | start one; `correct` writes fixes |
| `unraid.pauseParityCheck(c as Client)` | | pause it |
| `unraid.resumeParityCheck(c as Client)` | | resume it |
| `unraid.cancelParityCheck(c as Client)` | | cancel it |

## Containers

| Function | Returns | Does |
|---|---|---|
| `unraid.containers(c as Client)` | `list of Container` | every Docker container |
| `unraid.container(c as Client, id as string)` | `Container` | one container |
| `unraid.containerByName(c as Client, name as string)` | `Container` | by name, with or without the leading `/` |
| `unraid.startContainer(c as Client, id as string)` | `Container` | start it |
| `unraid.stopContainer(c as Client, id as string)` | `Container` | stop it |
| `unraid.restartContainer(c as Client, id as string)` | `Container` | restart it |
| `unraid.pauseContainer(c as Client, id as string)` | `Container` | pause it |
| `unraid.unpauseContainer(c as Client, id as string)` | `Container` | resume it |
| `unraid.updateContainer(c as Client, id as string)` | `Container` | pull a newer image and recreate it |
| `unraid.updateAllContainers(c as Client)` | `list of Container` | update every one with a newer image |
| `unraid.removeContainer(c as Client, id as string, withImage as bool)` | | remove it, and its image if asked |
| `unraid.containerLogs(c as Client, id as string, since as string, tail as int)` | `ContainerLogs` | log lines; `since` "" and `tail` 0 for all |
| `unraid.setAutostart(c as Client, entries as list of Autostart)` | | start order and delays |

## Virtual machines

| Function | Returns | Does |
|---|---|---|
| `unraid.vms(c as Client)` | `list of Vm` | every virtual machine |
| `unraid.vm(c as Client, id as string)` | `Vm` | one machine |
| `unraid.vmByName(c as Client, name as string)` | `Vm` | by name |
| `unraid.startVm(c as Client, id as string)` | | start it |
| `unraid.stopVm(c as Client, id as string)` | | ask it to shut down (ACPI) |
| `unraid.forceStopVm(c as Client, id as string)` | | power it off at once |
| `unraid.pauseVm(c as Client, id as string)` | | pause it |
| `unraid.resumeVm(c as Client, id as string)` | | resume it |
| `unraid.rebootVm(c as Client, id as string)` | | ask it to reboot |
| `unraid.resetVm(c as Client, id as string)` | | reset it |
| `unraid.waitVm(c as Client, id as string, state as string, timeoutMs as int)` | `Vm` | wait for a state from `VM_STATES` |

## Notifications

| Function | Returns | Does |
|---|---|---|
| `unraid.notifications(c as Client, archived as bool, importance as string, offset as int, limit as int)` | `list of Notification` | a page; `importance` "" for all |
| `unraid.notificationOverview(c as Client)` | `NotificationOverview` | counts, unread and archived |
| `unraid.notify(c as Client, title as string, subject as string, description as string, importance as string, link as string)` | `Notification` | raise one |
| `unraid.notifyOnce(c as Client, title as string, subject as string, description as string, importance as string, link as string)` | `bool` | raise one unless an unread twin exists |
| `unraid.archiveNotification(c as Client, id as string)` | | archive it |
| `unraid.unarchiveNotification(c as Client, id as string)` | | move it back to unread |
| `unraid.deleteNotification(c as Client, id as string, archived as bool)` | | delete it |
| `unraid.archiveAll(c as Client, importance as string)` | | archive all unread; "" for every level |

## Administration

| Function | Returns | Does |
|---|---|---|
| `unraid.apiKeys(c as Client)` | `list of ApiKey` | the keys, without secrets |
| `unraid.createApiKey(c as Client, name as string, description as string, roles as list of string)` | `ApiKey` | make one; the secret is in `key`, once |
| `unraid.deleteApiKey(c as Client, id as string)` | | delete one |
| `unraid.plugins(c as Client)` | `list of Plugin` | installed plugins |
| `unraid.flash(c as Client)` | `Flash` | the boot device |
| `unraid.backupFlash(c as Client, remoteName as string, sourcePath as string, destinationPath as string)` | `FlashBackup` | copy the flash device to an rclone remote |
| `unraid.rcloneRemotes(c as Client)` | `list of RcloneRemote` | the rclone remotes |
| `unraid.createRcloneRemote(c as Client, name as string, type as string, parameters as json.Value)` | `RcloneRemote` | set one up |
| `unraid.deleteRcloneRemote(c as Client, name as string)` | | delete one |
| `unraid.setServerIdentity(c as Client, name as string, comment as string)` | | rename the server |

## Types

### `Client`

| Field | Meaning |
|---|---|
| `url as string` | the GraphQL endpoint |
| `apiKey as string` | sent as `x-api-key`; "" for none |
| `caCert as bytes` | a PEM certificate to trust |
| `insecure as bool` | accept any certificate |
| `timeoutMs as int` | idle timeout per request; 0 for 30 s |
| `retries as int` | retries of a query answered 429 or 5xx |
| `pollMs as int` | delay between `waitVm` checks |

### `Versions`

| Field | Meaning |
|---|---|
| `unraid as string` | e.g. `7.2.0` |
| `api as string` | the Unraid API's version |
| `kernel as string` | the Linux kernel |

### `SystemInfo`

| Field | Meaning |
|---|---|
| `name as string` | the server name |
| `version as string` | the Unraid version |
| `hostname as string` | the host name |
| `distro as string` | e.g. `Unraid OS` |
| `release as string` | its release |
| `kernel as string` | the Linux kernel |
| `arch as string` | e.g. `x64` |
| `bootTime as string` | ISO 8601 |
| `cpu as string` | the processor model |
| `cores as int` | physical cores |
| `threads as int` | hardware threads |
| `timeZone as string` | e.g. `Europe/Vienna` |

### `Metrics`

| Field | Meaning |
|---|---|
| `cpuPercent as float` | CPU load, percent |
| `memTotal as int` | bytes |
| `memUsed as int` | bytes |
| `memAvailable as int` | bytes |
| `memPercent as float` | percent in use |
| `swapTotal as int` | bytes |
| `swapUsed as int` | bytes |

### `Service`

| Field | Meaning |
|---|---|
| `name as string` | e.g. `unraid-api` |
| `online as bool` | whether it runs |
| `version as string` | "" when not reported |

### `UpsDevice`

| Field | Meaning |
|---|---|
| `id as string` | its id |
| `name as string` | its name |
| `model as string` | its model |
| `status as string` | e.g. `Online`, `On Battery` |
| `chargePercent as int` | battery charge |
| `runtimeSeconds as int` | estimated runtime |
| `health as string` | battery health |
| `loadPercent as int` | load |
| `inputVolts as float` | input voltage |
| `outputVolts as float` | output voltage |

### `LogFile`

| Field | Meaning |
|---|---|
| `name as string` | e.g. `syslog` |
| `path as string` | e.g. `/var/log/syslog` |
| `size as int` | bytes |
| `modified as string` | ISO 8601 |

### `LogChunk`

| Field | Meaning |
|---|---|
| `path as string` | the file |
| `content as string` | the lines |
| `totalLines as int` | lines in the file |
| `startLine as int` | first line returned, from 1; 0 when not reported |

### `ArrayDisk`

| Field | Meaning |
|---|---|
| `id as string` | its id |
| `idx as int` | slot: parity 0 and 29, data 1 to 28, pools 30 to 53 |
| `name as string` | e.g. `disk1` |
| `device as string` | e.g. `sdb` |
| `type as string` | `DATA`, `PARITY`, `CACHE`, `BOOT`, `FLASH` |
| `status as string` | e.g. `DISK_OK` |
| `sizeKb as int` | kilobytes |
| `fsSizeKb as int` | file system size, kilobytes |
| `fsFreeKb as int` | free, kilobytes |
| `fsUsedKb as int` | used, kilobytes |
| `fsType as string` | e.g. `xfs` |
| `temp as int` | degrees Celsius; -1 when spun down |
| `errors as int` | errors since the array started |
| `spinning as bool` | spun up |
| `rotational as bool` | a spinning disk |

### `ParityCheck`

| Field | Meaning |
|---|---|
| `status as string` | `NEVER_RUN`, `RUNNING`, `PAUSED`, `COMPLETED`, `CANCELLED`, `FAILED` |
| `running as bool` | one runs now |
| `paused as bool` | it is paused |
| `correcting as bool` | it writes corrections |
| `progress as int` | percent |
| `errors as int` | sync errors |
| `speed as string` | MB/s |
| `duration as int` | seconds |
| `date as string` | ISO 8601 |

### `StorageArray`

| Field | Meaning |
|---|---|
| `state as string` | `STARTED`, `STOPPED`, or why it cannot start |
| `totalKb as int` | capacity, kilobytes |
| `usedKb as int` | used, kilobytes |
| `freeKb as int` | free, kilobytes |
| `parities as list of ArrayDisk` | parity disks |
| `disks as list of ArrayDisk` | data disks |
| `caches as list of ArrayDisk` | pool devices |
| `parity as ParityCheck` | the current or last check |

### `Disk`

| Field | Meaning |
|---|---|
| `id as string` | its id |
| `device as string` | e.g. `/dev/sdb` |
| `name as string` | its model |
| `vendor as string` | its vendor |
| `type as string` | e.g. `HD`, `SSD` |
| `size as int` | bytes |
| `serial as string` | serial number |
| `firmware as string` | firmware revision |
| `interfaceType as string` | `SATA`, `SAS`, `USB`, `PCIE`, `UNKNOWN` |
| `smartStatus as string` | `OK` or `UNKNOWN` |
| `temperature as float` | degrees Celsius; -1.0 when not reported |
| `spinning as bool` | spun up |

### `Share`

| Field | Meaning |
|---|---|
| `id as string` | its id |
| `name as string` | e.g. `appdata` |
| `comment as string` | its description |
| `freeKb as int` | kilobytes |
| `usedKb as int` | kilobytes |
| `sizeKb as int` | kilobytes |
| `cache as bool` | uses a pool |
| `includeDisks as list of string` | disks it may use; empty for all |
| `excludeDisks as list of string` | disks it must not use |

### `Port`

| Field | Meaning |
|---|---|
| `ip as string` | host address, "" for all |
| `privatePort as int` | inside the container |
| `publicPort as int` | on the host; 0 when not published |
| `type as string` | `TCP` or `UDP` |

### `Container`

| Field | Meaning |
|---|---|
| `id as string` | its id |
| `name as string` | first name, without `/` |
| `names as list of string` | every name |
| `image as string` | its image |
| `state as string` | `RUNNING`, `PAUSED`, `EXITED` |
| `status as string` | e.g. `Up 3 hours` |
| `autoStart as bool` | starts with the array |
| `webUiUrl as string` | "" for none |
| `updateAvailable as bool` | a newer image is known |
| `created as int` | Unix seconds |
| `ports as list of Port` | its ports |

### `LogLine`

| Field | Meaning |
|---|---|
| `timestamp as string` | ISO 8601 |
| `message as string` | the line |

### `ContainerLogs`

| Field | Meaning |
|---|---|
| `lines as list of LogLine` | oldest first |
| `cursor as string` | pass as `since` to continue |

### `Autostart`

| Field | Meaning |
|---|---|
| `id as string` | the container |
| `autoStart as bool` | start it with the array |
| `wait as int` | seconds before the next one |

### `Vm`

| Field | Meaning |
|---|---|
| `id as string` | its id |
| `name as string` | its name |
| `state as string` | one of `VM_STATES` |

### `Notification`

| Field | Meaning |
|---|---|
| `id as string` | its id |
| `title as string` | its title |
| `subject as string` | its subject |
| `description as string` | its text |
| `importance as string` | `INFO`, `WARNING`, `ALERT` |
| `link as string` | "" for none |
| `archived as bool` | archived |
| `timestamp as string` | ISO 8601 |

### `NotificationCounts`

| Field | Meaning |
|---|---|
| `info as int` | `INFO` |
| `warning as int` | `WARNING` |
| `alert as int` | `ALERT` |
| `total as int` | all |

### `NotificationOverview`

| Field | Meaning |
|---|---|
| `unread as NotificationCounts` | unread ones |
| `archived as NotificationCounts` | archived ones |

### `ApiKey`

| Field | Meaning |
|---|---|
| `id as string` | its id |
| `name as string` | its name |
| `description as string` | its description |
| `key as string` | the secret; set only by `createApiKey` |
| `roles as list of string` | from `ROLES` |
| `createdAt as string` | ISO 8601 |

### `Plugin`

| Field | Meaning |
|---|---|
| `name as string` | its name |
| `version as string` | its version |

### `Flash`

| Field | Meaning |
|---|---|
| `guid as string` | the GUID the licence is tied to |
| `vendor as string` | its vendor |
| `product as string` | its product name |

### `RcloneRemote`

| Field | Meaning |
|---|---|
| `name as string` | its name |
| `type as string` | its backend, e.g. `s3` |

### `FlashBackup`

| Field | Meaning |
|---|---|
| `status as string` | as the server reports it |
| `jobId as string` | the rclone job; "" when not reported |
