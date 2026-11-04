<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Array, disks and shares

`array` returns the array's state, capacity, its parity, data and pool
disks, and the current or last parity check:

```jennifer
def a as unraid.StorageArray init unraid.array($c);
io.printf("%s, %d of %d KB free\n", $a.state, $a.freeKb, $a.totalKb);
for (def d in $a.disks) {
    io.printf("%s %s %d C, %d errors\n", $d.name, $d.status, $d.temp, $d.errors);
}
```

`ArrayDisk` sizes are kilobytes, as the API reports them. `temp` is -1 for a
spun-down disk. `state` is `STARTED`, `STOPPED`, or why the array cannot
start (`NEW_DISK_TOO_SMALL`, `TOO_MANY_MISSING_DISKS`, ...).

`startArray(c, passphrase)` starts it; pass "" unless the array is
encrypted. The passphrase is refused over `http://`. `stopArray` stops it,
which stops the containers and virtual machines that use it. `mountDisk`,
`unmountDisk`, `addDiskToArray` and `clearDiskStats` act on single disks.

## Physical disks

`disks` lists every disk the server sees, `assignableDisks` the ones in no
array or pool, `disk(c, id)` one. `Disk.size` is bytes; `smartStatus` is
`OK` or `UNKNOWN`.

## Shares

`shares` lists the user shares with their free, used and total space
(kilobytes) and the disks they may use.

## Parity checks

`parityStatus` is the current or last check, `parityHistory` the past ones.
`startParityCheck(c, correct)` starts one; `correct` true writes
corrections, false only counts errors. `pauseParityCheck`,
`resumeParityCheck` and `cancelParityCheck` control it. The API marks these
mutations as work in progress and answers them with free-form JSON, so read
the outcome with `parityStatus`.
