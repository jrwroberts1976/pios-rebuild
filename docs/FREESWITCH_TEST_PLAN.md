# FreeSWITCH on Debian 13 Test Plan

## Objective

Prove that the site's FreeSWITCH workload behaves correctly on Debian 13 arm64 before live service is moved away from CentOS 7.

FreeSWITCH 1.11.0 includes Debian 13 Trixie support, but this project treats that as platform support only. The site's exact modules, configuration, SIP trunks, codecs, RTP behaviour and failover still require acceptance testing.

## Baseline to capture from CentOS

Before rebuilding anything, capture from both nodes:

```bash
freeswitch -version 2>/dev/null || true
fs_cli -x 'status' 2>/dev/null || true
fs_cli -x 'show modules' 2>/dev/null || true
fs_cli -x 'sofia status' 2>/dev/null || true
fs_cli -x 'sofia status profile internal' 2>/dev/null || true
fs_cli -x 'sofia status profile external' 2>/dev/null || true
fs_cli -x 'sofia status gateway' 2>/dev/null || true
```

Also export the current configuration directory and record:

- SIP profiles;
- gateways/trunks;
- dialplan;
- directory/users;
- ACLs;
- codec preferences;
- RTP port range;
- NAT/external SIP/RTP configuration;
- DNS dependencies;
- event socket consumers;
- CDR/logging integrations;
- scheduled jobs/scripts;
- custom modules;
- certificates;
- firewall rules.

## Test levels

### Level 1 - Installation and service

Pass criteria:

- Debian 13 arm64 confirmed.
- FreeSWITCH version is the approved version.
- `systemctl is-active freeswitch` returns active.
- `fs_cli -x status` succeeds.
- no repeated crash/restart loop exists.
- expected configuration directory is loaded.
- required modules are present and loaded.
- unexpected module-load failures are investigated.

Suggested commands:

```bash
cat /etc/os-release
uname -m
freeswitch -version
systemctl --no-pager --full status freeswitch
fs_cli -x 'status'
fs_cli -x 'show modules'
journalctl -u freeswitch -b --no-pager | tail -200
```

### Level 2 - SIP profiles and registrations

Pass criteria:

- expected internal and external profiles are RUNNING;
- expected SIP ports are listening;
- required endpoints register;
- required upstream gateways reach the expected registration state;
- no duplicate-IP/node-identity problem occurs while the CentOS active node remains live.

Suggested commands:

```bash
fs_cli -x 'sofia status'
fs_cli -x 'sofia status gateway'
ss -lntup | grep -E 'freeswitch|:5060|:5061'
```

### Level 3 - Functional call tests

Test at least:

| ID | Test | Expected result |
| --- | --- | --- |
| FS-01 | Internal extension to internal extension | call establishes, two-way audio |
| FS-02 | Outbound call | correct trunk, CLI and two-way audio |
| FS-03 | Inbound call | correct DID/dialplan destination and two-way audio |
| FS-04 | DTMF | digits recognised correctly end-to-end |
| FS-05 | Hold/resume | media resumes correctly |
| FS-06 | Transfer | transfer behaviour matches CentOS baseline |
| FS-07 | Codec | negotiated codec is approved/expected |
| FS-08 | Call clear-down | both legs release cleanly |
| FS-09 | Multiple simultaneous calls | expected concurrency works without audio degradation |
| FS-10 | Reboot recovery | FreeSWITCH and gateways recover automatically after reboot |

Add site-specific features such as voicemail, IVR, ring groups, conferencing or recording if they are used in production.

### Level 4 - RTP/media validation

During controlled calls verify:

- two-way audio;
- no one-way RTP;
- RTP source/destination addresses are correct;
- NAT behaviour is correct;
- expected RTP port range is in use;
- packet loss/jitter is acceptable for the site;
- no material CPU starvation occurs on the Pi 3.

Useful tools:

```bash
tcpdump -ni any 'udp and (port 5060 or portrange 10000-40000)'
fs_cli -x 'show channels'
```

Use the actual configured RTP range rather than assuming the example range above.

### Level 5 - Resource/stability test

Observe:

```bash
uptime
free -h
vmstat 1 10
df -hT
journalctl -p warning..alert -b --no-pager
systemctl --failed
```

Monitor CPU, RAM, swap, SD-card I/O, temperature and FreeSWITCH process state during repeated test calls.

Pass criteria:

- no OOM event;
- no FreeSWITCH crash;
- no sustained CPU saturation affecting media;
- adequate free storage;
- no kernel/storage errors;
- no unexplained registration churn.

### Level 6 - Passive-node soak

Before production failover, run the Debian passive node for 24-48 hours while the CentOS active node remains available.

Where possible route test endpoints/test DIDs to the Debian node during this period.

Check at least twice during the soak:

- FreeSWITCH uptime;
- gateway state;
- registrations;
- CPU/RAM;
- journal warnings/errors;
- clock/time synchronisation;
- disk usage;
- monitoring/logging.

### Level 7 - Controlled production failover

Preconditions:

- Levels 1-6 pass;
- original active CentOS node remains untouched and available for rollback;
- current config backup is complete;
- known rollback steps are ready.

Fail over using the site's actual active/passive mechanism.

Immediately perform critical inbound and outbound test calls and verify SIP/RTP.

Rollback immediately if any critical call path fails, one-way audio is present, registrations cannot stabilise, or a Severity 1/2 defect appears.

### Level 8 - Production soak

Target: 48 hours on the Debian node before rebuilding the former active CentOS node.

During this period review:

- all relevant call types;
- registration stability;
- system and FreeSWITCH logs;
- resource usage;
- monitoring alerts;
- user/service reports.

## Defect severity

- **Severity 1:** service unavailable, unable to place/receive required calls, node unreachable.
- **Severity 2:** material call-quality/routing/function failure without total outage.
- **Severity 3:** non-critical operational issue with workaround.
- **Severity 4:** cosmetic/documentation/minor improvement.

No unresolved Severity 1 or Severity 2 defects are allowed at production failover.

## Final dual-node acceptance

After both nodes run Debian 13:

1. prove active node carries calls;
2. fail over to passive;
3. repeat critical inbound/outbound calls;
4. fail back if supported/required;
5. reboot each node individually while the other remains available;
6. verify node identity/IP/configuration remains unique;
7. confirm monitoring identifies both nodes correctly.

Record evidence for each test and update this document with actual site-specific call flows.