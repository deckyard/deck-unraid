<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Notifications

Unraid's notifications are what its web UI shows and mails out. A program can
raise its own:

```jennifer
unraid.notify($c, "Backup", "Nightly backup", "Finished in 12 min", "INFO", "");
unraid.notifyOnce($c, "Disk check", "disk3 is hot", "52 C", "WARNING", "");
```

`importance` is `INFO`, `WARNING` or `ALERT`. `notifyOnce` raises nothing
while an unread notification with the same content exists, so a check that
runs every few minutes does not pile up copies; it returns whether it raised
one.

`notifications(c, archived, importance, offset, limit)` reads a page;
`notificationOverview` counts them:

```jennifer
def o as unraid.NotificationOverview init unraid.notificationOverview($c);
if ($o.unread.alert > 0) {
    for (def n in unraid.notifications($c, false, "ALERT", 0, 50)) {
        io.printf("%s: %s\n", $n.subject, $n.description);
    }
}
```

`archiveNotification`, `unarchiveNotification` and `deleteNotification`
act on one; `archiveAll` on every unread one, or those of one importance.
