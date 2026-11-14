# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0
# pragma-jennifer-capability: net

/**
 * A client for the Unraid API.
 *
 * Unraid 7.2 and newer serve a GraphQL API at `/graphql` (older releases
 * with the Unraid Connect plugin); a key made under Settings > Management
 * Access > API Keys, or with `unraid-api apikey --create`, authenticates it.
 * `query` sends any document; typed functions cover the system, the array
 * and its disks, shares, parity checks, Docker containers, virtual machines,
 * notifications, logs and API keys.
 *
 * Unraid serves a self-signed certificate unless one was set up: trust it
 * with `withCaCert`, or turn checking off with `withInsecure`. Every failure
 * is an `UnraidError` (kind "unraid", with the HTTP `status` and the GraphQL
 * error `codes`), except a reply over its size cap: kind "limit".
 *
 * @module unraid
 * @see https://docs.unraid.net/API/
 * @example
 *   def c as unraid.Client init unraid.withApiKey(unraid.client("tower.local"), $key);
 *   for (def ct in unraid.containers($c)) {
 *       io.printf("%s %s\n", $ct.name, $ct.state);
 *   }
 */
use convert;
use json;
use lists;
use regex;
use strings;
use time;
import "graphql.j" as graphql;

/** The `kind` of every error the deck throws. */
export def const ERROR_KIND as string init "unraid";

/** The roles an API key can hold. */
export def const ROLES as list of string init ["ADMIN", "CONNECT", "GUEST", "VIEWER"];

/** The importance levels of a notification. */
export def const IMPORTANCE as list of string init ["INFO", "WARNING", "ALERT"];

/** The states a virtual machine reports. */
export def const VM_STATES as list of string init [
    "NOSTATE",
    "RUNNING",
    "IDLE",
    "PAUSED",
    "SHUTDOWN",
    "SHUTOFF",
    "CRASHED",
    "PMSUSPENDED"
];

/**
 * A connection to one Unraid server. Build it with `client` and the `with*`
 * functions.
 *
 * @field url {string} the GraphQL endpoint, e.g. `https://tower.local/graphql`
 * @field apiKey {string} the API key sent as `x-api-key`; "" for none
 * @field caCert {bytes} a PEM certificate to trust besides the system's
 * @field insecure {bool} accept any certificate
 * @field timeoutMs {int} the idle timeout of each request; 0 for 30 s
 * @field retries {int} retries of a query answered 429 or 5xx
 * @field pollMs {int} the delay between checks in `waitVm`
 */
export def struct Client {
    url as string,
    apiKey as string,
    caCert as bytes,
    insecure as bool,
    timeoutMs as int,
    retries as int,
    pollMs as int
};

/**
 * The versions a server runs.
 *
 * @field unraid {string} e.g. `7.2.0`
 * @field api {string} the Unraid API's own version
 * @field kernel {string} the Linux kernel
 */
export def struct Versions {
    unraid as string,
    api as string,
    kernel as string
};

/**
 * A server's summary.
 *
 * @field name {string} the server name set in Unraid
 * @field version {string} the Unraid version
 * @field hostname {string} the host name
 * @field distro {string} the operating system, e.g. `Unraid OS`
 * @field release {string} its release
 * @field kernel {string} the Linux kernel
 * @field arch {string} e.g. `x64`
 * @field bootTime {string} when it booted, an ISO 8601 time
 * @field cpu {string} the processor model
 * @field cores {int} physical cores
 * @field threads {int} hardware threads
 * @field timeZone {string} e.g. `Europe/Vienna`
 */
export def struct SystemInfo {
    name as string,
    version as string,
    hostname as string,
    distro as string,
    release as string,
    kernel as string,
    arch as string,
    bootTime as string,
    cpu as string,
    cores as int,
    threads as int,
    timeZone as string
};

/**
 * Current load and memory use.
 *
 * @field cpuPercent {float} CPU load, all cores, in percent
 * @field memTotal {int} memory in bytes
 * @field memUsed {int} memory in use, bytes
 * @field memAvailable {int} memory available to programs, bytes
 * @field memPercent {float} memory in use, percent
 * @field swapTotal {int} swap in bytes
 * @field swapUsed {int} swap in use, bytes
 */
export def struct Metrics {
    cpuPercent as float,
    memTotal as int,
    memUsed as int,
    memAvailable as int,
    memPercent as float,
    swapTotal as int,
    swapUsed as int
};

/**
 * A service the API reports on.
 *
 * @field name {string} e.g. `unraid-api`
 * @field online {bool} whether it runs
 * @field version {string} its version, "" when not reported
 */
export def struct Service {
    name as string,
    online as bool,
    version as string
};

/**
 * An uninterruptible power supply.
 *
 * @field id {string} its id
 * @field name {string} its name
 * @field model {string} its model
 * @field status {string} e.g. `Online`, `On Battery`
 * @field chargePercent {int} battery charge, percent
 * @field runtimeSeconds {int} estimated runtime on battery
 * @field health {string} battery health
 * @field loadPercent {int} load, percent
 * @field inputVolts {float} input voltage
 * @field outputVolts {float} output voltage
 */
export def struct UpsDevice {
    id as string,
    name as string,
    model as string,
    status as string,
    chargePercent as int,
    runtimeSeconds as int,
    health as string,
    loadPercent as int,
    inputVolts as float,
    outputVolts as float
};

/**
 * A log file under `/var/log`.
 *
 * @field name {string} e.g. `syslog`
 * @field path {string} e.g. `/var/log/syslog`
 * @field size {int} bytes
 * @field modified {string} the last change, an ISO 8601 time
 */
export def struct LogFile {
    name as string,
    path as string,
    size as int,
    modified as string
};

/**
 * Lines read from a log file.
 *
 * @field path {string} the file
 * @field content {string} the lines, newline-separated
 * @field totalLines {int} lines in the whole file
 * @field startLine {int} the first line returned, counting from 1; 0 when not reported
 */
export def struct LogChunk {
    path as string,
    content as string,
    totalLines as int,
    startLine as int
};

/**
 * A disk in the array, a parity disk or a pool (cache) device.
 *
 * @field id {string} its id
 * @field idx {int} its slot: parity 0 and 29, data 1 to 28, pools 30 to 53
 * @field name {string} e.g. `disk1`, `parity`, `cache`
 * @field device {string} e.g. `sdb`
 * @field type {string} `DATA`, `PARITY`, `CACHE`, `BOOT` or `FLASH`
 * @field status {string} e.g. `DISK_OK`, `DISK_DSBL`, `DISK_NP`
 * @field sizeKb {int} its size in kilobytes
 * @field fsSizeKb {int} the file system's size in kilobytes; 0 for parity
 * @field fsFreeKb {int} free space in kilobytes
 * @field fsUsedKb {int} used space in kilobytes
 * @field fsType {string} e.g. `xfs`, `btrfs`, `zfs`
 * @field temp {int} degrees Celsius; -1 when not reported (a spun-down disk)
 * @field errors {int} read and write errors counted since the array started
 * @field spinning {bool} whether it is spun up
 * @field rotational {bool} a spinning disk rather than an SSD
 */
export def struct ArrayDisk {
    id as string,
    idx as int,
    name as string,
    device as string,
    type as string,
    status as string,
    sizeKb as int,
    fsSizeKb as int,
    fsFreeKb as int,
    fsUsedKb as int,
    fsType as string,
    temp as int,
    errors as int,
    spinning as bool,
    rotational as bool
};

/**
 * A parity check, running or finished.
 *
 * @field status {string} `NEVER_RUN`, `RUNNING`, `PAUSED`, `COMPLETED`, `CANCELLED` or `FAILED`
 * @field running {bool} whether one runs now
 * @field paused {bool} whether it is paused
 * @field correcting {bool} whether it writes corrections
 * @field progress {int} percent done
 * @field errors {int} sync errors found
 * @field speed {string} MB/s, as Unraid reports it
 * @field duration {int} seconds
 * @field date {string} when it ran, an ISO 8601 time; "" when not reported
 */
export def struct ParityCheck {
    status as string,
    running as bool,
    paused as bool,
    correcting as bool,
    progress as int,
    errors as int,
    speed as string,
    duration as int,
    date as string
};

/**
 * The array: its state, size and disks.
 *
 * @field state {string} `STARTED`, `STOPPED`, or why it cannot start, e.g. `NEW_DISK_TOO_SMALL`
 * @field totalKb {int} capacity in kilobytes
 * @field usedKb {int} used, kilobytes
 * @field freeKb {int} free, kilobytes
 * @field parities {list of ArrayDisk} the parity disks
 * @field disks {list of ArrayDisk} the data disks
 * @field caches {list of ArrayDisk} the pool devices
 * @field parity {ParityCheck} the current or last parity check
 */
export def struct StorageArray {
    state as string,
    totalKb as int,
    usedKb as int,
    freeKb as int,
    parities as list of ArrayDisk,
    disks as list of ArrayDisk,
    caches as list of ArrayDisk,
    parity as ParityCheck
};

/**
 * A physical disk, in the array or not.
 *
 * @field id {string} its id
 * @field device {string} e.g. `/dev/sdb`
 * @field name {string} its model name
 * @field vendor {string} its vendor
 * @field type {string} e.g. `HD`, `SSD`
 * @field size {int} bytes
 * @field serial {string} its serial number
 * @field firmware {string} its firmware revision
 * @field interfaceType {string} `SATA`, `SAS`, `USB`, `PCIE` or `UNKNOWN`
 * @field smartStatus {string} `OK` or `UNKNOWN`
 * @field temperature {float} degrees Celsius; -1.0 when not reported
 * @field spinning {bool} whether it is spun up
 */
export def struct Disk {
    id as string,
    device as string,
    name as string,
    vendor as string,
    type as string,
    size as int,
    serial as string,
    firmware as string,
    interfaceType as string,
    smartStatus as string,
    temperature as float,
    spinning as bool
};

/**
 * A user share.
 *
 * @field id {string} its id
 * @field name {string} e.g. `appdata`
 * @field comment {string} its description
 * @field freeKb {int} free space, kilobytes
 * @field usedKb {int} used space, kilobytes
 * @field sizeKb {int} total, kilobytes
 * @field cache {bool} whether it uses a pool
 * @field includeDisks {list of string} the disks it may use; empty for all
 * @field excludeDisks {list of string} the disks it must not use
 */
export def struct Share {
    id as string,
    name as string,
    comment as string,
    freeKb as int,
    usedKb as int,
    sizeKb as int,
    cache as bool,
    includeDisks as list of string,
    excludeDisks as list of string
};

/**
 * A published container port.
 *
 * @field ip {string} the host address, "" for all
 * @field privatePort {int} the port inside the container
 * @field publicPort {int} the port on the host; 0 when not published
 * @field type {string} `TCP` or `UDP`
 */
export def struct Port {
    ip as string,
    privatePort as int,
    publicPort as int,
    type as string
};

/**
 * A Docker container.
 *
 * @field id {string} its id
 * @field name {string} its first name, without the leading `/`
 * @field names {list of string} every name, as Docker reports them
 * @field image {string} e.g. `lscr.io/linuxserver/plex:latest`
 * @field state {string} `RUNNING`, `PAUSED` or `EXITED`
 * @field status {string} Docker's status line, e.g. `Up 3 hours`
 * @field autoStart {bool} whether it starts with the array
 * @field webUiUrl {string} its web UI, "" for none
 * @field updateAvailable {bool} whether a newer image is known
 * @field created {int} Unix seconds
 * @field ports {list of Port} its ports
 */
export def struct Container {
    id as string,
    name as string,
    names as list of string,
    image as string,
    state as string,
    status as string,
    autoStart as bool,
    webUiUrl as string,
    updateAvailable as bool,
    created as int,
    ports as list of Port
};

/**
 * One line of a container's log.
 *
 * @field timestamp {string} an ISO 8601 time
 * @field message {string} the line
 */
export def struct LogLine {
    timestamp as string,
    message as string
};

/**
 * Lines of a container's log, and where to continue.
 *
 * @field lines {list of LogLine} the lines, oldest first
 * @field cursor {string} pass it as `since` to read what follows; "" when not reported
 */
export def struct ContainerLogs {
    lines as list of LogLine,
    cursor as string
};

/**
 * Whether and when a container starts with the array.
 *
 * @field id {string} the container
 * @field autoStart {bool} start it with the array
 * @field wait {int} seconds to wait after it started before the next one
 */
export def struct Autostart {
    id as string,
    autoStart as bool,
    wait as int
};

/**
 * A virtual machine.
 *
 * @field id {string} its id (the libvirt UUID with the server prefix)
 * @field name {string} its name
 * @field state {string} one of `VM_STATES`
 */
export def struct Vm {
    id as string,
    name as string,
    state as string
};

/**
 * A notification.
 *
 * @field id {string} its id
 * @field title {string} its title
 * @field subject {string} its subject
 * @field description {string} its text
 * @field importance {string} `INFO`, `WARNING` or `ALERT`
 * @field link {string} a link, "" for none
 * @field archived {bool} whether it is archived
 * @field timestamp {string} when it was raised, an ISO 8601 time
 */
export def struct Notification {
    id as string,
    title as string,
    subject as string,
    description as string,
    importance as string,
    link as string,
    archived as bool,
    timestamp as string
};

/**
 * Notifications counted by importance.
 *
 * @field info {int} `INFO`
 * @field warning {int} `WARNING`
 * @field alert {int} `ALERT`
 * @field total {int} all of them
 */
export def struct NotificationCounts {
    info as int,
    warning as int,
    alert as int,
    total as int
};

/**
 * Unread and archived notifications, counted.
 *
 * @field unread {NotificationCounts} unread ones
 * @field archived {NotificationCounts} archived ones
 */
export def struct NotificationOverview {
    unread as NotificationCounts,
    archived as NotificationCounts
};

/**
 * An API key.
 *
 * @field id {string} its id
 * @field name {string} its name
 * @field description {string} its description
 * @field key {string} the secret; set only by `createApiKey`
 * @field roles {list of string} its roles, from `ROLES`
 * @field createdAt {string} an ISO 8601 time
 */
export def struct ApiKey {
    id as string,
    name as string,
    description as string,
    key as string,
    roles as list of string,
    createdAt as string
};

/**
 * An installed plugin.
 *
 * @field name {string} its name
 * @field version {string} its version
 */
export def struct Plugin {
    name as string,
    version as string
};

/**
 * The USB flash device Unraid boots from.
 *
 * @field guid {string} its GUID, which the licence is tied to
 * @field vendor {string} its vendor
 * @field product {string} its product name
 */
export def struct Flash {
    guid as string,
    vendor as string,
    product as string
};

/**
 * An rclone remote set up on the server.
 *
 * @field name {string} its name
 * @field type {string} its backend, e.g. `s3`, `drive`
 */
export def struct RcloneRemote {
    name as string,
    type as string
};

/**
 * A flash backup that was started.
 *
 * @field status {string} as the server reports it
 * @field jobId {string} the rclone job, "" when not reported
 */
export def struct FlashBackup {
    status as string,
    jobId as string
};

# --- errors -------------------------------------------------------------------

/**
 * A failed Unraid call. Every error of kind `"unraid"` is one, so its fields
 * are safe to read once the kind matches.
 *
 * @field kind {string} always `"unraid"` (`ERROR_KIND`)
 * @field message {string} `unraid: <operation>: <what went wrong>`
 * @field status {int} the HTTP status of a failed GraphQL request (401, 403, 502, ...); 0 when there was none
 * @field codes {list of string} each GraphQL error's `extensions.code` (`UNAUTHENTICATED`, `FORBIDDEN`, ...), "" for one without; empty unless the server answered GraphQL errors
 */
export def struct UnraidError {
    kind as string,
    message as string,
    status as int,
    codes as list of string
};

func fail(message as string) {
    throw UnraidError{kind: ERROR_KIND, message: "unraid: " + $message, status: 0, codes: []};
}

# How much of a string an error message repeats.
def const SHOWN as int init 60;

/**
 * A string fit for an error message: cut to `most` characters, with
 * anything but printable ASCII as `?`, so a message stays one line and
 * carries no line break or terminal escape into a log.
 *
 * @param text {string} a caller's or the server's string
 * @param most {int} the characters kept
 * @return {string} the text
 */
func plain(text as string, most as int) {
    def cut as string init $text;
    def more as string init "";
    if (len($text) > $most) {
        $cut = strings.substring($text, 0, $most);
        $more = "...";
    }
    return regex.replace("[^ -~]", $cut, "?") + $more;
}

/**
 * A string as an error message quotes it: `plain`, cut to `SHOWN`.
 *
 * @param text {string} a caller's or the server's string
 * @return {string} the text in double quotes
 */
func shown(text as string) {
    return "\"" + plain($text, SHOWN) + "\"";
}

# --- client -------------------------------------------------------------------

/**
 * The endpoint URL for a host name or URL. A bare host gets `https://` and
 * `/graphql`; a URL without a path gets `/graphql`.
 *
 * @param address {string} `tower.local`, `10.0.0.5:8443` or `https://tower.local/graphql`
 * @return {string} the endpoint
 */
func endpointOf(address as string) {
    def url as string init strings.trim($address);
    if ($url == "") {
        fail("the host is empty");
    }
    if (regex.matches("[\\x00-\\x20\\x7f]", $url)) {
        fail("the address holds a space or control character: " + shown($url));
    }
    if (strings.contains($url, "?") or strings.contains($url, "#")) {
        fail("the address holds a query or fragment: " + shown($url));
    }
    if (not strings.contains($url, "://")) {
        $url = "https://" + $url;
    } elseif (not regex.matches("^https?://", strings.lower($url))) {
        fail("the address is not http:// or https://: " + shown($url));
    }
    while (strings.endsWith($url, "/")) {
        $url = $url[..len($url) - 1];
    }
    def rest as string init $url[strings.indexOf($url, "://") + 3..];
    if (strings.contains($rest, "@")) {
        fail("the address holds credentials; use withApiKey");
    }
    if (not strings.contains($rest, "/")) {
        $url = $url + "/graphql";
    }
    return $url;
}

/**
 * A client for a server, with no API key yet.
 *
 * @param address {string} host name, `host:port` or a full URL; a bare host gets `https://` and `/graphql`
 * @return {Client} the client; full certificate checking, 1 s polling
 * @throws {Error} kind `"unraid"` when the address is empty, not http(s), or holds credentials, a query or a fragment
 * @example
 *   def c as unraid.Client init unraid.client("tower.local");
 */
export func client(address as string) {
    def c as Client;
    $c.url = endpointOf($address);
    $c.pollMs = 1000;
    return $c;
}

/**
 * Authenticate with an API key, sent as `x-api-key`.
 *
 * @param c {Client} the client
 * @param key {string} the key: letters, digits, `-` and `_`, as Unraid issues them
 * @return {Client} the changed copy
 * @throws {Error} kind `"unraid"` on another character (the key is not repeated)
 */
export func withApiKey(c as Client, key as string) {
    if (not regex.matches("^[A-Za-z0-9_-]+$", $key)) {
        fail("an API key is letters, digits, - and _");
    }
    $c.apiKey = $key;
    return $c;
}

/**
 * Trust a certificate (PEM) in addition to the system's, such as the one
 * Unraid created for itself.
 *
 * @param c {Client} the client
 * @param pem {bytes} the certificate
 * @return {Client} the changed copy
 */
export func withCaCert(c as Client, pem as bytes) {
    $c.caCert = $pem;
    $c.insecure = false;
    return $c;
}

/**
 * Accept any certificate. The connection stays encrypted but is no longer
 * authenticated; prefer `withCaCert`.
 *
 * @param c {Client} the client
 * @return {Client} the changed copy
 */
export func withInsecure(c as Client) {
    $c.insecure = true;
    return $c;
}

/**
 * Set the idle timeout of each request.
 *
 * @param c {Client} the client
 * @param ms {int} milliseconds; 0 for the default, 30 s
 * @return {Client} the changed copy
 */
export func withTimeout(c as Client, ms as int) {
    $c.timeoutMs = $ms;
    return $c;
}

/**
 * Retry a query answered 429 or 5xx. A mutation is never retried: the server
 * may have done it.
 *
 * @param c {Client} the client
 * @param n {int} retries, 0 for none
 * @return {Client} the changed copy
 */
export func withRetries(c as Client, n as int) {
    $c.retries = $n;
    return $c;
}

/**
 * Set how often `waitVm` checks a machine's state.
 *
 * @param c {Client} the client
 * @param ms {int} milliseconds between checks
 * @return {Client} the changed copy
 */
export func withPollInterval(c as Client, ms as int) {
    $c.pollMs = $ms;
    return $c;
}

# --- transport ----------------------------------------------------------------

/**
 * The `graphql` client for a client's settings.
 *
 * @param c {Client} the client
 * @return {graphql.Client} the GraphQL client
 */
func gql(c as Client) {
    def g as graphql.Client init graphql.client($c.url);
    if ($c.apiKey != "") {
        $g = graphql.header($g, "x-api-key", $c.apiKey);
    }
    if (len($c.caCert) > 0) {
        $g = graphql.withCA($g, $c.caCert);
    }
    if ($c.insecure) {
        $g = graphql.insecure($g);
    }
    $g = graphql.withTimeout($g, $c.timeoutMs);
    if ($c.retries > 0) {
        $g = graphql.withBackoff(graphql.withRetries($g, $c.retries), 500);
    }
    return $g;
}

/**
 * Send a document and return its `data`, turning any failure into an
 * `unraid` error that names what was asked.
 *
 * @param c {Client} the client
 * @param what {string} the operation, for the message
 * @param document {string} the query or mutation
 * @param variables {json.Value} its variables
 * @return {json.Value} the reply's `data`
 */
func run(c as Client, what as string, document as string, variables as json.Value) {
    def resp as json.Value;
    try {
        $resp = graphql.query(gql($c), $document, $variables);
    } catch (e) {
        def message as string init $e.message;
        if (strings.startsWith($message, "graphql: ")) {
            $message = $message[9..];
        }
        # a reply over its size cap stays a reached cap
        if ($e.kind == "limit") {
            throw Error{kind: "limit", message: "unraid: " + $what + ": " + plain($message, 300)};
        }
        def status as int init 0;
        def codes as list of string init [];
        if ($e.kind == "graphql") {
            $status = $e.status;
            $codes = $e.codes;
        }
        throw UnraidError{
            kind: ERROR_KIND,
            message: "unraid: " + $what + ": " + plain($message, 300),
            status: $status,
            codes: $codes
        };
    }
    if (json.typeOf($resp, "/data") != "map") {
        fail($what + ": the reply has no data");
    }
    return json.get($resp, "/data");
}

/**
 * Variables with one string.
 *
 * @param name {string} the variable
 * @param value {string} its value
 * @return {json.Value} the variables
 */
func withVar(name as string, value as string) {
    return json.set(json.map(), "/" + $name, $value);
}

/**
 * Check an id before it goes into a request.
 *
 * @param id {string} the id
 * @param what {string} what it identifies, for the message
 */
func checkId(id as string, what as string) {
    if ($id == "" or regex.matches("[\\x00-\\x1f\\x7f]", $id)) {
        fail("a " + $what + " id is not empty and holds no control characters, got " + shown($id));
    }
}

/**
 * Send any query or mutation and return the reply's `data`. A document that
 * is a query may be retried (`withRetries`); a mutation never is.
 *
 * @param c {Client} the client
 * @param document {string} the GraphQL document
 * @param variables {json.Value} its variables; `json.map()` for none
 * @return {json.Value} the reply's `data`
 * @throws {Error} kind `"unraid"` on an HTTP or GraphQL error
 * @example
 *   def d as json.Value init unraid.query($c, 'query { online }', json.map());
 */
export func query(c as Client, document as string, variables as json.Value) {
    return run($c, "query", $document, $variables);
}

# --- reading replies ----------------------------------------------------------

/**
 * A string field, "" when missing or null; a number is rendered.
 *
 * @param v {json.Value} the object
 * @param ptr {string} the pointer
 * @return {string} the value
 */
func text(v as json.Value, ptr as string) {
    def t as string init json.typeOf($v, $ptr);
    if ($t == "string") {
        return json.asString($v, $ptr);
    }
    if ($t == "int") {
        return convert.toString(json.asInt($v, $ptr));
    }
    if ($t == "float") {
        return convert.toString(json.asFloat($v, $ptr));
    }
    return "";
}

/**
 * A whole-number field: a JSON number, or a numeric string (how `BigInt`
 * and the capacity fields may come); `missing` when absent, null or not a
 * number.
 *
 * @param v {json.Value} the object
 * @param ptr {string} the pointer
 * @param missing {int} the value for an absent field
 * @return {int} the value
 */
func whole(v as json.Value, ptr as string, missing as int) {
    def t as string init json.typeOf($v, $ptr);
    if ($t == "int") {
        return json.asInt($v, $ptr);
    }
    if ($t == "float") {
        # Past what an int holds it is no size or count anyone reports.
        def f as float init json.asFloat($v, $ptr);
        if ($f > 9.0e18 or $f < -9.0e18) {
            return $missing;
        }
        return convert.toInt($f // 1);
    }
    if ($t == "string") {
        def s as string init strings.trim(json.asString($v, $ptr));
        if (regex.matches('^-?[0-9]{1,18}$', $s)) {
            return convert.toInt($s);
        }
    }
    return $missing;
}

/**
 * A number field as a float; `missing` when absent, null or not a number.
 *
 * @param v {json.Value} the object
 * @param ptr {string} the pointer
 * @param missing {float} the value for an absent field
 * @return {float} the value
 */
func real(v as json.Value, ptr as string, missing as float) {
    def t as string init json.typeOf($v, $ptr);
    if ($t == "int" or $t == "float") {
        return json.asFloat($v, $ptr);
    }
    if ($t == "string") {
        def s as string init strings.trim(json.asString($v, $ptr));
        if (regex.matches("^-?[0-9]+(\\.[0-9]+)?$", $s)) {
            return convert.toFloat($s);
        }
    }
    return $missing;
}

/**
 * A boolean field, false when missing or null.
 *
 * @param v {json.Value} the object
 * @param ptr {string} the pointer
 * @return {bool} the value
 */
func flag(v as json.Value, ptr as string) {
    if (json.typeOf($v, $ptr) == "bool") {
        return json.asBool($v, $ptr);
    }
    return false;
}

/**
 * The strings of a list field; empty when missing or null.
 *
 * @param v {json.Value} the object
 * @param ptr {string} the pointer
 * @return {list of string} the strings
 */
func texts(v as json.Value, ptr as string) {
    def out as list of string init [];
    if (json.typeOf($v, $ptr) != "list") {
        return $out;
    }
    def n as int init json.length($v, $ptr);
    for (def i in 0..$n) {
        $out[] = text($v, $ptr + "/" + convert.toString($i));
    }
    return $out;
}

/**
 * How many entries a list field has; 0 when missing or null.
 *
 * @param v {json.Value} the object
 * @param ptr {string} the pointer
 * @return {int} the count
 */
func count(v as json.Value, ptr as string) {
    if (json.typeOf($v, $ptr) != "list") {
        return 0;
    }
    return json.length($v, $ptr);
}

# --- system -------------------------------------------------------------------

/**
 * Whether the server reports itself online.
 *
 * @param c {Client} the client
 * @return {bool} the answer
 * @throws {Error} kind `"unraid"` when the request fails
 */
export func online(c as Client) {
    return flag(run($c, "online", 'query { online }', json.map()), "/online");
}

/**
 * The versions the server runs.
 *
 * @param c {Client} the client
 * @return {Versions} the versions
 * @throws {Error} kind `"unraid"` when the request fails
 */
export func version(c as Client) {
    def d as json.Value init run(
        $c,
        "version",
        'query { info { versions { core { unraid api kernel } } } }',
        json.map());
    return Versions{
        unraid: text($d, "/info/versions/core/unraid"),
        api: text($d, "/info/versions/core/api"),
        kernel: text($d, "/info/versions/core/kernel")
    };
}

/**
 * The server's summary.
 *
 * @param c {Client} the client
 * @return {SystemInfo} the summary
 * @throws {Error} kind `"unraid"` when the request fails
 */
export func info(c as Client) {
    def d as json.Value init run(
        $c,
        "info",
        'query { vars { name version timeZone } info { os { hostname distro release kernel arch uptime } cpu { brand cores threads } } }',
        json.map());
    return SystemInfo{
        name: text($d, "/vars/name"),
        version: text($d, "/vars/version"),
        hostname: text($d, "/info/os/hostname"),
        distro: text($d, "/info/os/distro"),
        release: text($d, "/info/os/release"),
        kernel: text($d, "/info/os/kernel"),
        arch: text($d, "/info/os/arch"),
        bootTime: text($d, "/info/os/uptime"),
        cpu: text($d, "/info/cpu/brand"),
        cores: whole($d, "/info/cpu/cores", 0),
        threads: whole($d, "/info/cpu/threads", 0),
        timeZone: text($d, "/vars/timeZone")
    };
}

/**
 * Current CPU load and memory use.
 *
 * @param c {Client} the client
 * @return {Metrics} the figures
 * @throws {Error} kind `"unraid"` when the request fails
 */
export func metrics(c as Client) {
    def d as json.Value init run(
        $c,
        "metrics",
        'query { metrics { cpu { percentTotal } memory { total used available percentTotal swapTotal swapUsed } } }',
        json.map());
    return Metrics{
        cpuPercent: real($d, "/metrics/cpu/percentTotal", 0.0),
        memTotal: whole($d, "/metrics/memory/total", 0),
        memUsed: whole($d, "/metrics/memory/used", 0),
        memAvailable: whole($d, "/metrics/memory/available", 0),
        memPercent: real($d, "/metrics/memory/percentTotal", 0.0),
        swapTotal: whole($d, "/metrics/memory/swapTotal", 0),
        swapUsed: whole($d, "/metrics/memory/swapUsed", 0)
    };
}

/**
 * The services the API reports on.
 *
 * @param c {Client} the client
 * @return {list of Service} the services
 * @throws {Error} kind `"unraid"` when the request fails
 */
export func services(c as Client) {
    def d as json.Value init run(
        $c,
        "services",
        'query { services { name online version } }',
        json.map());
    def out as list of Service init [];
    for (def i in 0..count($d, "/services")) {
        def p as string init "/services/" + convert.toString($i);
        $out[] = Service{
            name: text($d, $p + "/name"),
            online: flag($d, $p + "/online"),
            version: text($d, $p + "/version")
        };
    }
    return $out;
}

/**
 * The power supplies the server monitors.
 *
 * @param c {Client} the client
 * @return {list of UpsDevice} the devices; empty without one
 * @throws {Error} kind `"unraid"` when the request fails
 */
export func upsDevices(c as Client) {
    def d as json.Value init run(
        $c,
        "upsDevices",
        'query { upsDevices { id name model status battery { chargeLevel estimatedRuntime health } power { loadPercentage inputVoltage outputVoltage } } }',
        json.map());
    def out as list of UpsDevice init [];
    for (def i in 0..count($d, "/upsDevices")) {
        def p as string init "/upsDevices/" + convert.toString($i);
        $out[] = UpsDevice{
            id: text($d, $p + "/id"),
            name: text($d, $p + "/name"),
            model: text($d, $p + "/model"),
            status: text($d, $p + "/status"),
            chargePercent: whole($d, $p + "/battery/chargeLevel", 0),
            runtimeSeconds: whole($d, $p + "/battery/estimatedRuntime", 0),
            health: text($d, $p + "/battery/health"),
            loadPercent: whole($d, $p + "/power/loadPercentage", 0),
            inputVolts: real($d, $p + "/power/inputVoltage", 0.0),
            outputVolts: real($d, $p + "/power/outputVoltage", 0.0)
        };
    }
    return $out;
}

/**
 * The log files the server offers.
 *
 * @param c {Client} the client
 * @return {list of LogFile} the files
 * @throws {Error} kind `"unraid"` when the request fails
 */
export func logFiles(c as Client) {
    def d as json.Value init run(
        $c,
        "logFiles",
        'query { logFiles { name path size modifiedAt } }',
        json.map());
    def out as list of LogFile init [];
    for (def i in 0..count($d, "/logFiles")) {
        def p as string init "/logFiles/" + convert.toString($i);
        $out[] = LogFile{
            name: text($d, $p + "/name"),
            path: text($d, $p + "/path"),
            size: whole($d, $p + "/size", 0),
            modified: text($d, $p + "/modifiedAt")
        };
    }
    return $out;
}

/**
 * Read lines of a log file. Poll with `startLine` past the last
 * `totalLines` to follow it.
 *
 * @param c {Client} the client
 * @param path {string} the file, as `logFiles` lists it
 * @param lines {int} how many lines; 0 for the server's default
 * @param startLine {int} the first line, counting from 1; 0 for the last ones
 * @return {LogChunk} the lines
 * @throws {Error} kind `"unraid"` when the request fails
 */
export func readLog(c as Client, path as string, lines as int, startLine as int) {
    if ($path == "" or regex.matches("[\\x00-\\x1f\\x7f]", $path)) {
        fail("readLog: a path is not empty and holds no control characters");
    }
    def vars as json.Value init withVar("path", $path);
    if ($lines > 0) {
        $vars = json.set($vars, "/lines", $lines);
    }
    if ($startLine > 0) {
        $vars = json.set($vars, "/startLine", $startLine);
    }
    def d as json.Value init run(
        $c,
        "readLog " + shown($path),
        'query($path: String!, $lines: Int, $startLine: Int) { logFile(path: $path, lines: $lines, startLine: $startLine) { path content totalLines startLine } }',
        $vars);
    return LogChunk{
        path: text($d, "/logFile/path"),
        content: text($d, "/logFile/content"),
        totalLines: whole($d, "/logFile/totalLines", 0),
        startLine: whole($d, "/logFile/startLine", 0)
    };
}

# --- storage ------------------------------------------------------------------

# The fields asked for an ArrayDisk.
def const DISK_FIELDS as string init "id idx name device type status size fsSize fsFree fsUsed fsType temp numErrors isSpinning rotational";

# The fields asked for a ParityCheck.
def const PARITY_FIELDS as string init "status running paused correcting progress errors speed duration date";

# The fields asked for the array.
def const ARRAY_FIELDS as string init 'state capacity { kilobytes { free used total } } parityCheckStatus { ' +
    PARITY_FIELDS + ' } parities { ' + DISK_FIELDS + ' } disks { ' + DISK_FIELDS + ' } caches { ' +
    DISK_FIELDS + ' }';

/**
 * An ArrayDisk from its object.
 *
 * @param d {json.Value} the reply
 * @param p {string} the pointer to the disk
 * @return {ArrayDisk} the disk
 */
func arrayDiskAt(d as json.Value, p as string) {
    return ArrayDisk{
        id: text($d, $p + "/id"),
        idx: whole($d, $p + "/idx", -1),
        name: text($d, $p + "/name"),
        device: text($d, $p + "/device"),
        type: text($d, $p + "/type"),
        status: text($d, $p + "/status"),
        sizeKb: whole($d, $p + "/size", 0),
        fsSizeKb: whole($d, $p + "/fsSize", 0),
        fsFreeKb: whole($d, $p + "/fsFree", 0),
        fsUsedKb: whole($d, $p + "/fsUsed", 0),
        fsType: text($d, $p + "/fsType"),
        temp: whole($d, $p + "/temp", -1),
        errors: whole($d, $p + "/numErrors", 0),
        spinning: flag($d, $p + "/isSpinning"),
        rotational: flag($d, $p + "/rotational")
    };
}

/**
 * The ArrayDisks of a list field.
 *
 * @param d {json.Value} the reply
 * @param p {string} the pointer to the list
 * @return {list of ArrayDisk} the disks
 */
func arrayDisksAt(d as json.Value, p as string) {
    def out as list of ArrayDisk init [];
    for (def i in 0..count($d, $p)) {
        $out[] = arrayDiskAt($d, $p + "/" + convert.toString($i));
    }
    return $out;
}

/**
 * A ParityCheck from its object.
 *
 * @param d {json.Value} the reply
 * @param p {string} the pointer to the check
 * @return {ParityCheck} the check
 */
func parityAt(d as json.Value, p as string) {
    return ParityCheck{
        status: text($d, $p + "/status"),
        running: flag($d, $p + "/running"),
        paused: flag($d, $p + "/paused"),
        correcting: flag($d, $p + "/correcting"),
        progress: whole($d, $p + "/progress", 0),
        errors: whole($d, $p + "/errors", 0),
        speed: text($d, $p + "/speed"),
        duration: whole($d, $p + "/duration", 0),
        date: text($d, $p + "/date")
    };
}

/**
 * A StorageArray from its object.
 *
 * @param d {json.Value} the reply
 * @param p {string} the pointer to the array
 * @return {StorageArray} the array
 */
func arrayAt(d as json.Value, p as string) {
    return StorageArray{
        state: text($d, $p + "/state"),
        totalKb: whole($d, $p + "/capacity/kilobytes/total", 0),
        usedKb: whole($d, $p + "/capacity/kilobytes/used", 0),
        freeKb: whole($d, $p + "/capacity/kilobytes/free", 0),
        parities: arrayDisksAt($d, $p + "/parities"),
        disks: arrayDisksAt($d, $p + "/disks"),
        caches: arrayDisksAt($d, $p + "/caches"),
        parity: parityAt($d, $p + "/parityCheckStatus")
    };
}

/**
 * The array: its state, capacity, disks and parity check.
 *
 * @param c {Client} the client
 * @return {StorageArray} the array
 * @throws {Error} kind `"unraid"` when the request fails
 */
export func array(c as Client) {
    def d as json.Value init run(
        $c,
        "array",
        'query { array { ' + ARRAY_FIELDS + ' } }',
        json.map());
    return arrayAt($d, "/array");
}

/**
 * Start or stop the array.
 *
 * @param c {Client} the client
 * @param what {string} the operation, for messages
 * @param desired {string} `START` or `STOP`
 * @param passphrase {string} the encryption passphrase, "" for none
 * @return {StorageArray} the array afterwards
 */
func setArrayState(c as Client, what as string, desired as string, passphrase as string) {
    def input as json.Value init json.set(json.map(), "/desiredState", $desired);
    if ($passphrase != "") {
        if (strings.startsWith(strings.lower($c.url), "http://")) {
            fail($what + ": an encryption passphrase goes over https:// only");
        }
        $input = json.set($input, "/decryptionPassword", $passphrase);
    }
    def d as json.Value init run(
        $c,
        $what,
        'mutation($input: ArrayStateInput!) { array { setState(input: $input) { ' + ARRAY_FIELDS +
            ' } } }',
        json.set(json.map(), "/input", $input));
    return arrayAt($d, "/array/setState");
}

/**
 * Start the array.
 *
 * @param c {Client} the client
 * @param passphrase {string} the passphrase of an encrypted array, "" for none; sent over https:// only
 * @return {StorageArray} the array afterwards
 * @throws {Error} kind `"unraid"` when the server refuses, or a passphrase would go over http://
 */
export func startArray(c as Client, passphrase as string) {
    return setArrayState($c, "startArray", "START", $passphrase);
}

/**
 * Stop the array. Containers and virtual machines that use it stop first.
 *
 * @param c {Client} the client
 * @return {StorageArray} the array afterwards
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func stopArray(c as Client) {
    return setArrayState($c, "stopArray", "STOP", "");
}

/**
 * Mount a disk of the array.
 *
 * @param c {Client} the client
 * @param id {string} the disk's id
 * @return {ArrayDisk} the disk afterwards
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func mountDisk(c as Client, id as string) {
    checkId($id, "disk");
    def d as json.Value init run(
        $c,
        "mountDisk",
        'mutation($id: PrefixedID!) { array { mountArrayDisk(id: $id) { ' + DISK_FIELDS + ' } } }',
        withVar("id", $id));
    return arrayDiskAt($d, "/array/mountArrayDisk");
}

/**
 * Unmount a disk of the array.
 *
 * @param c {Client} the client
 * @param id {string} the disk's id
 * @return {ArrayDisk} the disk afterwards
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func unmountDisk(c as Client, id as string) {
    checkId($id, "disk");
    def d as json.Value init run(
        $c,
        "unmountDisk",
        'mutation($id: PrefixedID!) { array { unmountArrayDisk(id: $id) { ' + DISK_FIELDS + ' } } }',
        withVar("id", $id));
    return arrayDiskAt($d, "/array/unmountArrayDisk");
}

/**
 * Add a disk to the stopped array.
 *
 * @param c {Client} the client
 * @param id {string} the disk's id, from `disks`
 * @param slot {int} the slot, `ArrayDisk.idx`; -1 to let Unraid choose
 * @return {StorageArray} the array afterwards
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func addDiskToArray(c as Client, id as string, slot as int) {
    checkId($id, "disk");
    def input as json.Value init withVar("id", $id);
    if ($slot >= 0) {
        $input = json.set($input, "/slot", $slot);
    }
    def d as json.Value init run(
        $c,
        "addDiskToArray",
        'mutation($input: ArrayDiskInput!) { array { addDiskToArray(input: $input) { ' +
            ARRAY_FIELDS + ' } } }',
        json.set(json.map(), "/input", $input));
    return arrayAt($d, "/array/addDiskToArray");
}

/**
 * Reset a disk's read, write and error counters.
 *
 * @param c {Client} the client
 * @param id {string} the disk's id
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func clearDiskStats(c as Client, id as string) {
    checkId($id, "disk");
    def d as json.Value init run(
        $c,
        "clearDiskStats",
        'mutation($id: PrefixedID!) { array { clearArrayDiskStatistics(id: $id) } }',
        withVar("id", $id));
    if (not flag($d, "/array/clearArrayDiskStatistics")) {
        fail("clearDiskStats: the server did not clear them");
    }
}

# The fields asked for a Disk.
def const PHYSICAL_FIELDS as string init "id device name vendor type size serialNum firmwareRevision interfaceType smartStatus temperature isSpinning";

/**
 * A Disk from its object.
 *
 * @param d {json.Value} the reply
 * @param p {string} the pointer to the disk
 * @return {Disk} the disk
 */
func diskAt(d as json.Value, p as string) {
    return Disk{
        id: text($d, $p + "/id"),
        device: text($d, $p + "/device"),
        name: text($d, $p + "/name"),
        vendor: text($d, $p + "/vendor"),
        type: text($d, $p + "/type"),
        size: whole($d, $p + "/size", 0),
        serial: text($d, $p + "/serialNum"),
        firmware: text($d, $p + "/firmwareRevision"),
        interfaceType: text($d, $p + "/interfaceType"),
        smartStatus: text($d, $p + "/smartStatus"),
        temperature: real($d, $p + "/temperature", -1.0),
        spinning: flag($d, $p + "/isSpinning")
    };
}

/**
 * Every physical disk the server sees.
 *
 * @param c {Client} the client
 * @return {list of Disk} the disks
 * @throws {Error} kind `"unraid"` when the request fails
 */
export func disks(c as Client) {
    def d as json.Value init run(
        $c,
        "disks",
        'query { disks { ' + PHYSICAL_FIELDS + ' } }',
        json.map());
    def out as list of Disk init [];
    for (def i in 0..count($d, "/disks")) {
        $out[] = diskAt($d, "/disks/" + convert.toString($i));
    }
    return $out;
}

/**
 * The disks that are in no array or pool and could be added.
 *
 * @param c {Client} the client
 * @return {list of Disk} the disks
 * @throws {Error} kind `"unraid"` when the request fails
 */
export func assignableDisks(c as Client) {
    def d as json.Value init run(
        $c,
        "assignableDisks",
        'query { assignableDisks { ' + PHYSICAL_FIELDS + ' } }',
        json.map());
    def out as list of Disk init [];
    for (def i in 0..count($d, "/assignableDisks")) {
        $out[] = diskAt($d, "/assignableDisks/" + convert.toString($i));
    }
    return $out;
}

/**
 * One physical disk.
 *
 * @param c {Client} the client
 * @param id {string} its id
 * @return {Disk} the disk
 * @throws {Error} kind `"unraid"` when there is none with that id
 */
export func disk(c as Client, id as string) {
    checkId($id, "disk");
    def d as json.Value init run(
        $c,
        "disk " + shown($id),
        'query($id: PrefixedID!) { disk(id: $id) { ' + PHYSICAL_FIELDS + ' } }',
        withVar("id", $id));
    if (json.typeOf($d, "/disk") != "map") {
        fail("no disk " + shown($id));
    }
    return diskAt($d, "/disk");
}

/**
 * The user shares.
 *
 * @param c {Client} the client
 * @return {list of Share} the shares
 * @throws {Error} kind `"unraid"` when the request fails
 */
export func shares(c as Client) {
    def d as json.Value init run(
        $c,
        "shares",
        'query { shares { id name comment free used size cache include exclude } }',
        json.map());
    def out as list of Share init [];
    for (def i in 0..count($d, "/shares")) {
        def p as string init "/shares/" + convert.toString($i);
        $out[] = Share{
            id: text($d, $p + "/id"),
            name: text($d, $p + "/name"),
            comment: text($d, $p + "/comment"),
            freeKb: whole($d, $p + "/free", 0),
            usedKb: whole($d, $p + "/used", 0),
            sizeKb: whole($d, $p + "/size", 0),
            cache: flag($d, $p + "/cache"),
            includeDisks: texts($d, $p + "/include"),
            excludeDisks: texts($d, $p + "/exclude")
        };
    }
    return $out;
}

/**
 * The current or last parity check.
 *
 * @param c {Client} the client
 * @return {ParityCheck} the check
 * @throws {Error} kind `"unraid"` when the request fails
 */
export func parityStatus(c as Client) {
    def d as json.Value init run(
        $c,
        "parityStatus",
        'query { array { parityCheckStatus { ' + PARITY_FIELDS + ' } } }',
        json.map());
    return parityAt($d, "/array/parityCheckStatus");
}

/**
 * Past parity checks.
 *
 * @param c {Client} the client
 * @return {list of ParityCheck} the checks, as the server orders them
 * @throws {Error} kind `"unraid"` when the request fails
 */
export func parityHistory(c as Client) {
    def d as json.Value init run(
        $c,
        "parityHistory",
        'query { parityHistory { ' + PARITY_FIELDS + ' } }',
        json.map());
    def out as list of ParityCheck init [];
    for (def i in 0..count($d, "/parityHistory")) {
        $out[] = parityAt($d, "/parityHistory/" + convert.toString($i));
    }
    return $out;
}

/**
 * Send a parity-check mutation. Its reply is free-form JSON (the API marks
 * these mutations as work in progress), so read the outcome with
 * `parityStatus`.
 *
 * @param c {Client} the client
 * @param what {string} the operation, for messages
 * @param document {string} the mutation
 * @param variables {json.Value} its variables
 */
func parityMutation(c as Client, what as string, document as string, variables as json.Value) {
    run($c, $what, $document, $variables);
}

/**
 * Start a parity check.
 *
 * @param c {Client} the client
 * @param correct {bool} write corrections, not only count errors
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func startParityCheck(c as Client, correct as bool) {
    parityMutation(
        $c,
        "startParityCheck",
        'mutation($correct: Boolean!) { parityCheck { start(correct: $correct) } }',
        json.set(json.map(), "/correct", $correct));
}

/**
 * Pause the running parity check.
 *
 * @param c {Client} the client
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func pauseParityCheck(c as Client) {
    parityMutation($c, "pauseParityCheck", 'mutation { parityCheck { pause } }', json.map());
}

/**
 * Resume a paused parity check.
 *
 * @param c {Client} the client
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func resumeParityCheck(c as Client) {
    parityMutation($c, "resumeParityCheck", 'mutation { parityCheck { resume } }', json.map());
}

/**
 * Cancel the running parity check.
 *
 * @param c {Client} the client
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func cancelParityCheck(c as Client) {
    parityMutation($c, "cancelParityCheck", 'mutation { parityCheck { cancel } }', json.map());
}

# --- containers ---------------------------------------------------------------

# The fields asked for a Container.
def const CONTAINER_FIELDS as string init 'id names image state status autoStart webUiUrl isUpdateAvailable created ports { ip privatePort publicPort type }';

/**
 * A container's name as people use it: the first name, without Docker's
 * leading `/`.
 *
 * @param names {list of string} its names
 * @return {string} the name, "" when it has none
 */
func nameOf(names as list of string) {
    if (len($names) == 0) {
        return "";
    }
    def first as string init $names[0];
    if (strings.startsWith($first, "/")) {
        return $first[1..];
    }
    return $first;
}

/**
 * A Container from its object.
 *
 * @param d {json.Value} the reply
 * @param p {string} the pointer to the container
 * @return {Container} the container
 */
func containerAt(d as json.Value, p as string) {
    def names as list of string init texts($d, $p + "/names");
    def ports as list of Port init [];
    for (def i in 0..count($d, $p + "/ports")) {
        def q as string init $p + "/ports/" + convert.toString($i);
        $ports[] = Port{
            ip: text($d, $q + "/ip"),
            privatePort: whole($d, $q + "/privatePort", 0),
            publicPort: whole($d, $q + "/publicPort", 0),
            type: text($d, $q + "/type")
        };
    }
    return Container{
        id: text($d, $p + "/id"),
        name: nameOf($names),
        names: $names,
        image: text($d, $p + "/image"),
        state: text($d, $p + "/state"),
        status: text($d, $p + "/status"),
        autoStart: flag($d, $p + "/autoStart"),
        webUiUrl: text($d, $p + "/webUiUrl"),
        updateAvailable: flag($d, $p + "/isUpdateAvailable"),
        created: whole($d, $p + "/created", 0),
        ports: $ports
    };
}

/**
 * The Containers of a list field.
 *
 * @param d {json.Value} the reply
 * @param p {string} the pointer to the list
 * @return {list of Container} the containers
 */
func containersAt(d as json.Value, p as string) {
    def out as list of Container init [];
    for (def i in 0..count($d, $p)) {
        $out[] = containerAt($d, $p + "/" + convert.toString($i));
    }
    return $out;
}

/**
 * Every Docker container, running or not.
 *
 * @param c {Client} the client
 * @return {list of Container} the containers
 * @throws {Error} kind `"unraid"` when the request fails
 */
export func containers(c as Client) {
    def d as json.Value init run(
        $c,
        "containers",
        'query { docker { containers { ' + CONTAINER_FIELDS + ' } } }',
        json.map());
    return containersAt($d, "/docker/containers");
}

/**
 * One container.
 *
 * @param c {Client} the client
 * @param id {string} its id
 * @return {Container} the container
 * @throws {Error} kind `"unraid"` when there is none with that id
 */
export func container(c as Client, id as string) {
    checkId($id, "container");
    def d as json.Value init run(
        $c,
        "container " + shown($id),
        'query($id: PrefixedID!) { docker { container(id: $id) { ' + CONTAINER_FIELDS + ' } } }',
        withVar("id", $id));
    if (json.typeOf($d, "/docker/container") != "map") {
        fail("no container " + shown($id));
    }
    return containerAt($d, "/docker/container");
}

/**
 * The container with this name, with or without Docker's leading `/`.
 *
 * @param c {Client} the client
 * @param name {string} its name, e.g. `plex`
 * @return {Container} the container
 * @throws {Error} kind `"unraid"` when none has that name
 */
export func containerByName(c as Client, name as string) {
    def wanted as string init $name;
    if (strings.startsWith($wanted, "/")) {
        $wanted = $wanted[1..];
    }
    for (def ct in containers($c)) {
        for (def n in $ct.names) {
            if ($n == $wanted or $n == "/" + $wanted) {
                return $ct;
            }
        }
    }
    fail("no container named " + shown($name));
}

/**
 * Send one of the container mutations that answer with the container.
 *
 * @param c {Client} the client
 * @param verb {string} the mutation under `docker`, e.g. `start`
 * @param what {string} the operation, for messages
 * @param id {string} the container
 * @return {Container} the container afterwards
 */
func containerAction(c as Client, verb as string, what as string, id as string) {
    checkId($id, "container");
    def d as json.Value init run(
        $c,
        $what + " " + shown($id),
        'mutation($id: PrefixedID!) { docker { ' + $verb + '(id: $id) { ' + CONTAINER_FIELDS +
            ' } } }',
        withVar("id", $id));
    return containerAt($d, "/docker/" + $verb);
}

/**
 * Start a container.
 *
 * @param c {Client} the client
 * @param id {string} its id
 * @return {Container} the container afterwards
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func startContainer(c as Client, id as string) {
    return containerAction($c, "start", "startContainer", $id);
}

/**
 * Stop a container.
 *
 * @param c {Client} the client
 * @param id {string} its id
 * @return {Container} the container afterwards
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func stopContainer(c as Client, id as string) {
    return containerAction($c, "stop", "stopContainer", $id);
}

/**
 * Restart a container.
 *
 * @param c {Client} the client
 * @param id {string} its id
 * @return {Container} the container afterwards
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func restartContainer(c as Client, id as string) {
    return containerAction($c, "restart", "restartContainer", $id);
}

/**
 * Pause a container.
 *
 * @param c {Client} the client
 * @param id {string} its id
 * @return {Container} the container afterwards
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func pauseContainer(c as Client, id as string) {
    return containerAction($c, "pause", "pauseContainer", $id);
}

/**
 * Resume a paused container.
 *
 * @param c {Client} the client
 * @param id {string} its id
 * @return {Container} the container afterwards
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func unpauseContainer(c as Client, id as string) {
    return containerAction($c, "unpause", "unpauseContainer", $id);
}

/**
 * Pull a container's image again and recreate it, if a newer image exists.
 *
 * @param c {Client} the client
 * @param id {string} its id
 * @return {Container} the container afterwards
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func updateContainer(c as Client, id as string) {
    return containerAction($c, "updateContainer", "updateContainer", $id);
}

/**
 * Update every container that has a newer image.
 *
 * @param c {Client} the client
 * @return {list of Container} the containers afterwards
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func updateAllContainers(c as Client) {
    def d as json.Value init run(
        $c,
        "updateAllContainers",
        'mutation { docker { updateAllContainers { ' + CONTAINER_FIELDS + ' } } }',
        json.map());
    return containersAt($d, "/docker/updateAllContainers");
}

/**
 * Remove a container.
 *
 * @param c {Client} the client
 * @param id {string} its id
 * @param withImage {bool} remove its image too
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func removeContainer(c as Client, id as string, withImage as bool) {
    checkId($id, "container");
    def vars as json.Value init json.set(withVar("id", $id), "/withImage", $withImage);
    def d as json.Value init run(
        $c,
        "removeContainer " + shown($id),
        'mutation($id: PrefixedID!, $withImage: Boolean) { docker { removeContainer(id: $id, withImage: $withImage) } }',
        $vars);
    if (not flag($d, "/docker/removeContainer")) {
        fail("removeContainer " + shown($id) + ": the server did not remove it");
    }
}

/**
 * Read a container's log.
 *
 * @param c {Client} the client
 * @param id {string} its id
 * @param since {string} an ISO 8601 time, or the `cursor` of an earlier read; "" for no lower bound
 * @param tail {int} only the last lines; 0 for all
 * @return {ContainerLogs} the lines and the cursor to continue from
 * @throws {Error} kind `"unraid"` when the request fails
 */
export func containerLogs(c as Client, id as string, since as string, tail as int) {
    checkId($id, "container");
    def vars as json.Value init withVar("id", $id);
    if ($since != "") {
        $vars = json.set($vars, "/since", $since);
    }
    if ($tail > 0) {
        $vars = json.set($vars, "/tail", $tail);
    }
    def d as json.Value init run(
        $c,
        "containerLogs " + shown($id),
        'query($id: PrefixedID!, $since: DateTime, $tail: Int) { docker { logs(id: $id, since: $since, tail: $tail) { lines { timestamp message } cursor } } }',
        $vars);
    def lines as list of LogLine init [];
    for (def i in 0..count($d, "/docker/logs/lines")) {
        def p as string init "/docker/logs/lines/" + convert.toString($i);
        $lines[] = LogLine{
            timestamp: text($d, $p + "/timestamp"),
            message: text($d, $p + "/message")
        };
    }
    return ContainerLogs{lines: $lines, cursor: text($d, "/docker/logs/cursor")};
}

/**
 * Set which containers start with the array, in which order and with what
 * delay. The order of `entries` is the start order.
 *
 * @param c {Client} the client
 * @param entries {list of Autostart} one per container
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func setAutostart(c as Client, entries as list of Autostart) {
    def items as json.Value init json.list();
    for (def e in $entries) {
        checkId($e.id, "container");
        def item as json.Value init json.set(withVar("id", $e.id), "/autoStart", $e.autoStart);
        $items = json.append($items, "", json.set($item, "/wait", $e.wait));
    }
    def d as json.Value init run(
        $c,
        "setAutostart",
        'mutation($entries: [DockerAutostartEntryInput!]!) { docker { updateAutostartConfiguration(entries: $entries) } }',
        json.set(json.map(), "/entries", $items));
    if (not flag($d, "/docker/updateAutostartConfiguration")) {
        fail("setAutostart: the server did not apply it");
    }
}

# --- virtual machines ---------------------------------------------------------

/**
 * Every virtual machine.
 *
 * @param c {Client} the client
 * @return {list of Vm} the machines; empty when VMs are disabled
 * @throws {Error} kind `"unraid"` when the request fails
 */
export func vms(c as Client) {
    def d as json.Value init run(
        $c,
        "vms",
        'query { vms { domains { id name state } } }',
        json.map());
    def out as list of Vm init [];
    for (def i in 0..count($d, "/vms/domains")) {
        def p as string init "/vms/domains/" + convert.toString($i);
        $out[] = Vm{
            id: text($d, $p + "/id"),
            name: text($d, $p + "/name"),
            state: text($d, $p + "/state")
        };
    }
    return $out;
}

/**
 * The idle part of an id: Unraid prefixes output ids with `<server>:` and
 * accepts them with or without it.
 *
 * @param id {string} an id
 * @return {string} the part after the last `:`
 */
func bareId(id as string) {
    def at as int init strings.lastIndexOf($id, ":");
    if ($at < 0) {
        return $id;
    }
    return $id[$at + 1..];
}

/**
 * One virtual machine.
 *
 * @param c {Client} the client
 * @param id {string} its id, with or without the server prefix
 * @return {Vm} the machine
 * @throws {Error} kind `"unraid"` when there is none with that id
 */
export func vm(c as Client, id as string) {
    checkId($id, "VM");
    for (def m in vms($c)) {
        if ($m.id == $id or bareId($m.id) == bareId($id)) {
            return $m;
        }
    }
    fail("no VM " + shown($id));
}

/**
 * The virtual machine with this name.
 *
 * @param c {Client} the client
 * @param name {string} its name
 * @return {Vm} the machine
 * @throws {Error} kind `"unraid"` when none has that name
 */
export func vmByName(c as Client, name as string) {
    for (def m in vms($c)) {
        if ($m.name == $name) {
            return $m;
        }
    }
    fail("no VM named " + shown($name));
}

/**
 * Send one of the VM mutations, which answer true or false.
 *
 * @param c {Client} the client
 * @param verb {string} the mutation under `vm`, e.g. `start`
 * @param what {string} the operation, for messages
 * @param id {string} the machine
 */
func vmAction(c as Client, verb as string, what as string, id as string) {
    checkId($id, "VM");
    def d as json.Value init run(
        $c,
        $what + " " + shown($id),
        'mutation($id: PrefixedID!) { vm { ' + $verb + '(id: $id) } }',
        withVar("id", $id));
    if (not flag($d, "/vm/" + $verb)) {
        fail($what + " " + shown($id) + ": the server did not do it");
    }
}

/**
 * Start a virtual machine. It returns once libvirt took the request; use
 * `waitVm` for the state.
 *
 * @param c {Client} the client
 * @param id {string} its id
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func startVm(c as Client, id as string) {
    vmAction($c, "start", "startVm", $id);
}

/**
 * Ask a virtual machine to shut down (ACPI). The guest may take its time or
 * ignore it; `forceStopVm` does not ask.
 *
 * @param c {Client} the client
 * @param id {string} its id
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func stopVm(c as Client, id as string) {
    vmAction($c, "stop", "stopVm", $id);
}

/**
 * Power a virtual machine off at once.
 *
 * @param c {Client} the client
 * @param id {string} its id
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func forceStopVm(c as Client, id as string) {
    vmAction($c, "forceStop", "forceStopVm", $id);
}

/**
 * Pause a virtual machine.
 *
 * @param c {Client} the client
 * @param id {string} its id
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func pauseVm(c as Client, id as string) {
    vmAction($c, "pause", "pauseVm", $id);
}

/**
 * Resume a paused virtual machine.
 *
 * @param c {Client} the client
 * @param id {string} its id
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func resumeVm(c as Client, id as string) {
    vmAction($c, "resume", "resumeVm", $id);
}

/**
 * Ask a virtual machine to reboot.
 *
 * @param c {Client} the client
 * @param id {string} its id
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func rebootVm(c as Client, id as string) {
    vmAction($c, "reboot", "rebootVm", $id);
}

/**
 * Reset a virtual machine, as the reset button would.
 *
 * @param c {Client} the client
 * @param id {string} its id
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func resetVm(c as Client, id as string) {
    vmAction($c, "reset", "resetVm", $id);
}

/**
 * Wait until a virtual machine reports a state, checking every `pollMs`.
 *
 * @param c {Client} the client
 * @param id {string} its id
 * @param state {string} the state to wait for, one of `VM_STATES`
 * @param timeoutMs {int} how long to wait at most
 * @return {Vm} the machine in that state
 * @throws {Error} kind `"unraid"` on an unknown state, or when time runs out
 */
export func waitVm(c as Client, id as string, state as string, timeoutMs as int) {
    if (not lists.contains(VM_STATES, $state)) {
        fail("waitVm: unknown state " + shown($state));
    }
    def pause as int init $c.pollMs;
    if ($pause <= 0) {
        $pause = 1000;
    }
    def deadline as float init time.unixNanos(time.utc()) / 1000000.0 + $timeoutMs;
    while (true) {
        def m as Vm init vm($c, $id);
        if ($m.state == $state) {
            return $m;
        }
        if (time.unixNanos(time.utc()) / 1000000.0 + $pause > $deadline) {
            fail("waitVm " + shown($id) + ": still " + $m.state + " after " +
                convert.toString($timeoutMs) + " ms");
        }
        time.sleep(time.fromMilliseconds($pause));
    }
}

# --- notifications ------------------------------------------------------------

# The fields asked for a Notification.
def const NOTIFICATION_FIELDS as string init "id title subject description importance link type timestamp";

/**
 * Check an importance level.
 *
 * @param importance {string} the level
 * @param blankOk {bool} whether "" (any level) is allowed
 */
func checkImportance(importance as string, blankOk as bool) {
    if ($importance == "" and $blankOk) {
        return;
    }
    if (not lists.contains(IMPORTANCE, $importance)) {
        fail("importance is INFO, WARNING or ALERT, got " + shown($importance));
    }
}

/**
 * A Notification from its object.
 *
 * @param d {json.Value} the reply
 * @param p {string} the pointer to the notification
 * @return {Notification} the notification
 */
func notificationAt(d as json.Value, p as string) {
    return Notification{
        id: text($d, $p + "/id"),
        title: text($d, $p + "/title"),
        subject: text($d, $p + "/subject"),
        description: text($d, $p + "/description"),
        importance: text($d, $p + "/importance"),
        link: text($d, $p + "/link"),
        archived: text($d, $p + "/type") == "ARCHIVE",
        timestamp: text($d, $p + "/timestamp")
    };
}

/**
 * A page of notifications.
 *
 * @param c {Client} the client
 * @param archived {bool} archived ones rather than unread ones
 * @param importance {string} `INFO`, `WARNING` or `ALERT`; "" for all
 * @param offset {int} how many to skip
 * @param limit {int} how many at most
 * @return {list of Notification} the notifications
 * @throws {Error} kind `"unraid"` on a bad importance, offset or limit, or when the request fails
 */
export func notifications(
    c as Client,
    archived as bool,
    importance as string,
    offset as int,
    limit as int) {
    checkImportance($importance, true);
    if ($offset < 0 or $limit < 1) {
        fail("notifications: offset is 0 or more and limit 1 or more");
    }
    def kind as string init "UNREAD";
    if ($archived) {
        $kind = "ARCHIVE";
    }
    def filter as json.Value init json.set(json.map(), "/type", $kind);
    $filter = json.set(json.set($filter, "/offset", $offset), "/limit", $limit);
    if ($importance != "") {
        $filter = json.set($filter, "/importance", $importance);
    }
    def d as json.Value init run(
        $c,
        "notifications",
        'query($filter: NotificationFilter!) { notifications { list(filter: $filter) { ' +
            NOTIFICATION_FIELDS + ' } } }',
        json.set(json.map(), "/filter", $filter));
    def out as list of Notification init [];
    for (def i in 0..count($d, "/notifications/list")) {
        $out[] = notificationAt($d, "/notifications/list/" + convert.toString($i));
    }
    return $out;
}

/**
 * NotificationCounts from its object.
 *
 * @param d {json.Value} the reply
 * @param p {string} the pointer to the counts
 * @return {NotificationCounts} the counts
 */
func countsAt(d as json.Value, p as string) {
    return NotificationCounts{
        info: whole($d, $p + "/info", 0),
        warning: whole($d, $p + "/warning", 0),
        alert: whole($d, $p + "/alert", 0),
        total: whole($d, $p + "/total", 0)
    };
}

/**
 * How many notifications there are, unread and archived.
 *
 * @param c {Client} the client
 * @return {NotificationOverview} the counts
 * @throws {Error} kind `"unraid"` when the request fails
 */
export func notificationOverview(c as Client) {
    def d as json.Value init run(
        $c,
        "notificationOverview",
        'query { notifications { overview { unread { info warning alert total } archive { info warning alert total } } } }',
        json.map());
    return NotificationOverview{
        unread: countsAt($d, "/notifications/overview/unread"),
        archived: countsAt($d, "/notifications/overview/archive")
    };
}

/**
 * The input of a new notification.
 *
 * @param title {string} its title
 * @param subject {string} its subject
 * @param description {string} its text
 * @param importance {string} `INFO`, `WARNING` or `ALERT`
 * @param link {string} a link, "" for none
 * @return {json.Value} the variables
 */
func notificationInput(
    title as string,
    subject as string,
    description as string,
    importance as string,
    link as string) {
    checkImportance($importance, false);
    def input as json.Value init json.map();
    $input = json.set($input, "/title", $title);
    $input = json.set($input, "/subject", $subject);
    $input = json.set($input, "/description", $description);
    $input = json.set($input, "/importance", $importance);
    if ($link != "") {
        $input = json.set($input, "/link", $link);
    }
    return json.set(json.map(), "/input", $input);
}

/**
 * Raise a notification on the server, as Unraid's own alerts are.
 *
 * @param c {Client} the client
 * @param title {string} its title
 * @param subject {string} its subject
 * @param description {string} its text
 * @param importance {string} `INFO`, `WARNING` or `ALERT`
 * @param link {string} a link, "" for none
 * @return {Notification} the notification
 * @throws {Error} kind `"unraid"` on a bad importance, or when the server refuses
 */
export func notify(
    c as Client,
    title as string,
    subject as string,
    description as string,
    importance as string,
    link as string) {
    def d as json.Value init run(
        $c,
        "notify",
        'mutation($input: NotificationData!) { createNotification(input: $input) { ' +
            NOTIFICATION_FIELDS + ' } }',
        notificationInput($title, $subject, $description, $importance, $link));
    return notificationAt($d, "/createNotification");
}

/**
 * Raise a notification unless an unread one with the same content exists,
 * so a check that runs every few minutes does not pile up copies.
 *
 * @param c {Client} the client
 * @param title {string} its title
 * @param subject {string} its subject
 * @param description {string} its text
 * @param importance {string} `INFO`, `WARNING` or `ALERT`
 * @param link {string} a link, "" for none
 * @return {bool} whether a notification was raised
 * @throws {Error} kind `"unraid"` on a bad importance, or when the server refuses
 */
export func notifyOnce(
    c as Client,
    title as string,
    subject as string,
    description as string,
    importance as string,
    link as string) {
    def d as json.Value init run(
        $c,
        "notifyOnce",
        'mutation($input: NotificationData!) { notifyIfUnique(input: $input) { id } }',
        notificationInput($title, $subject, $description, $importance, $link));
    return json.typeOf($d, "/notifyIfUnique") == "map";
}

/**
 * Archive a notification.
 *
 * @param c {Client} the client
 * @param id {string} its id
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func archiveNotification(c as Client, id as string) {
    checkId($id, "notification");
    run(
        $c,
        "archiveNotification " + shown($id),
        'mutation($id: PrefixedID!) { archiveNotification(id: $id) { id } }',
        withVar("id", $id));
}

/**
 * Move an archived notification back to the unread ones.
 *
 * @param c {Client} the client
 * @param id {string} its id
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func unarchiveNotification(c as Client, id as string) {
    checkId($id, "notification");
    def ids as json.Value init json.append(json.list(), "", $id);
    run(
        $c,
        "unarchiveNotification " + shown($id),
        'mutation($ids: [PrefixedID!]!) { unarchiveNotifications(ids: $ids) { unread { total } } }',
        json.set(json.map(), "/ids", $ids));
}

/**
 * Delete a notification.
 *
 * @param c {Client} the client
 * @param id {string} its id
 * @param archived {bool} whether it is an archived one
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func deleteNotification(c as Client, id as string, archived as bool) {
    checkId($id, "notification");
    def kind as string init "UNREAD";
    if ($archived) {
        $kind = "ARCHIVE";
    }
    run(
        $c,
        "deleteNotification " + shown($id),
        'mutation($id: PrefixedID!, $type: NotificationType!) { deleteNotification(id: $id, type: $type) { unread { total } } }',
        json.set(withVar("id", $id), "/type", $kind));
}

/**
 * Archive every unread notification, or those of one importance.
 *
 * @param c {Client} the client
 * @param importance {string} `INFO`, `WARNING` or `ALERT`; "" for all
 * @throws {Error} kind `"unraid"` on a bad importance, or when the server refuses
 */
export func archiveAll(c as Client, importance as string) {
    checkImportance($importance, true);
    def vars as json.Value init json.map();
    if ($importance != "") {
        $vars = withVar("importance", $importance);
    }
    run(
        $c,
        "archiveAll",
        'mutation($importance: NotificationImportance) { archiveAll(importance: $importance) { unread { total } } }',
        $vars);
}

# --- administration -----------------------------------------------------------

/**
 * The API keys. Their secrets are not listed: Unraid shows a key once, when
 * it is made.
 *
 * @param c {Client} the client
 * @return {list of ApiKey} the keys, `key` ""
 * @throws {Error} kind `"unraid"` when the request fails
 */
export func apiKeys(c as Client) {
    def d as json.Value init run(
        $c,
        "apiKeys",
        'query { apiKeys { id name description roles createdAt } }',
        json.map());
    def out as list of ApiKey init [];
    for (def i in 0..count($d, "/apiKeys")) {
        def p as string init "/apiKeys/" + convert.toString($i);
        $out[] = ApiKey{
            id: text($d, $p + "/id"),
            name: text($d, $p + "/name"),
            description: text($d, $p + "/description"),
            key: "",
            roles: texts($d, $p + "/roles"),
            createdAt: text($d, $p + "/createdAt")
        };
    }
    return $out;
}

/**
 * Make an API key. Its secret is in `key` of the result, and only there:
 * keep it.
 *
 * @param c {Client} the client
 * @param name {string} its name
 * @param description {string} what it is for, "" for none
 * @param roles {list of string} its roles, from `ROLES`; `VIEWER` reads everything, `ADMIN` may do anything
 * @return {ApiKey} the key, secret included
 * @throws {Error} kind `"unraid"` on an unknown role, or when the server refuses
 */
export func createApiKey(
    c as Client,
    name as string,
    description as string,
    roles as list of string) {
    if (strings.trim($name) == "") {
        fail("createApiKey: the name is empty");
    }
    def roleList as json.Value init json.list();
    for (def r in $roles) {
        if (not lists.contains(ROLES, $r)) {
            fail("createApiKey: unknown role " + shown($r));
        }
        $roleList = json.append($roleList, "", $r);
    }
    def input as json.Value init json.set(
        json.set(json.map(), "/name", $name),
        "/roles",
        $roleList);
    if ($description != "") {
        $input = json.set($input, "/description", $description);
    }
    def d as json.Value init run(
        $c,
        "createApiKey " + shown($name),
        'mutation($input: CreateApiKeyInput!) { apiKey { create(input: $input) { id name description key roles createdAt } } }',
        json.set(json.map(), "/input", $input));
    def p as string init "/apiKey/create";
    return ApiKey{
        id: text($d, $p + "/id"),
        name: text($d, $p + "/name"),
        description: text($d, $p + "/description"),
        key: text($d, $p + "/key"),
        roles: texts($d, $p + "/roles"),
        createdAt: text($d, $p + "/createdAt")
    };
}

/**
 * Delete an API key. A client using it is refused from then on.
 *
 * @param c {Client} the client
 * @param id {string} its id
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func deleteApiKey(c as Client, id as string) {
    checkId($id, "API key");
    def input as json.Value init json.set(json.map(), "/ids", json.append(json.list(), "", $id));
    def d as json.Value init run(
        $c,
        "deleteApiKey " + shown($id),
        'mutation($input: DeleteApiKeyInput!) { apiKey { delete(input: $input) } }',
        json.set(json.map(), "/input", $input));
    if (not flag($d, "/apiKey/delete")) {
        fail("deleteApiKey " + shown($id) + ": the server did not delete it");
    }
}

/**
 * The installed plugins.
 *
 * @param c {Client} the client
 * @return {list of Plugin} the plugins
 * @throws {Error} kind `"unraid"` when the request fails
 */
export func plugins(c as Client) {
    def d as json.Value init run($c, "plugins", 'query { plugins { name version } }', json.map());
    def out as list of Plugin init [];
    for (def i in 0..count($d, "/plugins")) {
        def p as string init "/plugins/" + convert.toString($i);
        $out[] = Plugin{name: text($d, $p + "/name"), version: text($d, $p + "/version")};
    }
    return $out;
}

/**
 * The USB flash device Unraid boots from.
 *
 * @param c {Client} the client
 * @return {Flash} the device
 * @throws {Error} kind `"unraid"` when the request fails
 */
export func flash(c as Client) {
    def d as json.Value init run(
        $c,
        "flash",
        'query { flash { guid vendor product } }',
        json.map());
    return Flash{
        guid: text($d, "/flash/guid"),
        vendor: text($d, "/flash/vendor"),
        product: text($d, "/flash/product")
    };
}

/**
 * Copy the flash device to an rclone remote. The copy runs on the server;
 * the result names its job.
 *
 * @param c {Client} the client
 * @param remoteName {string} the remote, from `rcloneRemotes`
 * @param sourcePath {string} what to copy, e.g. `/boot`
 * @param destinationPath {string} where on the remote
 * @return {FlashBackup} the started backup
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func backupFlash(
    c as Client,
    remoteName as string,
    sourcePath as string,
    destinationPath as string) {
    def input as json.Value init json.set(json.map(), "/remoteName", $remoteName);
    $input = json.set(
        json.set($input, "/sourcePath", $sourcePath),
        "/destinationPath",
        $destinationPath);
    def d as json.Value init run(
        $c,
        "backupFlash",
        'mutation($input: InitiateFlashBackupInput!) { initiateFlashBackup(input: $input) { status jobId } }',
        json.set(json.map(), "/input", $input));
    return FlashBackup{
        status: text($d, "/initiateFlashBackup/status"),
        jobId: text($d, "/initiateFlashBackup/jobId")
    };
}

/**
 * The rclone remotes set up on the server.
 *
 * @param c {Client} the client
 * @return {list of RcloneRemote} the remotes
 * @throws {Error} kind `"unraid"` when the request fails
 */
export func rcloneRemotes(c as Client) {
    def d as json.Value init run(
        $c,
        "rcloneRemotes",
        'query { rclone { remotes { name type } } }',
        json.map());
    def out as list of RcloneRemote init [];
    for (def i in 0..count($d, "/rclone/remotes")) {
        def p as string init "/rclone/remotes/" + convert.toString($i);
        $out[] = RcloneRemote{name: text($d, $p + "/name"), type: text($d, $p + "/type")};
    }
    return $out;
}

/**
 * Set up an rclone remote.
 *
 * @param c {Client} the client
 * @param name {string} its name
 * @param type {string} its backend, e.g. `s3`
 * @param parameters {json.Value} the backend's settings, an object of rclone's option names
 * @return {RcloneRemote} the remote
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func createRcloneRemote(
    c as Client,
    name as string,
    type as string,
    parameters as json.Value) {
    def input as json.Value init json.set(json.set(json.map(), "/name", $name), "/type", $type);
    $input = json.set($input, "/parameters", $parameters);
    def d as json.Value init run(
        $c,
        "createRcloneRemote " + shown($name),
        'mutation($input: CreateRCloneRemoteInput!) { rclone { createRCloneRemote(input: $input) { name type } } }',
        json.set(json.map(), "/input", $input));
    return RcloneRemote{
        name: text($d, "/rclone/createRCloneRemote/name"),
        type: text($d, "/rclone/createRCloneRemote/type")
    };
}

/**
 * Delete an rclone remote.
 *
 * @param c {Client} the client
 * @param name {string} its name
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func deleteRcloneRemote(c as Client, name as string) {
    def d as json.Value init run(
        $c,
        "deleteRcloneRemote " + shown($name),
        'mutation($input: DeleteRCloneRemoteInput!) { rclone { deleteRCloneRemote(input: $input) } }',
        json.set(json.map(), "/input", withVar("name", $name)));
    if (not flag($d, "/rclone/deleteRCloneRemote")) {
        fail("deleteRcloneRemote " + shown($name) + ": the server did not delete it");
    }
}

/**
 * Rename the server, or change its description.
 *
 * @param c {Client} the client
 * @param name {string} the new name
 * @param comment {string} the new description
 * @throws {Error} kind `"unraid"` when the server refuses
 */
export func setServerIdentity(c as Client, name as string, comment as string) {
    if (strings.trim($name) == "") {
        fail("setServerIdentity: the name is empty");
    }
    run(
        $c,
        "setServerIdentity",
        'mutation($name: String!, $comment: String) { updateServerIdentity(name: $name, comment: $comment) { name } }',
        json.set(withVar("name", $name), "/comment", $comment));
}
