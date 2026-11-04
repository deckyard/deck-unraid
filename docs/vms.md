<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Virtual machines

```jennifer
def win as unraid.Vm init unraid.vmByName($c, "win11");
unraid.startVm($c, $win.id);
$win = unraid.waitVm($c, $win.id, "RUNNING", 60000);
```

`vms` lists every machine, `vm(c, id)` and `vmByName` find one. `state` is
one of `VM_STATES`; a stopped machine is `SHUTOFF`.

The controls answer only whether libvirt took the request, so use `waitVm`
for the state. `stopVm` and `rebootVm` ask the guest (ACPI), which may take
its time or ignore it; `forceStopVm` powers it off and `resetVm` resets it at
once. `pauseVm` and `resumeVm` freeze and thaw it.

`waitVm(c, id, state, timeoutMs)` checks every `pollMs` (`withPollInterval`,
1 s by default) and throws when time runs out.

The API cannot create virtual machines.
