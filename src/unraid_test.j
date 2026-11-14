# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * White-box tests for unraid: jennifer test src/unraid_test.j
 *
 * The parsing helpers are tested directly. The requests go to an `httpd`
 * server on a loopback port that answers canned GraphQL replies in order and
 * hands back the document, variables and API key it received.
 */
use httpd;
use task;
use testing;

/** A canned reply. */
def struct Reply {
    status as int,
    body as string
};

/** One request as the fake server saw it. */
def struct Seen {
    document as string,
    variables as json.Value,
    apiKey as string,
    accept as string
};

/** A running fake server. */
def struct Fake {
    srv as httpd.Server,
    c as Client,
    t as task of list of Seen
};

/**
 * Answer one request per reply, in order.
 *
 * @param srv {httpd.Server} the listening server
 * @param replies {list of Reply} the replies
 * @return {list of Seen} the requests
 */
func serve(srv as httpd.Server, replies as list of Reply) {
    def seen as list of Seen init [];
    for (def r in $replies) {
        def req as httpd.Request init httpd.accept($srv);
        def body as json.Value init json.decode(convert.stringFromBytes("utf-8", httpd.body($req)));
        def vars as json.Value init json.map();
        if (json.typeOf($body, "/variables") == "map") {
            $vars = json.get($body, "/variables");
        }
        $seen[] = Seen{
            document: json.asString($body, "/query"),
            variables: $vars,
            apiKey: httpd.header($req, "x-api-key"),
            accept: httpd.header($req, "Accept")
        };
        httpd.setHeader($req, "Content-Type", "application/json");
        httpd.respond($req, $r.status, $r.body);
    }
    return $seen;
}

/**
 * Start a fake server that gives these replies, and a client for it.
 *
 * @param replies {list of Reply} the replies
 * @return {Fake} the server and the client
 */
func fake(replies as list of Reply) {
    def srv as httpd.Server init httpd.listen("127.0.0.1:0");
    def t as task of list of Seen init spawn {
        return serve($srv, $replies);
    };
    def c as Client init withApiKey(
        client("http://" + httpd.address($srv) + "/graphql"),
        "test-key_1");
    return Fake{srv: $srv, c: withPollInterval($c, 10), t: $t};
}

/**
 * How long `finish` waits for the fake server to have answered every reply,
 * in milliseconds. `httpd.accept` has no timeout of its own, so a client that
 * fails before sending a request it was meant to send would otherwise leave
 * the server, and the whole suite, waiting forever.
 */
def const SERVE_TIMEOUT_MS as int init 5000;

/**
 * Stop a fake server, failing the test when it did not receive one request per
 * reply within `SERVE_TIMEOUT_MS`.
 *
 * @param f {Fake} the server
 * @return {list of Seen} what it received
 */
func finish(f as Fake) {
    return finishWithin($f, SERVE_TIMEOUT_MS);
}

/**
 * Stop a fake server, failing the test when it did not receive one request per
 * reply within `ms`.
 *
 * On a timeout the server is shut down, which wakes its parked `accept`, and
 * its task is discarded, so the run can go on to the next test.
 *
 * @param f {Fake} the server
 * @param ms {int} how long to wait, in milliseconds
 * @return {list of Seen} what it received
 * @throws {Error} kind `"assertion"` when the server was still waiting for a
 *     request; anything the server's task threw, after the same cleanup
 */
func finishWithin(f as Fake, ms as int) {
    def seen as list of Seen init [];
    try {
        $seen = task.waitTimeout($f.t, $ms);
    } catch (e) {
        httpd.shutdown($f.srv);
        task.discard($f.t);
        if ($e.kind == "timeout") {
            throw Error{
                kind: "assertion",
                message: "the fake server was still waiting for a request after " +
                    convert.toString($ms) + " ms: the client sent " +
                    "fewer requests than the test gave replies"
            };
        }
        throw $e;
    }
    httpd.shutdown($f.srv);
    return $seen;
}

/**
 * A reply carrying `data`.
 *
 * @param data {string} the JSON of `data`
 * @return {Reply} the reply
 */
func ok(data as string) {
    return Reply{status: 200, body: '{"data":' + $data + '}'};
}

/**
 * The message of an error a function throws, checking its kind.
 *
 * @param e {UnraidError} the error
 * @return {string} its message
 */
func messageOf(e as UnraidError) {
    testing.assertEqual($e.kind, ERROR_KIND);
    return $e.message;
}

# --- helpers ------------------------------------------------------------------

func testEndpointOf() {
    testing.assertEqual(endpointOf("tower.local"), "https://tower.local/graphql");
    testing.assertEqual(endpointOf(" tower.local:8443 "), "https://tower.local:8443/graphql");
    testing.assertEqual(endpointOf("https://tower.local/"), "https://tower.local/graphql");
    testing.assertEqual(endpointOf("http://10.0.0.5/graphql"), "http://10.0.0.5/graphql");
    testing.assertEqual(endpointOf("https://[::1]:443"), "https://[::1]:443/graphql");
    testing.assertEqual(client("tower").pollMs, 1000);
    for (def bad in [
        "",
        "ftp://tower",
        "https://user:pw@tower/",
        "tower local",
        "https://tower?x=1",
        "tower#f"
    ]) {
        def failed as bool init false;
        try {
            endpointOf($bad);
        } catch (e) {
            $failed = true;
            messageOf($e);
        }
        testing.assertTrue($failed);
    }
}

func testClientSettings() {
    def c as Client init withRetries(withTimeout(withInsecure(client("tower")), 5000), 2);
    testing.assertTrue($c.insecure);
    $c = withCaCert($c, convert.bytesFromString("utf-8", "PEM"));
    testing.assertFalse($c.insecure);
    $c = withApiKey($c, "abc-DEF_123");
    def g as graphql.Client init gql($c);
    testing.assertEqual($g.rest.headers["x-api-key"], "abc-DEF_123");
    testing.assertEqual($g.rest.options.timeoutMs, 5000);
    testing.assertEqual($g.rest.options.maxRetries, 2);
    def refused as bool init false;
    try {
        withApiKey($c, "secret with space");
    } catch (e) {
        $refused = true;
        testing.assertFalse(strings.contains(messageOf($e), "secret"));
    }
    testing.assertTrue($refused);
}

func testReaders() {
    def v as json.Value init json.decode('{"n":5,"s":"12","f":1.5,"x":"no","z":null,"b":true,"l":["a","b"]}');
    testing.assertEqual(whole($v, "/n", -1), 5);
    testing.assertEqual(whole($v, "/s", -1), 12);
    testing.assertEqual(whole($v, "/f", -1), 1);
    testing.assertEqual(whole($v, "/x", -1), -1);
    testing.assertEqual(whole($v, "/z", -1), -1);
    testing.assertEqual(whole($v, "/missing", 7), 7);
    testing.assertEqual(whole(json.decode('{"f":1e30}'), "/f", -1), -1);
    testing.assertEqual(real($v, "/s", 0.0), 12.0);
    testing.assertEqual(real($v, "/z", -1.0), -1.0);
    testing.assertEqual(text($v, "/n"), "5");
    testing.assertEqual(text($v, "/z"), "");
    testing.assertTrue(flag($v, "/b"));
    testing.assertFalse(flag($v, "/z"));
    testing.assertEqual(texts($v, "/l"), ["a", "b"]);
    testing.assertEqual(texts($v, "/z"), []);
    testing.assertEqual(count($v, "/l"), 2);
    testing.assertEqual(nameOf(["/plex", "/plex-alias"]), "plex");
    testing.assertEqual(nameOf([]), "");
    testing.assertEqual(bareId("abc:123-uuid"), "123-uuid");
    testing.assertEqual(plain("a\nb", 10), "a?b");
    testing.assertEqual(shown(strings.repeat("x", 70)), "\"" + strings.repeat("x", 60) + "...\"");
}

# --- transport and errors -----------------------------------------------------

func testQuerySendsKeyAndDocument() {
    def f as Fake init fake([ok('{"online":true}'), ok('{"x":1}')]);
    testing.assertTrue(online($f.c));
    def d as json.Value init query($f.c, 'query($a: Int) { x }', json.set(json.map(), "/a", 3));
    testing.assertEqual(json.asInt($d, "/x"), 1);
    def seen as list of Seen init finish($f);
    testing.assertEqual($seen[0].document, 'query { online }');
    testing.assertEqual($seen[0].apiKey, "test-key_1");
    testing.assertTrue(strings.startsWith($seen[0].accept, "application/graphql-response+json"));
    testing.assertEqual(json.asInt($seen[1].variables, "/a"), 3);
}

func testErrorsAreUnraid() {
    def f as Fake init fake([
        ok('null'),
        Reply{
            status: 200,
            body: '{"data":null,"errors":[{"message":"Forbidden resource","extensions":{"code":"FORBIDDEN"}}]}'
        },
        Reply{
            status: 401,
            body: '{"errors":[{"message":"No API key provided","extensions":{"code":"UNAUTHENTICATED"}}]}'
        },
        Reply{status: 502, body: "<html>bad gateway</html>"}
    ]);
    def messages as list of string init [];
    def statuses as list of int init [];
    def codes as list of string init [];
    for (def i in 0..4) {
        try {
            online($f.c);
        } catch (e) {
            $messages[] = messageOf($e);
            $statuses[] = $e.status;
            $codes[] = strings.join($e.codes, ",");
        }
    }
    finish($f);
    testing.assertEqual($statuses, [0, 200, 401, 502]);
    testing.assertEqual($codes, ["", "FORBIDDEN", "UNAUTHENTICATED", ""]);
    testing.assertEqual(len($messages), 4);
    testing.assertEqual($messages[0], "unraid: online: the reply has no data");
    testing.assertEqual($messages[1], "unraid: online: Forbidden resource [FORBIDDEN]");
    testing.assertEqual(
        $messages[2],
        "unraid: online: HTTP 401: No API key provided [UNAUTHENTICATED]");
    testing.assertTrue(strings.contains($messages[3], "HTTP 502"));
    for (def m in $messages) {
        testing.assertFalse(strings.contains($m, "test-key_1"));
    }
}

func testNetworkFailureIsUnraid() {
    def srv as httpd.Server init httpd.listen("127.0.0.1:0");
    def addr as string init httpd.address($srv);
    httpd.shutdown($srv);
    def failed as bool init false;
    try {
        online(withTimeout(client("http://" + $addr), 2000));
    } catch (e) {
        $failed = true;
        testing.assertTrue(strings.startsWith(messageOf($e), "unraid: online: "));
    }
    testing.assertTrue($failed);
}

# --- system -------------------------------------------------------------------

func testSystem() {
    def f as Fake init fake([
        ok('{"info":{"versions":{"core":{"unraid":"7.2.0","api":"4.10.0","kernel":"6.12.24"}}}}'),
        ok('{"vars":{"name":"Tower","version":"7.2.0","timeZone":"Europe/Vienna"},"info":{"os":{"hostname":"tower","distro":"Unraid OS","release":"7.2.0","kernel":"6.12.24","arch":"x64","uptime":"2026-11-01T08:00:00Z"},"cpu":{"brand":"Ryzen 7 5700G","cores":8,"threads":16}}}'),
        ok('{"metrics":{"cpu":{"percentTotal":12.5},"memory":{"total":"34359738368","used":8589934592,"available":"25769803776","percentTotal":25.0,"swapTotal":0,"swapUsed":0}}}'),
        ok('{"services":[{"name":"unraid-api","online":true,"version":"4.10.0"},{"name":"flash-backup","online":null,"version":null}]}'),
        ok('{"upsDevices":[{"id":"ups","name":"APC","model":"Back-UPS 700","status":"Online","battery":{"chargeLevel":100,"estimatedRuntime":2400,"health":"Good"},"power":{"loadPercentage":18,"inputVoltage":230.0,"outputVoltage":230.0}}]}'),
        ok('{"logFiles":[{"name":"syslog","path":"/var/log/syslog","size":51200,"modifiedAt":"2026-11-04T10:00:00Z"}]}'),
        ok('{"logFile":{"path":"/var/log/syslog","content":"a\nb","totalLines":900,"startLine":899}}'),
        ok('{"logFile":{"path":"/var/log/syslog","content":"","totalLines":900,"startLine":null}}')
    ]);
    def v as Versions init version($f.c);
    testing.assertEqual($v.unraid, "7.2.0");
    testing.assertEqual($v.api, "4.10.0");
    def i as SystemInfo init info($f.c);
    testing.assertEqual($i.name, "Tower");
    testing.assertEqual($i.cpu, "Ryzen 7 5700G");
    testing.assertEqual($i.threads, 16);
    testing.assertEqual($i.bootTime, "2026-11-01T08:00:00Z");
    def m as Metrics init metrics($f.c);
    testing.assertEqual($m.memTotal, 34359738368);
    testing.assertEqual($m.memUsed, 8589934592);
    testing.assertEqual($m.cpuPercent, 12.5);
    def svc as list of Service init services($f.c);
    testing.assertTrue($svc[0].online);
    testing.assertFalse($svc[1].online);
    testing.assertEqual($svc[1].version, "");
    def ups as list of UpsDevice init upsDevices($f.c);
    testing.assertEqual($ups[0].runtimeSeconds, 2400);
    testing.assertEqual($ups[0].inputVolts, 230.0);
    testing.assertEqual(logFiles($f.c)[0].size, 51200);
    def chunk as LogChunk init readLog($f.c, "/var/log/syslog", 2, 899);
    testing.assertEqual($chunk.content, "a\nb");
    testing.assertEqual($chunk.startLine, 899);
    testing.assertEqual(readLog($f.c, "/var/log/syslog", 0, 0).startLine, 0);
    def seen as list of Seen init finish($f);
    testing.assertEqual(json.asInt($seen[6].variables, "/lines"), 2);
    testing.assertEqual(json.asInt($seen[6].variables, "/startLine"), 899);
    testing.assertFalse(json.has($seen[7].variables, "/lines"));
    testing.assertFalse(json.has($seen[7].variables, "/startLine"));
}

func badLogPath() {
    readLog(client("tower"), "", 0, 0);
}

func testReadLogChecksPath() {
    testing.assertThrows("badLogPath", ERROR_KIND);
}

# --- storage ------------------------------------------------------------------

def const DISK_JSON as string init '{"id":"s:d1","idx":1,"name":"disk1","device":"sdb","type":"DATA","status":"DISK_OK","size":"3907018532","fsSize":3905920000,"fsFree":"1000000","fsUsed":2905920000,"fsType":"xfs","temp":null,"numErrors":"0","isSpinning":false,"rotational":true}';

def const PARITY_JSON as string init '{"status":"COMPLETED","running":false,"paused":false,"correcting":true,"progress":100,"errors":0,"speed":"180.5","duration":36000,"date":"2026-10-01T03:00:00Z"}';

def const ARRAY_JSON as string init '{"state":"STARTED","capacity":{"kilobytes":{"free":"1000000","used":"2905920000","total":"3906920000"}},"parityCheckStatus":' +
    PARITY_JSON + ',"parities":[],"disks":[' + DISK_JSON + '],"caches":[]}';

func testArray() {
    def f as Fake init fake([ok('{"array":' + ARRAY_JSON + '}')]);
    def a as StorageArray init array($f.c);
    finish($f);
    testing.assertEqual($a.state, "STARTED");
    testing.assertEqual($a.totalKb, 3906920000);
    testing.assertEqual(len($a.disks), 1);
    testing.assertEqual($a.disks[0].sizeKb, 3907018532);
    testing.assertEqual($a.disks[0].temp, -1);
    testing.assertEqual($a.disks[0].fsFreeKb, 1000000);
    testing.assertTrue($a.disks[0].rotational);
    testing.assertEqual($a.parity.status, "COMPLETED");
    testing.assertEqual($a.parity.duration, 36000);
}

func passphraseOverHttp() {
    startArray(client("http://tower"), "secret");
}

func testArrayChanges() {
    testing.assertThrows("passphraseOverHttp", ERROR_KIND);
    def f as Fake init fake([
        ok('{"array":{"setState":' + ARRAY_JSON + '}}'),
        ok('{"array":{"setState":' + ARRAY_JSON + '}}'),
        ok('{"array":{"mountArrayDisk":' + DISK_JSON + '}}'),
        ok('{"array":{"unmountArrayDisk":' + DISK_JSON + '}}'),
        ok('{"array":{"addDiskToArray":' + ARRAY_JSON + '}}'),
        ok('{"array":{"addDiskToArray":' + ARRAY_JSON + '}}'),
        ok('{"array":{"clearArrayDiskStatistics":true}}'),
        ok('{"array":{"clearArrayDiskStatistics":false}}')
    ]);
    testing.assertEqual(startArray($f.c, "").state, "STARTED");
    stopArray($f.c);
    testing.assertEqual(mountDisk($f.c, "s:d1").name, "disk1");
    unmountDisk($f.c, "s:d1");
    addDiskToArray($f.c, "s:d9", 3);
    addDiskToArray($f.c, "s:d9", -1);
    clearDiskStats($f.c, "s:d1");
    def refused as bool init false;
    try {
        clearDiskStats($f.c, "s:d1");
    } catch (e) {
        $refused = true;
        messageOf($e);
    }
    testing.assertTrue($refused);
    def seen as list of Seen init finish($f);
    testing.assertTrue(strings.startsWith($seen[0].document, "mutation($input: ArrayStateInput!)"));
    testing.assertEqual(json.asString($seen[0].variables, "/input/desiredState"), "START");
    testing.assertFalse(json.has($seen[0].variables, "/input/decryptionPassword"));
    testing.assertEqual(json.asString($seen[1].variables, "/input/desiredState"), "STOP");
    testing.assertEqual(json.asString($seen[2].variables, "/id"), "s:d1");
    testing.assertTrue(strings.contains($seen[3].document, "unmountArrayDisk"));
    testing.assertEqual(json.asInt($seen[4].variables, "/input/slot"), 3);
    testing.assertFalse(json.has($seen[5].variables, "/input/slot"));
}

def const PHYSICAL_JSON as string init '{"id":"s:p1","device":"/dev/sdb","name":"WDC WD40EFRX","vendor":"WDC","type":"HD","size":4000787030016,"serialNum":"WD-1","firmwareRevision":"82.00A82","interfaceType":"SATA","smartStatus":"OK","temperature":null,"isSpinning":true}';

func testDisksAndShares() {
    def f as Fake init fake([
        ok('{"disks":[' + PHYSICAL_JSON + ']}'),
        ok('{"assignableDisks":[]}'),
        ok('{"disk":' + PHYSICAL_JSON + '}'),
        ok('{"disk":null}'),
        ok('{"shares":[{"id":"s:appdata","name":"appdata","comment":"","free":"100","used":200,"size":300,"cache":true,"include":["disk1"],"exclude":null}]}')
    ]);
    def d as list of Disk init disks($f.c);
    testing.assertEqual($d[0].size, 4000787030016);
    testing.assertEqual($d[0].temperature, -1.0);
    testing.assertEqual(len(assignableDisks($f.c)), 0);
    testing.assertEqual(disk($f.c, "s:p1").serial, "WD-1");
    def missing as bool init false;
    try {
        disk($f.c, "s:none");
    } catch (e) {
        $missing = strings.contains(messageOf($e), "no disk");
    }
    testing.assertTrue($missing);
    def sh as list of Share init shares($f.c);
    testing.assertEqual($sh[0].freeKb, 100);
    testing.assertEqual($sh[0].includeDisks, ["disk1"]);
    testing.assertEqual($sh[0].excludeDisks, []);
    finish($f);
}

func testParity() {
    def f as Fake init fake([
        ok('{"array":{"parityCheckStatus":' + PARITY_JSON + '}}'),
        ok('{"parityHistory":[' + PARITY_JSON + ',' + PARITY_JSON + ']}'),
        ok('{"parityCheck":{"start":{}}}'),
        ok('{"parityCheck":{"pause":{}}}'),
        ok('{"parityCheck":{"resume":{}}}'),
        ok('{"parityCheck":{"cancel":{}}}')
    ]);
    testing.assertEqual(parityStatus($f.c).speed, "180.5");
    testing.assertEqual(len(parityHistory($f.c)), 2);
    startParityCheck($f.c, false);
    pauseParityCheck($f.c);
    resumeParityCheck($f.c);
    cancelParityCheck($f.c);
    def seen as list of Seen init finish($f);
    testing.assertFalse(json.asBool($seen[2].variables, "/correct"));
    testing.assertEqual($seen[5].document, 'mutation { parityCheck { cancel } }');
}

# --- containers ---------------------------------------------------------------

def const CONTAINER_JSON as string init '{"id":"s:c1","names":["/plex"],"image":"plexinc/pms-docker","state":"RUNNING","status":"Up 3 hours","autoStart":true,"webUiUrl":"http://tower:32400/web","isUpdateAvailable":false,"created":1761900000,"ports":[{"ip":"0.0.0.0","privatePort":32400,"publicPort":32400,"type":"TCP"}]}';

func testContainers() {
    def f as Fake init fake([
        ok('{"docker":{"containers":[' + CONTAINER_JSON + ']}}'),
        ok('{"docker":{"container":' + CONTAINER_JSON + '}}'),
        ok('{"docker":{"container":null}}'),
        ok('{"docker":{"containers":[' + CONTAINER_JSON + ']}}'),
        ok('{"docker":{"containers":[' + CONTAINER_JSON + ']}}')
    ]);
    def all as list of Container init containers($f.c);
    testing.assertEqual($all[0].name, "plex");
    testing.assertEqual($all[0].ports[0].publicPort, 32400);
    testing.assertEqual(container($f.c, "s:c1").image, "plexinc/pms-docker");
    def missing as bool init false;
    try {
        container($f.c, "s:none");
    } catch (e) {
        $missing = strings.contains(messageOf($e), "no container");
    }
    testing.assertTrue($missing);
    testing.assertEqual(containerByName($f.c, "/plex").id, "s:c1");
    def unknown as bool init false;
    try {
        containerByName($f.c, "jellyfin");
    } catch (e) {
        $unknown = strings.contains(messageOf($e), "no container named");
    }
    testing.assertTrue($unknown);
    def seen as list of Seen init finish($f);
    testing.assertEqual(json.asString($seen[1].variables, "/id"), "s:c1");
}

func testContainerChanges() {
    def f as Fake init fake([
        ok('{"docker":{"start":' + CONTAINER_JSON + '}}'),
        ok('{"docker":{"stop":' + CONTAINER_JSON + '}}'),
        ok('{"docker":{"restart":' + CONTAINER_JSON + '}}'),
        ok('{"docker":{"pause":' + CONTAINER_JSON + '}}'),
        ok('{"docker":{"unpause":' + CONTAINER_JSON + '}}'),
        ok('{"docker":{"updateContainer":' + CONTAINER_JSON + '}}'),
        ok('{"docker":{"updateAllContainers":[' + CONTAINER_JSON + ']}}'),
        ok('{"docker":{"removeContainer":true}}'),
        ok('{"docker":{"removeContainer":false}}'),
        ok('{"docker":{"logs":{"lines":[{"timestamp":"2026-11-04T10:00:00Z","message":"ready"}],"cursor":"2026-11-04T10:00:00Z"}}}'),
        ok('{"docker":{"updateAutostartConfiguration":true}}')
    ]);
    testing.assertEqual(startContainer($f.c, "s:c1").state, "RUNNING");
    stopContainer($f.c, "s:c1");
    restartContainer($f.c, "s:c1");
    pauseContainer($f.c, "s:c1");
    unpauseContainer($f.c, "s:c1");
    updateContainer($f.c, "s:c1");
    testing.assertEqual(len(updateAllContainers($f.c)), 1);
    removeContainer($f.c, "s:c1", true);
    def refused as bool init false;
    try {
        removeContainer($f.c, "s:c1", false);
    } catch (e) {
        $refused = true;
        messageOf($e);
    }
    testing.assertTrue($refused);
    def logs as ContainerLogs init containerLogs($f.c, "s:c1", "", 50);
    testing.assertEqual($logs.lines[0].message, "ready");
    testing.assertEqual($logs.cursor, "2026-11-04T10:00:00Z");
    def plan as list of Autostart init [
        Autostart{id: "s:c1", autoStart: true, wait: 10},
        Autostart{id: "s:c2", autoStart: false, wait: 0}
    ];
    setAutostart($f.c, $plan);
    def seen as list of Seen init finish($f);
    testing.assertTrue(strings.contains($seen[0].document, 'docker { start(id: $id)'));
    testing.assertTrue(strings.contains($seen[5].document, 'updateContainer(id: $id)'));
    testing.assertTrue(json.asBool($seen[7].variables, "/withImage"));
    testing.assertEqual(json.asInt($seen[9].variables, "/tail"), 50);
    testing.assertFalse(json.has($seen[9].variables, "/since"));
    testing.assertEqual(json.length($seen[10].variables, "/entries"), 2);
    testing.assertEqual(json.asInt($seen[10].variables, "/entries/0/wait"), 10);
    testing.assertFalse(json.asBool($seen[10].variables, "/entries/1/autoStart"));
}

func badContainerId() {
    startContainer(client("tower"), "");
}

func testIdsAreChecked() {
    testing.assertThrows("badContainerId", ERROR_KIND);
}

# --- virtual machines ---------------------------------------------------------

def const VMS_OFF as string init '{"vms":{"domains":[{"id":"s:1f2e","name":"win11","state":"SHUTOFF"}]}}';

def const VMS_ON as string init '{"vms":{"domains":[{"id":"s:1f2e","name":"win11","state":"RUNNING"}]}}';

func testVms() {
    def f as Fake init fake([ok(VMS_OFF), ok(VMS_OFF), ok(VMS_OFF), ok('{"vms":{"domains":null}}')]);
    testing.assertEqual(vms($f.c)[0].name, "win11");
    testing.assertEqual(vm($f.c, "1f2e").state, "SHUTOFF");
    testing.assertEqual(vmByName($f.c, "win11").id, "s:1f2e");
    def missing as bool init false;
    try {
        vmByName($f.c, "win11");
    } catch (e) {
        $missing = strings.contains(messageOf($e), "no VM named");
    }
    testing.assertTrue($missing);
    finish($f);
}

func testVmChanges() {
    def f as Fake init fake([
        ok('{"vm":{"start":true}}'),
        ok('{"vm":{"stop":true}}'),
        ok('{"vm":{"forceStop":true}}'),
        ok('{"vm":{"pause":true}}'),
        ok('{"vm":{"resume":true}}'),
        ok('{"vm":{"reboot":true}}'),
        ok('{"vm":{"reset":false}}'),
        ok(VMS_OFF),
        ok(VMS_ON),
        ok(VMS_OFF),
        ok(VMS_OFF)
    ]);
    startVm($f.c, "s:1f2e");
    stopVm($f.c, "s:1f2e");
    forceStopVm($f.c, "s:1f2e");
    pauseVm($f.c, "s:1f2e");
    resumeVm($f.c, "s:1f2e");
    rebootVm($f.c, "s:1f2e");
    def refused as bool init false;
    try {
        resetVm($f.c, "s:1f2e");
    } catch (e) {
        $refused = strings.contains(messageOf($e), "did not do it");
    }
    testing.assertTrue($refused);
    testing.assertEqual(waitVm($f.c, "s:1f2e", "RUNNING", 5000).state, "RUNNING");
    def late as bool init false;
    try {
        waitVm($f.c, "s:1f2e", "RUNNING", 15);
    } catch (e) {
        $late = strings.contains(messageOf($e), "still SHUTOFF");
    }
    testing.assertTrue($late);
    def seen as list of Seen init finish($f);
    testing.assertTrue(strings.contains($seen[2].document, 'vm { forceStop(id: $id) }'));
}

func waitUnknownState() {
    waitVm(client("tower"), "s:1", "UP", 10);
}

func testWaitVmChecksState() {
    testing.assertThrows("waitUnknownState", ERROR_KIND);
}

# --- notifications ------------------------------------------------------------

def const NOTE_JSON as string init '{"id":"s:n1","title":"Array","subject":"Disk 3","description":"hot","importance":"WARNING","link":null,"type":"UNREAD","timestamp":"2026-11-04T09:00:00Z"}';

func testNotifications() {
    def f as Fake init fake([
        ok('{"notifications":{"list":[' + NOTE_JSON + ']}}'),
        ok('{"notifications":{"list":[]}}'),
        ok('{"notifications":{"overview":{"unread":{"info":1,"warning":2,"alert":0,"total":3},"archive":{"info":5,"warning":0,"alert":1,"total":6}}}}'),
        ok('{"createNotification":' + NOTE_JSON + '}'),
        ok('{"notifyIfUnique":{"id":"s:n2"}}'),
        ok('{"notifyIfUnique":null}'),
        ok('{"archiveNotification":{"id":"s:n1"}}'),
        ok('{"unarchiveNotifications":{"unread":{"total":3}}}'),
        ok('{"deleteNotification":{"unread":{"total":2}}}'),
        ok('{"archiveAll":{"unread":{"total":0}}}'),
        ok('{"archiveAll":{"unread":{"total":0}}}')
    ]);
    def page as list of Notification init notifications($f.c, false, "WARNING", 0, 20);
    testing.assertEqual($page[0].subject, "Disk 3");
    testing.assertFalse($page[0].archived);
    testing.assertEqual($page[0].link, "");
    notifications($f.c, true, "", 20, 20);
    def o as NotificationOverview init notificationOverview($f.c);
    testing.assertEqual($o.unread.warning, 2);
    testing.assertEqual($o.archived.total, 6);
    testing.assertEqual(notify($f.c, "Backup", "Nightly", "done", "INFO", "").id, "s:n1");
    testing.assertTrue(notifyOnce($f.c, "Backup", "Nightly", "done", "INFO", "http://x"));
    testing.assertFalse(notifyOnce($f.c, "Backup", "Nightly", "done", "INFO", "http://x"));
    archiveNotification($f.c, "s:n1");
    unarchiveNotification($f.c, "s:n1");
    deleteNotification($f.c, "s:n1", true);
    archiveAll($f.c, "");
    archiveAll($f.c, "ALERT");
    def seen as list of Seen init finish($f);
    testing.assertEqual(json.asString($seen[0].variables, "/filter/type"), "UNREAD");
    testing.assertEqual(json.asString($seen[0].variables, "/filter/importance"), "WARNING");
    testing.assertEqual(json.asInt($seen[0].variables, "/filter/limit"), 20);
    testing.assertEqual(json.asString($seen[1].variables, "/filter/type"), "ARCHIVE");
    testing.assertFalse(json.has($seen[1].variables, "/filter/importance"));
    testing.assertFalse(json.has($seen[3].variables, "/input/link"));
    testing.assertEqual(json.asString($seen[4].variables, "/input/link"), "http://x");
    testing.assertEqual(json.asString($seen[7].variables, "/ids/0"), "s:n1");
    testing.assertEqual(json.asString($seen[8].variables, "/type"), "ARCHIVE");
    testing.assertFalse(json.has($seen[9].variables, "/importance"));
    testing.assertEqual(json.asString($seen[10].variables, "/importance"), "ALERT");
}

func badImportance() {
    notify(client("tower"), "t", "s", "d", "info", "");
}

func badLimit() {
    notifications(client("tower"), false, "", 0, 0);
}

func badOffset() {
    notifications(client("tower"), false, "", -1, 10);
}

func testImportanceChecked() {
    testing.assertThrows("badImportance", ERROR_KIND);
    testing.assertThrows("badLimit", ERROR_KIND);
    testing.assertThrows("badOffset", ERROR_KIND);
}

# --- administration -----------------------------------------------------------

func testAdmin() {
    def f as Fake init fake([
        ok('{"apiKeys":[{"id":"s:k1","name":"ci","description":null,"roles":["VIEWER"],"createdAt":"2026-11-01T00:00:00Z"}]}'),
        ok('{"apiKey":{"create":{"id":"s:k2","name":"backup","description":"nightly","key":"abc123","roles":["ADMIN"],"createdAt":"2026-11-04T00:00:00Z"}}}'),
        ok('{"apiKey":{"delete":true}}'),
        ok('{"plugins":[{"name":"unassigned.devices","version":"2026.10.01"}]}'),
        ok('{"flash":{"guid":"0781-5571","vendor":"SanDisk","product":"Cruzer Fit"}}'),
        ok('{"initiateFlashBackup":{"status":"started","jobId":"42"}}'),
        ok('{"rclone":{"remotes":[{"name":"b2","type":"b2"}]}}'),
        ok('{"rclone":{"createRCloneRemote":{"name":"s3","type":"s3"}}}'),
        ok('{"rclone":{"deleteRCloneRemote":true}}'),
        ok('{"updateServerIdentity":{"name":"Tower2"}}')
    ]);
    def keys as list of ApiKey init apiKeys($f.c);
    testing.assertEqual($keys[0].roles, ["VIEWER"]);
    testing.assertEqual($keys[0].key, "");
    def made as ApiKey init createApiKey($f.c, "backup", "nightly", ["ADMIN"]);
    testing.assertEqual($made.key, "abc123");
    deleteApiKey($f.c, "s:k2");
    testing.assertEqual(plugins($f.c)[0].name, "unassigned.devices");
    testing.assertEqual(flash($f.c).product, "Cruzer Fit");
    testing.assertEqual(backupFlash($f.c, "b2", "/boot", "unraid/flash").jobId, "42");
    testing.assertEqual(rcloneRemotes($f.c)[0].type, "b2");
    def params as json.Value init json.set(json.map(), "/provider", "AWS");
    testing.assertEqual(createRcloneRemote($f.c, "s3", "s3", $params).name, "s3");
    deleteRcloneRemote($f.c, "s3");
    setServerIdentity($f.c, "Tower2", "");
    def seen as list of Seen init finish($f);
    testing.assertFalse(strings.contains($seen[0].document, "key"));
    testing.assertEqual(json.asString($seen[1].variables, "/input/roles/0"), "ADMIN");
    testing.assertEqual(json.asString($seen[2].variables, "/input/ids/0"), "s:k2");
    testing.assertEqual(json.asString($seen[5].variables, "/input/sourcePath"), "/boot");
    testing.assertEqual(json.asString($seen[7].variables, "/input/parameters/provider"), "AWS");
    testing.assertEqual(json.asString($seen[8].variables, "/input/name"), "s3");
    testing.assertEqual(json.asString($seen[9].variables, "/name"), "Tower2");
}

func unknownRole() {
    createApiKey(client("tower"), "ci", "", ["ROOT"]);
}

func testRolesChecked() {
    testing.assertThrows("unknownRole", ERROR_KIND);
}

# --- the fake server ----------------------------------------------------------

# A client that never sends the request a reply was given for fails the test
# instead of leaving the server, and the run, waiting forever.
func testAFakeServerLeftWaitingFailsTheTest() {
    def f as Fake init fake([ok('null')]);
    def message as string init "";
    try {
        finishWithin($f, 200);
    } catch (e) {
        testing.assertEqual($e.kind, "assertion");
        $message = $e.message;
    }
    testing.assertContains($message, "still waiting for a request after 200 ms");
}
