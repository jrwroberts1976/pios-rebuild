# Raspberry Pi Rebuild Release Record

> This is the live electronic evidence record for one rebuild. Follow `docs/RELEASE_DAY.md` for the actual operating procedure. Do not commit populated release records containing site-specific operational information unless that is explicitly approved.

## Change details

| Field | Value |
| --- | --- |
| Change / release reference | {{CHANGE_REFERENCE}} |
| Date | {{DATE}} |
| Created at | {{CREATED_AT}} |
| Engineer | {{ENGINEER}} |
| Site | {{SITE}} |
| Migration profile | `{{PROFILE}}` |
| Git commit | `{{GIT_COMMIT}}` |
| Git branch | `{{GIT_BRANCH}}` |
| Record file | `{{RECORD_FILE}}` |

## Automatically discovered source state

| Field | Value |
| --- | --- |
| Active node | {{ACTIVE_TARGET}} |
| Active hostname | {{ACTIVE_HOSTNAME}} |
| Active OS | {{ACTIVE_OS}} |
| Node being rebuilt | {{TARGET}} |
| Target hostname | {{TARGET_HOSTNAME}} |
| Raspberry Pi model | {{TARGET_MODEL}} |
| Architecture | {{TARGET_ARCH}} |
| Current OS | {{TARGET_OS}} |
| Source OS ID/version | {{TARGET_OS_ID}} / {{TARGET_OS_VERSION}} |
| Management interface | {{INTERFACE}} |
| Target MAC | {{TARGET_MAC}} |
| SD device | `{{SD_DEVICE}}` |
| Detected SD capacity | {{SD_CAPACITY}} |
| VPN router | {{ROUTER}} |

## Profile verification

Expected source for `{{PROFILE}}`: **{{EXPECTED_PROFILE_DESCRIPTION}}**.

```text
Profile/hardware match: {{PROFILE_HARDWARE_RESULT}}
Profile/OS match:       {{PROFILE_OS_RESULT}}
Architecture check:     {{PROFILE_ARCH_RESULT}}
Overall profile gate:   {{PROFILE_OVERALL_RESULT}}
```

If the overall profile gate is not `PASS`, this release is **NO-GO** and no destructive step may be performed.

## Approved Debian image

| Field | Value |
| --- | --- |
| Debian image | {{DEBIAN_IMAGE}} |
| Debian image SHA512 | {{DEBIAN_IMAGE_SHA512}} |
| Rescue build identity | _fill in before change_ |
| Rescue round-trip evidence | _fill in before change_ |

## Release gate record

Update this table during the change. Use `GO`, `NO-GO`, `PASS`, `FAIL`, `ROLLED BACK`, or `N/A` as appropriate.

| Gate | Result | Time | Notes / evidence |
| --- | --- | --- | --- |
| -1 PowerShell/Git environment pinned | {{GATE_MINUS1_INITIAL}} | {{CREATED_TIME}} | Commit `{{GIT_COMMIT}}` |
| 0 Correct Pi/profile confirmed | {{PROFILE_OVERALL_RESULT}} | {{CREATED_TIME}} | {{PROFILE_SUMMARY}} |
| 1 Pre-change prerequisites | _pending_ |  |  |
| 2 Start-of-change validation | _pending_ |  |  |
| 3 Final node/profile preflight | _pending_ |  |  |
| 4 Inventory + FreeSWITCH export | _pending_ |  |  |
| 5 Full 32 GB rollback image | _pending_ |  |  |
| 6 RAM rescue readiness + load | _pending_ |  |  |
| 7 Enter and validate RAM rescue | _pending_ |  |  |
| 8 Destructive Debian write | _pending_ |  |  |
| 9 First Debian boot + validation | _pending_ |  |  |
| 10 FreeSWITCH restore + smoke test | _pending_ |  |  |
| 11 End-of-day decision | _pending_ |  |  |

## Rollback and migration artifacts

| Artifact | Path / value | Checksum / result |
| --- | --- | --- |
| Full source SD rollback image | _pending_ | _pending_ |
| FreeSWITCH export | _pending_ | _pending_ |
| Inventory bundle | _pending_ | _pending_ |
| Debian image | {{DEBIAN_IMAGE}} | {{DEBIAN_IMAGE_SHA512}} |
| Release log / console transcript | _pending_ |  |

## Destructive checkpoint

Complete immediately before Gate 8.

```text
[ ] Profile still matches target hardware/source OS
[ ] Correct PASSIVE node selected
[ ] Active peer is healthy and carrying production
[ ] Target whole SD device re-confirmed
[ ] Verified full rollback image is available off-node
[ ] Verified FreeSWITCH export is available off-node
[ ] Approved Debian image checksum matches
[ ] Correct profile-specific rescue is running from RAM
[ ] Target SD card and child partitions are unmounted
[ ] VPN path is stable

GO / NO-GO:
Decision time:
Engineer initials/name:
Notes:
```

## Functional validation

```text
[ ] Debian validation PASS
[ ] FreeSWITCH service healthy
[ ] Required modules loaded
[ ] Sofia profiles healthy
[ ] Gateways/trunks in expected state
[ ] Test endpoint registration
[ ] Inbound call path
[ ] Outbound call path
[ ] Two-way RTP/audio
[ ] DTMF
[ ] Codec negotiation
[ ] Caller ID / presentation
[ ] Logging/monitoring
[ ] Reboot persistence
```

## End-of-day outcome

```text
Migration technical result: PASS / FAIL / ROLLED BACK
Debian validation: PASS / FAIL
FreeSWITCH smoke test: PASS / FAIL
Functional test result: PASS / FAIL
Actual start:
Actual finish:
Issues / defects raised:
Rollback performed: YES / NO
Final node state:
Engineer decision:
```

Expected successful first-node end state:

```text
ACTIVE NODE: original CentOS node still carrying production
PASSIVE NODE: Debian rebuilt and validated
NEXT STEP: 24-48 hour passive soak
```

## Notes

_Add timestamped notes here during the release._
