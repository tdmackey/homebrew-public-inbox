# macOS IPC compatibility and test matrix

Status: acceptance plan. This document is not a completed test report.

Design reference: [`macos-ipc-record-rfc.md`](macos-ipc-record-rfc.md)

## Purpose

Use this matrix to collect evidence for upstream review and Homebrew releases.
It covers the native `SOCK_SEQPACKET` transport and the `SOCK_STREAM` fallback.
The fallback stores each record in an anonymous file and sends its file
descriptor (FD) with one notification byte.

All required tests must show these results:

- Records are not lost, duplicated, merged, or sent to the wrong recipient.
- File descriptors do not leak.
- Both transports produce the same command results and exit status.

## Transport modes

| Mode | Selection | Expected use |
| --- | --- | --- |
| native-seq | sequence-packet socket creation succeeds | preferred transport on hosts that support it |
| forced-stream | `PI_TEST_LEI_STREAM=1` selects stream | regression tests on each POSIX test host |
| native-stream | sequence-packet socket creation reports an unsupported type | automatic fallback, including macOS |
| datagram | never selected automatically | experiments only; excluded from acceptance |

Use the override only for tests. Verify that operational errors, such as
descriptor exhaustion, do not select the fallback.

## Host compatibility matrix

| Host | Architecture | Native expectation | Required modes | Release gate |
| --- | --- | --- | --- | --- |
| GitHub `macos-latest` | arm64 | stream fallback | native-stream | required; configured in source CI |
| Linux, Ubuntu 24.04 | x86_64 | sequence packet | native-seq, forced-stream | required; configured in source CI |
| Linux, Debian stable or oldstable | x86_64 | sequence packet | native-seq, forced-stream | recommended additional run |
| Linux, Debian stable | arm64 | sequence packet | native-seq, forced-stream | recommended automated run |
| Linux, musl-based distribution | x86_64 | sequence packet | native-seq, forced-stream | required when an existing project runner is available |
| FreeBSD | supported architecture | socket creation decides; normally sequence packet | native-seq, forced-stream | required before claiming a portable BSD fallback |
| OpenBSD | supported architecture | socket creation decides | native mode, forced-stream | periodic or manual run |
| NetBSD | supported architecture | socket creation decides | native mode, forced-stream | periodic or manual run |
| DragonFly BSD | supported architecture | socket creation decides | native mode, forced-stream | periodic or manual run |

The source fork's `.github/workflows/ipc-portability.yml` configures the Ubuntu
and macOS jobs. The other rows are test targets. A configured job does not
establish that a run passed.

Older macOS releases and Intel Macs are additional compatibility targets.
The tap does not continuously test them or claim support for them.

For each result, record the exact OS build, kernel, Perl, Git, Xapian, SQLite,
serializer, and descriptor backend. State which release and architecture
passed. Do not extend that result to an untested host.

## Dependency and implementation dimensions

Test each available variant on at least one host:

| Dimension | Variant A | Variant B | Required evidence |
| --- | --- | --- | --- |
| FD backend | pure-Perl syscall | Inline::C/`PublicInbox::Spawn` | run the record and FD suites on both; include the packaged macOS backend |
| serialization | Sereal | Storable fallback | run IPC and multiworker tests on both |
| Xapian Perl API | `Xapian` | `Search::Xapian`, where supported | test import and query with the packaged API |
| Xapian helper | direct Perl binding | Perl or C++ helper | test each supported helper; disable unsupported helpers in stream mode |
| worker count | 1 | 4 or detected maximum | run the full work-distribution suite at both counts |
| socket mode | blocking | nonblocking/event loop | test short writes, backpressure, and wakeups |
| client I/O | pipe or file | terminal, pager, or mail user agent (MUA) | test descriptor routing and signals |

For each skipped test, name the missing dependency or unavailable platform.
A skipped test does not prove that the Homebrew dependency set works.

## Capability-selection tests

| ID | Case | Method | Expected result |
| --- | --- | --- | --- |
| CAP-001 | sequence packet supported | create a UNIX sequence-packet socket pair and exchange a record | select native-seq; retry selection on each socket or socket-pair creation |
| CAP-002 | sequence packet unsupported | make socket creation return `EPROTONOSUPPORT` or a supported equivalent | select stream |
| CAP-003 | resource exhaustion | inject `EMFILE`, `ENFILE`, `ENOMEM`, and `ENOBUFS` during socket creation | report the operational error; do not select the fallback |
| CAP-004 | permission error or invalid path | fail named socket creation or bind | report the error; do not select the fallback |
| CAP-005 | FD transfer | pass a temporary descriptor and read known bytes | receive the correct descriptor once |
| CAP-006 | separate paths | start native-seq and forced-stream daemons for the same user | use different versioned paths; prevent connections to the wrong transport |
| CAP-007 | stale path | leave a stale stream socket path, then restart | recover the stale socket with the existing safety checks |
| CAP-008 | future capability | simulate successful sequence-packet creation while `$^O` reports Darwin | select native-seq without an OS-name condition |

## Stream record tests

The fallback sends one NUL notification byte with the record FD and the
application FDs. The record file holds the complete payload. An empty logical
payload is invalid: callers reserve it for end-of-file (EOF). EOF occurs
between notifications, so the receiver has no partial frame to retain.

| ID | Case | Expected result |
| --- | --- | --- |
| REC-001 | ordinary payload with no application FDs | return the exact payload; hide the record FD |
| REC-002 | two queued records | return separate records in order |
| REC-003 | payload larger than the sequence-packet limit | read the exact payload from the record FD |
| REC-004 | notification without a record FD | reject it without an FD leak |
| REC-005 | unknown record magic or version | reject the record |
| REC-006 | header count differs from application FD count | reject the record and close all received FDs |
| REC-007 | explicit receive limit exceeded | reject the record before reading the payload |
| REC-008 | empty nonblocking socket | immediately return `undef` with `EAGAIN` |
| REC-009 | full nonblocking send queue | promptly return `undef` with `EAGAIN`; publish no record |
| REC-010 | injected `ETOOMANYREFS` | retry with a timer; do not repeatedly retry a writable socket |
| REC-011 | two concurrent writers that pass FDs | receive each large record intact and exactly once |
| REC-012 | two readers on one endpoint | assign each record and its FDs to one reader |
| REC-013 | writer exits before notification | expose no partial record |
| REC-014 | sender closes originals after send | keep the queued record and FDs valid |

## Descriptor-passing tests

| ID | Case | Expected result |
| --- | --- | --- |
| FD-001 | no application descriptors | accept the record with count zero |
| FD-002 | one descriptor plus payload | keep the descriptor and payload in the same record |
| FD-003 | standard input, output, error, and working directory | receive four descriptors in the documented order |
| FD-004 | consecutive records with different FD counts | keep each descriptor with its record |
| FD-005 | record file arrives with a nonzero offset | seek to zero and read the exact record |
| FD-006 | one-byte notification | return one from `sendmsg`, or fail without a partial record |
| FD-007 | declared count differs from received count | reject and close every received descriptor |
| FD-008 | `MSG_CTRUNC` | reject the notification and close all visible descriptors |
| FD-009 | unexpected control-message type or level | reject the message safely |
| FD-010 | receiver aborts after descriptor arrival | return the descriptor count to its initial value |
| FD-011 | sender closes original immediately after send | keep the received duplicate valid |
| FD-012 | execute a test child after receive | close unintended descriptors on exec (`CLOEXEC`) |
| FD-013 | descriptor limit or `ETOOMANYREFS` | bound retries or report the documented error; do not leak FDs or retry continuously |
| FD-014 | largest audited descriptor set | accept ten application FDs plus the record FD; reject eleven application FDs |

Count open descriptors before and after each failure case. On macOS, use
`lsof` as an additional check if needed. Tests must also verify descriptor
cleanup without parsing `lsof` output.

## Ownership and concurrency tests

| ID | Topology | Load | Expected result |
| --- | --- | --- | --- |
| CON-001 | one client writer, daemon reader | 100,000 numbered records | exact ordered sequence |
| CON-002 | daemon writer, one client reader | 100,000 mixed response records | exact ordered sequence |
| CON-003 | 32 simultaneous clients | repeated short commands | per-client isolation and correct exits |
| CON-004 | four workqueue workers | 100,000 uniquely numbered jobs | every job assigned exactly once |
| CON-005 | different worker speeds | one delayed worker, three normal | the delayed worker does not block all others; all jobs complete |
| CON-006 | all worker queues full | slow readers and bounded parent queue | no loss; producer resumes after a writable event |
| CON-007 | `PktOp` with four producers | 25,000 records per producer | 100,000 intact records, no interleaving |
| CON-008 | broadcasts | 10,000 numbered broadcasts to four workers | each live worker receives each broadcast once |
| CON-009 | worker exits between jobs | queued and unassigned jobs present | other channels remain synchronized |
| CON-010 | worker exits after receiving a record | terminate the worker at a known point after dequeue | assigned work fails cleanly; later records remain intact |
| CON-011 | parent exits | workers blocked in receive | workers observe EOF and terminate |
| CON-012 | client exits during long work | active worker set | work cancellation/detach matches current semantics |
| CON-013 | rapid fork/reap cycles | at least 1,000 worker replacements | no stale event-loop registrations or FD growth |
| CON-014 | sequence wrap/long run | at least one million records | no loss, duplicate, or checksum mismatch |

Compare the event traces from native-seq and forced-stream runs. Ignore
process IDs and timing differences. The logical events must match.

## Signal and lifecycle tests

| ID | Case | Expected result |
| --- | --- | --- |
| SIG-001 | repeated client `TSTP` and `CONT` during output | keep records intact and resume the process |
| SIG-002 | `WINCH` while a pager or MUA is active | notify the correct process group; keep records with their recipient |
| SIG-003 | `TERM`, `INT`, and `QUIT` at an idle daemon | use the documented exit and socket cleanup |
| SIG-004 | the same signals during record send or receive | prevent deadlock and damage to the next record |
| SIG-005 | many helper processes send `CHLD` | reap all children and keep responses intact |
| SIG-006 | signal immediately before and after notification | publish the exact record or publish nothing |
| LIFE-001 | first client races to start daemon with 15 peers | one usable daemon; all clients connect or retry cleanly |
| LIFE-002 | daemon dies after bind before readiness | next client recovers stale endpoint |
| LIFE-003 | daemon restarts while old client is connected | old client gets explicit failure/EOF; new client succeeds |
| LIFE-004 | client closes without completion message | daemon detects EOF and releases request resources |
| LIFE-005 | client disconnects before initial notification | clean EOF; no descriptors leaked |
| LIFE-006 | runtime directory path near `sun_path` limit | clear diagnostic or successful bounded path |
| LIFE-007 | runtime directory permissions are too broad | existing safety policy retained |

Signal handlers must publish each control record with one complete
notification. They must not leak the record FD.

## `lei` functional matrix

Run each required case in three modes: native-seq on Linux, forced-stream on
Linux, and native-stream on macOS. Give each run a temporary `HOME`, XDG
directories, Git configuration, and store.

| ID | Scenario | Assertions |
| --- | --- | --- |
| LEI-001 | `lei init` | initialize the store, exit 0, and keep the daemon reusable |
| LEI-002 | import one RFC 822 message from stdin | route stdout and stderr correctly; make the message searchable |
| LEI-003 | bulk mbox import through stdin | consume the exact input without truncation |
| LEI-004 | Maildir import | store the expected document and keywords |
| LEI-005 | `lei q` to stdout | return the expected result and exit status |
| LEI-006 | `lei q -o mboxrd:` and Maildir output | produce the correct output count and content |
| LEI-007 | threaded query with multiple workers | return a stable set of threads and results |
| LEI-008 | `lei tag` or keyword update | retain the change and make it searchable |
| LEI-009 | `lei up` saved search | complete the update; make the client wait for barriers |
| LEI-010 | `lei index` local mail source | make the source searchable |
| LEI-011 | add, list, and forget an external source | change the configuration and return correct responses |
| LEI-012 | pager use | pass descriptors to the pager; make the client wait correctly |
| LEI-013 | MUA execution | transfer the command, environment, and FDs exactly once |
| LEI-014 | `git credential` helper use | route request and response pipes correctly |
| LEI-015 | client `umask` request | return the exact value in a record |
| LEI-016 | successful store barrier | keep the client running until committed data is visible |
| LEI-017 | injected store barrier failure | send `child_error` to the client once; exit with a nonzero status |
| LEI-018 | `lei daemon-pid`, kill, and restart | target the correct daemon |
| LEI-019 | concurrent import and query clients | keep descriptors and responses with the correct client |
| LEI-020 | large arguments and environment near the accepted limit | parse them exactly; reject a request one byte above the limit |

Run and extend these tests in the source fork:

- `t/cmd_ipc.t`
- `t/ipc-socket.t`
- `t/ipc-stream.t`
- `t/ipc.t`
- `t/lei.t`
- `t/lei-daemon.t`
- `t/lei-stream.t`
- `t/lei-import.t`
- `t/lei-q-*.t`
- `t/lei-tag.t`
- `t/lei-up.t`
- `t/lei-store-fail.t`
- `t/lei-sigpipe.t`
- `t/xap_helper.t`

Keep record-protocol cases in focused tests as well as complete `lei` tests.

## Xapian helper matrix

| ID | Mode | Case | Expected result |
| --- | --- | --- | --- |
| XAP-001 | native-seq | Perl helper | existing test behavior unchanged |
| XAP-002 | native-seq | C/C++ helper | existing test behavior unchanged |
| XAP-003 | forced-stream | helper lacks stream support | report the capability and use the direct binding without a crash |
| XAP-004 | forced/native-stream | Perl helper | keep request FDs and results associated |
| XAP-005 | forced/native-stream | future C++ helper with stream support | accept stream in the `SO_TYPE` check only when the stream parser is enabled |
| XAP-006 | four helper workers | mixed fast/slow queries | each request handled once; output FD correct |
| XAP-007 | helper worker dies mid-query | caller receives failure; later queries remain usable |
| XAP-008 | helper parent dies | clients see EOF/failure without hang |
| XAP-009 | query request exceeds normal packet size | descriptor-backed large record succeeds |
| XAP-010 | read-only daemon retry setting | error/retry behavior matches native path |

State which helper mode the Homebrew package uses. Test every helper that the
package can select automatically.

The current Perl helper supports stream records. The C++ helper requires
sequence-packet sockets. In stream mode, `lei` uses the direct Perl Xapian
binding. The macOS source job sets `PI_NO_CXX=1` to suppress C++ helper probes.
Its comment about using the Perl stream helper does not describe the `lei`
selection code. A helper test does not prove that `lei` uses that helper.

## Fault-injection plan

Inject failures at known points so each case can be repeated:

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

Limit fault hooks to a lexical scope or a test process. Do not let an inherited
user variable enable a production fault hook.

## Performance and resource measurements

After the correctness tests pass, report these measurements in the patch
cover letter:

- tiny-record round trips per second;
- workqueue jobs per second with one and four workers;
- bulk import wall time and CPU time;
- query latency distribution;
- daemon resident memory (RSS);
- maximum open descriptor count;
- context switches where available.

Compare on the same Linux host:

1. Unmodified source with native-seq, to establish a baseline.
2. Patched source with native-seq, to measure the change to the existing path.
3. Patched source with forced-stream, to measure the fallback cost.

Measure a baseline before setting a performance threshold for stream mode.
Explain each native-seq slowdown. If a slowdown is measurable and repeatable,
block the release until it is fixed or upstream accepts it.

## Test commands and result capture

Run these commands in the public-inbox **source fork**, after installing its
test dependencies. This tap does not contain the Perl source or its tests.
For native Linux, build and run the focused and full suites:

```sh
cd /path/to/public-inbox
unset PI_TEST_LEI_STREAM
perl Makefile.PL
make
prove -Ilib -bvw \
  t/cmd_ipc.t t/ipc-socket.t t/ipc-stream.t t/ipc.t \
  t/lei.t t/lei-daemon.t t/lei-stream.t t/xap_helper.t
make test
```

On the same Linux host, force stream mode and repeat both suites:

```sh
PI_TEST_LEI_STREAM=1 prove -Ilib -bvw \
  t/cmd_ipc.t t/ipc-socket.t t/ipc-stream.t t/ipc.t \
  t/lei.t t/lei-daemon.t t/lei-stream.t t/xap_helper.t
PI_TEST_LEI_STREAM=1 make test
```

On macOS, set `TMPDIR=/private/tmp` and `PI_NO_CXX=1` before the build and test
commands. Keep `PI_TEST_LEI_STREAM` unset to test automatic fallback. The
short temporary path prevents test socket names from exceeding `sun_path`.
Run the same build and focused-test commands.

The source CI macOS job runs a broad suite with `t/daemon.t` and `t/extsearch.t`
excluded. Its comments identify upstream Darwin failures in kqueue HUP timing
and NNTP Xref fixture ordering. To reproduce that job, run this in Bash:

```bash
tests=()
for test_file in t/*.t; do
  case "$test_file" in
    t/daemon.t|t/extsearch.t) ;;
    *) tests+=("$test_file") ;;
  esac
done
make test TEST_FILES="${tests[*]}"
```

Report these exclusions with the result. This broad run is not a full-suite
pass and does not, by itself, meet the full-suite upstream merge requirement.
Record the selected transport and the test override with every run.

For every matrix run, retain:

- source commit and patch-series version;
- full command line and relevant test-local variables;
- `uname -a`, Perl configuration summary, and dependency versions;
- TAP output, skipped-test reasons, and excluded test files;
- stress-test seed and iteration count;
- descriptor counts before and after tests that check for leaks;
- benchmark samples, not only averages.

## Acceptance gates

### Before sending a patch series for acceptance

- Pass record and descriptor unit tests with forced-stream Linux.
- Pass existing IPC and `lei` tests with native-seq Linux.
- Complete the focused suite on a real Apple Silicon macOS host.
- Show no loss or duplication in `PktOp` tests with multiple producers and
  workqueue tests with multiple workers.
- Test each supported Xapian helper. Disable an unsupported helper and test
  its direct-binding fallback.

### Before requesting upstream merge

- Pass full `make test` runs on native-seq Linux and native-stream macOS.
  Explain each skipped test and report exclusions separately.
- Pass the focused IPC and `lei` suites with forced-stream Linux.
- Pass stress tests with one million records and stable descriptor counts.
- Show that worker or client crashes do not damage unrelated channels.
- Show that native-seq performance has no material slowdown.
- Document transport selection and limitations.

### Before publishing Homebrew bottles

- Pass Apple Silicon tests on the current GitHub-hosted macOS runner.
- Publish bottles only for continuously tested OS and architecture combinations.
- Test the exact bottle dependency set for FD transfer, serialization, Xapian,
  import, query, pager and MUA use, signals, and daemon lifecycle.
- Install on a clean machine. Pass `brew test` and a representative `lei`
  import and query procedure.
- Match any downstream patch to a posted upstream series. Remove or update
  the patch promptly when upstream accepts the fix.

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
Xapian binding/helper selected:
Worker count:
Focused suite:
Full suite:
Stress iterations/seed:
FD baseline/high-water/final:
Skipped tests and reasons:
Excluded tests and reasons:
Performance summary:
Known failures:
Log/artifact location:
```

Include this information in the cover letter for `meta@public-inbox.org`.
Put large raw logs at a stable public URL and link to them from the email.
