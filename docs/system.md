<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# System

```jennifer
def i as unraid.SystemInfo init unraid.info($c);
io.printf("%s, Unraid %s, %s (%d threads)\n", $i.name, $i.version, $i.cpu, $i.threads);

def m as unraid.Metrics init unraid.metrics($c);
io.printf("CPU %s percent, memory %s percent\n", convert.toString($m.cpuPercent), convert.toString($m.memPercent));
```

`version` gives the Unraid, API and kernel versions. `services` lists the
services the API reports on, `upsDevices` the power supplies it monitors
(empty without one).

## Logs

`logFiles` lists `/var/log`. `readLog(c, path, lines, startLine)` reads
part of a file; 0 for `lines` takes the server's default, 0 for
`startLine` the last lines. To follow a file, read from one past the last
`totalLines`:

```jennifer
def chunk as unraid.LogChunk init unraid.readLog($c, "/var/log/syslog", 50, 0);
def next as int init $chunk.totalLines + 1;
# later
def more as unraid.LogChunk init unraid.readLog($c, "/var/log/syslog", 0, $next);
```
