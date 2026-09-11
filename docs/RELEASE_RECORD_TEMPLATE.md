# Raspberry Pi Rebuild Release Record

> This is the live electronic evidence record for one rebuild. Start with `START-HERE.md` and follow the numbered steps in order. Use `docs/RELEASE_DAY.md` when more detail is needed. Do not commit populated release records containing site-specific operational information unless that is explicitly approved.

## How to use this record

For every numbered step in `START-HERE.md`:

1. run the documented command;
2. check that the documented expected result is present;
3. record the result and evidence here;
4. only then continue to the next step.

If a step returns `FAIL` or `NO-GO`, **stop** unless you are following the documented rollback procedure.

Do not mark a step `PASS` simply because a command finished. The expected result must actually have been seen.

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

## Step-by-step release record

Update this table while following `START-HERE.md`.

Use these values where practical:

```text
PASS
FAIL
NO-GO
ROLLED BACK
NOT RUN
N/A
```

| Step | What this step proves | Result | Time | Evidence / notes |
| --- | --- | --- | --- | --- |
| 1 - Git environment | Checkout is current, clean and pinned to an exact commit | {{GATE_MINUS1_INITIAL}} | {{CREATED_TIME}} | Commit `{{GIT_COMMIT}}` |
| 2 - Migration profile | Correct Pi/OS profile selected | {{PROFILE_OVERALL_RESULT}} | {{CREATED_TIME}} | {{PROFILE_SUMMARY}} |
| 3 - Electronic record | Release record created and automatic profile discovery agrees | {{PROFILE_OVERALL_RESULT}} | {{CREATED_TIME}} | Record `{{RECORD_FILE}}` |
| 4 - Site configuration | Protected profile-specific site configuration prepared | _pending_ |  |  |
| 5 - Laptop/VPN/SSH | Laptop, VPN, active Pi and passive Pi are reachable and healthy | _pending_ |  |  |
| 6 - Passive-node preflight | Pi model, CentOS version, architecture, network and whole SD device confirmed | _pending_ |  |  |
| 7 - Inventory + FreeSWITCH export | Required configuration/evidence copied safely off-node | _pending_ |  |  |
| 8 - Full rollback image | Complete SD-card rollback image exists off-node and is checksummed | _pending_ |  |  |
| 9 - Rescue readiness | Correct profile-specific rescue is ready and loaded | _pending_ |  |  |
| 10 - RAM rescue validation | Rescue runs from RAM, network works, correct SD is visible and unmounted | _pending_ |  |  |
| 11 - Debian write | Approved Debian image written to the confirmed passive-node SD card | _pending_ |  |  |
| 12 - Debian validation | Debian boots and OS/network/storage/SSH validation passes | _pending_ |  |  |
| 13 - FreeSWITCH validation | Config restore, smoke tests and functional checks pass | _pending_ |  |  |
| 14 - Finish / soak | First-node release completed and passive soak started | _pending_ |  |  |

## Rollback and migration artifacts

| Artifact | Path / value | Checksum / result |
| --- | --- | --- |
| Full source SD rollback image | _pending_ | _pending_ |
| FreeSWITCH export | _pending_ | _pending_ |
| Inventory bundle | _pending_ | _pending_ |
| Debian image | {{DEBIAN_IMAGE}} | {{DEBIAN_IMAGE_SHA512}} |
| Release log / console transcript | _pending_ |  |

## Destructive checkpoint

Complete immediately before **Step 11 - Debian write**.

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

If any line above cannot be confirmed, the result is **NO-GO**. Do not write Debian.

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

Do not rebuild the active node as part of the same first-node release simply because time remains in the maintenance window.

## Notes

_Add timestamped notes here during the release._
