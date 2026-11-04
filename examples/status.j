#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * Print a server's state: the array, its disks, containers and virtual
 * machines, and raise an Unraid notification for a disk that is not OK.
 *
 *   UNRAID_HOST=tower.local UNRAID_KEY=... jennifer run examples/status.j
 *
 * Needs a server and an API key with the VIEWER role (ADMIN to raise the
 * notification). Without UNRAID_HOST it prints how to run it.
 */
use io;
use os;
import "../src/unraid.j" as unraid;

if (os.getEnv("UNRAID_HOST") == "") {
    io.printf("set UNRAID_HOST and UNRAID_KEY to query a server\n");
} else {
    def c as unraid.Client init unraid.client(os.getEnv("UNRAID_HOST"));
    $c = unraid.withApiKey($c, os.getEnv("UNRAID_KEY"));
    if (os.getEnv("UNRAID_INSECURE") == "1") {
        $c = unraid.withInsecure($c);
    }
    def i as unraid.SystemInfo init unraid.info($c);
    io.printf("%s: Unraid %s on %s\n", $i.name, $i.version, $i.cpu);
    def a as unraid.StorageArray init unraid.array($c);
    io.printf("array %s, %d of %d KB free\n", $a.state, $a.freeKb, $a.totalKb);
    for (def d in $a.disks) {
        io.printf("  %s %s %d C\n", $d.name, $d.status, $d.temp);
        if ($d.status != "DISK_OK") {
            unraid.notifyOnce(
                $c,
                "Disk check",
                $d.name + " is " + $d.status,
                "reported by status.j",
                "WARNING",
                "");
        }
    }
    for (def ct in unraid.containers($c)) {
        io.printf("container %s %s\n", $ct.name, $ct.state);
    }
    for (def m in unraid.vms($c)) {
        io.printf("vm %s %s\n", $m.name, $m.state);
    }
}
