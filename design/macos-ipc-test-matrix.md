# macOS IPC compatibility and test matrix

Status: active acceptance plan
Design reference: [`macos-ipc-record-rfc.md`](macos-ipc-record-rfc.md)

## Purpose

This matrix defines the evidence required before a portable `lei` IPC change
is suitable for upstream submission or use by the Homebrew tap. It covers the
native `SOCK_SEQPACKET` path and the descriptor-backed `SOCK_STREAM` fallback.

Correctness gates are absolute: no lost, duplicated, merged, or misdirected
records; no leaked descriptors; and no transport-dependent change to command
results or exit status.

## Transport modes

| Mode | Selection | Expected use |
| --- | --- | --- |
| native-seq | runtime probe succeeds | Linux and BSD fast path |
| forced-stream | test override selects stream | regression coverage on every CI-capable POSIX host |
| native-stream | sequence-packet probe reports unsupported | macOS and any future unsupported platform |
| datagram | never automatically selected | experimental comparison only; not an acceptance path |

The force override is test-only. Tests must prove that operational failures
such as descriptor exhaustion do not trigger transport fallback.

## Host compatibility matrix

| Host | Architecture | Native expectation | Required modes | Release gate |
| --- | --- | --- | --- | --- |
| Current stable macOS (`macos-latest`) | arm64 | stream fallback | native-stream | required automated run |
| Linux, Debian stable or oldstable | x86_64 | sequence packet | native-seq, forced-stream | required automated run |
| Linux, Debian stable | arm64 | sequence packet | native-seq, forced-stream | recommended automated run |
| Linux, musl-based distribution | x86_64 | sequence packet | native-seq, forced-stream | required when an existing project runner is available |
| FreeBSD | supported architecture | probe decides; normally sequence packet | native-seq, forced-stream | required before claiming BSD-neutral fallback |
| OpenBSD | supported architecture | probe decides | native mode, forced-stream | periodic/manual |
| NetBSD | supported architecture | probe decides | native mode, forced-stream | periodic/manual |
| DragonFly BSD | supported architecture | probe decides | native mode, forced-stream | periodic/manual |

Older macOS releases and Intel remain best-effort compatibility targets; the
tap does not continuously test or publish support claims for them.

Record the exact OS build, kernel, Perl, Git, Xapian, SQLite, serializer, and
descriptor-passing backend with every result. Do not use a generic "macOS"
result to claim coverage of untested releases or architectures.

## Dependency and implementation dimensions

Run at least one host through each reachable row:

| Dimension | Variant A | Variant B | Required evidence |
| --- | --- | --- | --- |
| FD passing backend | pure-Perl syscall | Inline::C/`PublicInbox::Spawn` | complete record/FD suite on both; macOS must cover the packaged default |
| serialization | Sereal | Storable fallback | IPC and multiworker suite on both |
| Xapian Perl API | `Xapian` | `Search::Xapian`, where still supported | query/import smoke coverage for packaged API |
| Xapian helper | direct Perl binding | C/C++ helper | helper either passes stream tests or is explicitly unavailable on stream mode |
| worker count | 1 | 4 or detected maximum | full work-distribution suite at both counts |
| socket mode | blocking | nonblocking/event-loop | short-write, backpressure, and wakeup coverage |
| client I/O | pipe/file | TTY/pager/MUA | descriptor routing and signal coverage |

Skip reports must state the missing dependency or unavailable platform. A skip
is not a pass for the Homebrew package's selected dependency set.

## Capability-selection tests

| ID | Case | Method | Expected result |
| --- | --- | --- | --- |
| CAP-001 | sequence packet supported | create and round-trip over a UNIX sequence-packet socketpair | native-seq cached |
| CAP-002 | sequence packet unsupported | force the probe to return `EPROTONOSUPPORT`/platform equivalent | stream selected |
| CAP-003 | resource exhaustion | inject `EMFILE`, `ENFILE`, `ENOMEM`, and `ENOBUFS` | fatal operational error; no fallback |
| CAP-004 | permission or bad path | fail named socket creation/bind | error reported; no fallback |
| CAP-005 | FD capability | pass a temporary descriptor over selected transport and read known bytes | exact descriptor arrives once |
| CAP-006 | path separation | start native-seq and forced-stream daemons for the same user | different versioned paths; no cross-connect |
| CAP-007 | stale path | leave a stale stream socket pathname, then restart | safe stale-socket recovery matching current behavior |
| CAP-008 | future capability | force a successful sequence-packet probe while `$^O` reports Darwin | native-seq selected, proving no OS-name gate |

## Stream record tests

The fallback sends one notification byte with an anonymous record FD and the
application FDs. There is no partial byte-stream frame to resynchronize.

| ID | Case | Expected result |
| --- | --- | --- |
| REC-001 | ordinary payload with no application FDs | exact payload; record FD hidden |
| REC-002 | two queued records | returned separately and in order |
| REC-003 | payload larger than the seqpacket limit | exact payload restored from record FD |
| REC-004 | notification without record FD | rejected without leaking FDs |
| REC-005 | unknown record magic/version | rejected |
| REC-006 | header count differs from application FD count | rejected and all FDs closed |
| REC-007 | explicit receive bound exceeded | rejected before reading payload |
| REC-008 | empty nonblocking socket | immediate `undef`/`EAGAIN` |
| REC-009 | saturated nonblocking sender | prompt `undef`/`EAGAIN`; no phantom record |
| REC-010 | injected `ETOOMANYREFS` | queued for timer retry; no busy writable loop |
| REC-011 | two concurrent passed-FD writers | every large record intact and exactly once |
| REC-012 | two readers on one endpoint | every record/FD pair assigned to one reader |
| REC-013 | writer exits before notification | no partial record visible |
| REC-014 | sender closes originals after send | queued record and FDs remain valid |

## Descriptor-passing tests

| ID | Case | Expected result |
| --- | --- | --- |
| FD-001 | no application descriptors | record accepted with count zero |
| FD-002 | one descriptor plus payload | descriptor and payload associated with same record |
| FD-003 | standard input/output/error plus cwd | four descriptors arrive in documented order |
| FD-004 | consecutive records with different FD counts | no descriptor crosses a record boundary |
| FD-005 | record file arrives with a nonzero offset | receiver seeks to zero and reads the exact record |
| FD-006 | one-byte notification | `sendmsg` returns one or fails without a partial record |
| FD-007 | declared count differs from received count | reject and close every received descriptor |
| FD-008 | `MSG_CTRUNC` | reject the notification and close all visible descriptors |
| FD-009 | unexpected ancillary type/level | reject safely |
| FD-010 | receiver aborts after descriptor arrival | descriptor count returns to baseline |
| FD-011 | sender closes original immediately after send | received duplicate remains valid |
| FD-012 | exec a probe child after receive | unintended descriptors are `CLOEXEC` |
| FD-013 | descriptor limit pressure/`ETOOMANYREFS` | bounded retry or documented error; no leak/spin |
| FD-014 | largest audited descriptor set | accepted within explicit protocol limit |

Measure open descriptors before and after every negative case. On macOS,
`lsof` may supplement the test, but correctness must not depend on parsing its
output.

## Ownership and concurrency tests

| ID | Topology | Load | Expected result |
| --- | --- | --- | --- |
| CON-001 | one client writer, daemon reader | 100,000 numbered records | exact ordered sequence |
| CON-002 | daemon writer, one client reader | 100,000 mixed response records | exact ordered sequence |
| CON-003 | 32 simultaneous clients | repeated short commands | per-client isolation and correct exits |
| CON-004 | four workqueue workers | 100,000 uniquely numbered jobs | every job assigned exactly once |
| CON-005 | heterogeneous worker speed | one delayed worker, three normal | no global head-of-line stall; all jobs complete |
| CON-006 | all workers backpressured | slow readers and bounded parent queue | no loss; producer resumes after writable event |
| CON-007 | `PktOp` with four producers | 25,000 records per producer | 100,000 intact records, no interleaving |
| CON-008 | broadcasts | 10,000 numbered broadcasts to four workers | each live worker receives each broadcast once |
| CON-009 | worker exits between jobs | queued and unassigned jobs present | other channels remain synchronized |
| CON-010 | worker exits after receiving a record | deterministic post-dequeue termination | assigned work fails cleanly; later records remain intact |
| CON-011 | parent exits | workers blocked in receive | workers observe EOF and terminate |
| CON-012 | client exits during long work | active worker set | work cancellation/detach matches current semantics |
| CON-013 | rapid fork/reap cycles | at least 1,000 worker replacements | no stale event-loop registrations or FD growth |
| CON-014 | sequence wrap/long run | at least one million records | no loss, duplicate, or checksum mismatch |

For native-seq and forced-stream runs, the test should produce the same logical
event trace after normalizing PIDs and timing.

## Signal and lifecycle tests

| ID | Case | Expected result |
| --- | --- | --- |
| SIG-001 | client `TSTP`/`CONT` loop during output | records remain intact; process resumes |
| SIG-002 | `WINCH` while pager/MUA is active | correct process group notified; no record misassociation |
| SIG-003 | `TERM`, `INT`, and `QUIT` at idle daemon | documented exit and socket cleanup |
| SIG-004 | same signals during record send/receive | no deadlock or malformed next record |
| SIG-005 | `CHLD` storm from helper processes | all children reaped; responses remain intact |
| SIG-006 | signal immediately before and after notification | exact record or no publication |
| LIFE-001 | first client races to start daemon with 15 peers | one usable daemon; all clients connect or retry cleanly |
| LIFE-002 | daemon dies after bind before readiness | next client recovers stale endpoint |
| LIFE-003 | daemon restarts while old client is connected | old client gets explicit failure/EOF; new client succeeds |
| LIFE-004 | client closes without completion message | daemon detects EOF and releases request resources |
| LIFE-005 | client disconnects before initial notification | clean EOF; no descriptors leaked |
| LIFE-006 | runtime directory path near `sun_path` limit | clear diagnostic or successful bounded path |
| LIFE-007 | runtime directory permissions are too broad | existing safety policy retained |

Signal handlers that publish control records must retain the one-notification
atomicity guarantee and must not leak the descriptor-backed record.

## `lei` functional matrix

Run each required scenario once under native-seq on Linux, once under
forced-stream on Linux, and once under native-stream on macOS. Use isolated
temporary `HOME`, XDG directories, Git config, and stores.

| ID | Scenario | Assertions |
| --- | --- | --- |
| LEI-001 | `lei init` | store initialized; exit 0; daemon reusable |
| LEI-002 | import one RFC 822 message from stdin | stdout/stderr routing correct; message searchable |
| LEI-003 | bulk mbox import through stdin | byte-for-byte input consumed; no truncation |
| LEI-004 | Maildir import | expected document and keywords stored |
| LEI-005 | `lei q` to stdout | expected result and exit status |
| LEI-006 | `lei q -o mboxrd:` and Maildir output | output count/content correct |
| LEI-007 | threaded query with multiple workers | stable thread/result set |
| LEI-008 | `lei tag`/keyword update | mutation persists and is queryable |
| LEI-009 | `lei up` saved search | update completes; client waits for barriers |
| LEI-010 | `lei index` local mail source | source becomes searchable |
| LEI-011 | add/list/forget external | configuration and responses correct |
| LEI-012 | pager path | pager receives passed descriptors; client waits correctly |
| LEI-013 | MUA execution path | command/env/FDs transferred exactly once |
| LEI-014 | `git credential` helper path | request and response pipes routed correctly |
| LEI-015 | client `umask` request | exact value returned in a record |
| LEI-016 | store barrier success | client does not exit before committed data is visible |
| LEI-017 | injected store barrier failure | `child_error` reaches client once; nonzero exit |
| LEI-018 | `lei daemon-pid`, kill, and restart | lifecycle commands target correct daemon |
| LEI-019 | concurrent import and query clients | no cross-client descriptors or responses |
| LEI-020 | large argv/environment near accepted limit | exact parse; one-byte-over-limit request rejected |

Suggested existing upstream tests to run and extend include:

- `t/cmd_ipc.t`
- `t/ipc.t`
- `t/lei.t`
- `t/lei-daemon.t`
- `t/lei-import.t`
- `t/lei-q-*.t`
- `t/lei-tag.t`
- `t/lei-up.t`
- `t/lei-store-fail.t`
- `t/lei-sigpipe.t`
- `t/xap_helper.t`

Add a focused record-protocol test rather than hiding all edge cases inside
end-to-end `lei` tests.

## Xapian helper matrix

| ID | Mode | Case | Expected result |
| --- | --- | --- | --- |
| XAP-001 | native-seq | Perl helper | existing test behavior unchanged |
| XAP-002 | native-seq | C/C++ helper | existing test behavior unchanged |
| XAP-003 | forced-stream | helper not yet ported | explicit capability result and direct-binding fallback, not a crash |
| XAP-004 | forced/native-stream | ported Perl helper | request FDs and results remain associated |
| XAP-005 | forced/native-stream | ported C/C++ helper | `SO_TYPE` accepts stream only when stream parser is enabled |
| XAP-006 | four helper workers | mixed fast/slow queries | each request handled once; output FD correct |
| XAP-007 | helper worker dies mid-query | caller receives failure; later queries remain usable |
| XAP-008 | helper parent dies | clients see EOF/failure without hang |
| XAP-009 | query request exceeds normal packet size | descriptor-backed large record succeeds |
| XAP-010 | read-only daemon retry setting | error/retry behavior matches native path |

The Homebrew acceptance result must state which helper mode the packaged build
uses. An untested automatic helper path is not acceptable.

## Fault-injection plan

Tests need deterministic faults rather than hoping for kernel timing:

- inject `EINTR`, `EAGAIN`, and descriptor-pressure errors around `sendmsg`;
- pause selected workers before and after notification receipt;
- terminate writers immediately before and after the atomic notification;
- kill a worker after dequeue, during payload receipt, during execution, and
  during response;
- reduce socket buffers to trigger backpressure;
- lower `RLIMIT_NOFILE` in a subprocess to exercise descriptor failures;
- corrupt magic, record-file type/size, descriptor count, and serialized payload;
- run with slow readers and event-loop one-shot wakeups;
- repeat with Sereal and Storable.

Fault hooks should be lexically scoped or test-process-only so production code
cannot accidentally enable them through inherited user environment.

## Performance and resource measurements

Correctness comes first, but the patch cover letter should report:

- tiny-record round trips per second;
- workqueue jobs per second with one and four workers;
- bulk import wall time and CPU time;
- query latency distribution;
- daemon RSS;
- open descriptor high-water mark;
- context switches where available.

Compare on the same Linux host:

1. unmodified/native-seq baseline;
2. patched/native-seq, proving the abstraction does not materially regress the
   existing path;
3. patched/forced-stream.

No fixed stream-versus-sequence-packet threshold should be chosen before a
baseline exists. Any native-seq regression should be explained; a regression
large enough to be measurable and repeatable should be treated as a release
blocker unless upstream accepts it.

## Test commands and result capture

At minimum, capture:

```sh
perl Makefile.PL
make
make test
prove -lv t/cmd_ipc.t t/ipc.t t/lei.t t/lei-daemon.t t/xap_helper.t
```

Run the focused and full suites in both selectable transports on a host that
supports sequence packets. The exact force mechanism is pending upstream
design review; record it with the results rather than relying on an implicit
OS branch.

For every matrix run, retain:

- source commit and patch-series version;
- full command line and relevant test-local variables;
- `uname -a`, Perl configuration summary, and dependency versions;
- TAP output and skipped-test reasons;
- stress-test seed and iteration count;
- before/after descriptor counts for leak-sensitive tests;
- benchmark samples, not only averages.

## Acceptance gates

### Required before sending a non-RFC patch series

- Record and descriptor unit suites pass under forced-stream Linux.
- Existing IPC/lei tests pass under native-seq Linux.
- One real Apple Silicon macOS run completes the focused suite.
- Multi-producer `PktOp` and multiworker workqueue stress tests show zero loss
  or duplication.
- The Xapian helper is either ported and tested or explicitly gated with a
  tested direct-binding fallback.

### Required before requesting upstream merge

- Full `make test` passes on native-seq Linux and native-stream macOS, with
  skips explained.
- Forced-stream Linux passes the focused IPC and `lei` suites.
- One million-record stress tests pass with stable descriptor counts.
- Worker/client crash tests cannot desynchronize unrelated channels.
- Native-seq performance is not materially regressed.
- Documentation describes runtime selection and limitations.

### Required before publishing Homebrew bottles

- Apple Silicon tests pass on the current GitHub-hosted macOS runner.
- Publish bottles only for continuously tested OS and architecture combinations.
- The exact bottled dependency set passes the FD backend, serializer, Xapian,
  import, query, pager/MUA, signal, and daemon-lifecycle scenarios.
- A clean-machine install passes `brew test` plus a representative real `lei`
  import/query workflow.
- Any downstream patch corresponds to a posted upstream series and is removed
  or updated promptly when upstream lands the fix.

## Result-report template

```text
Source commit:
Patch series/version:
Host and architecture:
OS/kernel:
Perl/Git/Xapian/SQLite:
FD backend:
Serializer:
Transport selected:
Worker count:
Focused suite:
Full suite:
Stress iterations/seed:
FD baseline/high-water/final:
Skipped tests and reasons:
Performance summary:
Known failures:
Log/artifact location:
```

Attach or summarize this information in the cover letter sent to
`meta@public-inbox.org`, keeping large raw logs at a stable public URL rather
than embedding them in the email.
