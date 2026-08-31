# RFC: record-preserving `lei` IPC without `SOCK_SEQPACKET`

Status: implemented in the portability fork; pending upstream review
Audience: public-inbox maintainers, downstream packagers, and contributors

## Summary

public-inbox and `lei` prefer `AF_UNIX SOCK_SEQPACKET` because one send maps
to one receive, `SCM_RIGHTS` descriptors stay attached to their record, and a
shared endpoint can safely distribute work among processes. Darwin exposes
the constant but does not implement UNIX-domain sequence-packet sockets.

The portability fork keeps the existing sequence-packet path and wire format
unchanged when a runtime probe succeeds. If the socket type is unsupported,
it selects `SOCK_STREAM` and carries every logical message as an anonymous,
descriptor-backed record:

1. write a small header and the complete payload to an anonymous regular file;
2. reset the file offset;
3. send one NUL notification byte with `SCM_RIGHTS`, placing the record file
   first and the existing application descriptors after it;
4. receive exactly one byte, validate and read the record file, then return
   only the application descriptors to the existing caller.

A one-byte stream send cannot be short. The kernel associates the ancillary
descriptor set with that byte, so concurrent writers cannot interleave a
record and concurrent readers cannot split one. A writer that dies before the
send publishes nothing; a writer that dies after it publishes a complete
record. This retains the shared-reader/shared-writer topology instead of
adding brokers, cross-process locks, or one socketpair per worker.

## Why this design

### Not `SOCK_DGRAM`

Darwin UNIX datagrams preserve message boundaries but may silently discard a
datagram when the receive queue is full. Lost work, completion, or barrier
records are unacceptable. Datagram sockets also do not provide stream-style
EOF semantics.

### Not ordinary length-prefixed stream frames

A byte-stream frame plus a mutex is insufficient for the current topology.
Several readers can divide a header and payload; several writers can splice
short writes; a writer can die after a partial frame; and a Perl safe signal
handler can re-enter a non-reentrant writer lock. Once a partial frame exists,
the next valid frame cannot be recovered without a more elaborate poison and
resynchronization protocol.

### Not a worker broker

A parent broker or one stream per producer/worker can be correct, but it
rewrites work distribution, backpressure, broadcasts, cancellation, and
worker lifecycle. Descriptor-backed records preserve the current architecture
and keep the portability patch reviewable.

## Capability selection

Selection is based on the operation, not `$^O`:

- try `socket` or `socketpair` with `AF_UNIX SOCK_SEQPACKET`;
- use it unchanged on success;
- fall back only for unsupported-protocol errors such as
  `EPROTONOSUPPORT`, `ESOCKTNOSUPPORT`, `EPROTOTYPE`, `EOPNOTSUPP`,
  `EAFNOSUPPORT`, or the platform's `EINVAL` result;
- report resource exhaustion and other operational failures rather than
  silently changing transports.

`PI_TEST_LEI_STREAM=1` is a test hook that forces the fallback on Linux. It is
not a documented end-user compatibility switch.

Named `lei` sockets remain transport-specific:

- sequence packet: `5.seq.sock`
- descriptor-backed stream: `5.stream.sock`

The distinct path prevents a client from connecting to a daemon that expects
the other private protocol.

## Record protocol

The anonymous record file begins with an eight-byte header:

| Field | Size | Encoding |
| --- | ---: | --- |
| magic and version | 4 bytes | `PI\\0\\1` |
| application FD count | 4 bytes | network-order unsigned integer |

The payload is every remaining byte in the file, so payload length is derived
from `fstat(2)`. This avoids a 32-bit length ceiling and retains the existing
large-request behavior. Empty logical payloads remain reserved for EOF in
current callers and are rejected when sending a stream record.

The notification carries, in order:

1. the anonymous record file descriptor;
2. zero to ten application file descriptors.

Both existing SCM backends are raised from ten to eleven total descriptors so
the stream record does not reduce the sequence-packet API's ten-descriptor
limit. The receiver checks that the header count matches the application
descriptor count and hides the record descriptor from callers.

Malformed tokens, non-regular record descriptors, truncated headers, bad
versions, oversized records for bounded receive sites, and descriptor-count
mismatches are fatal protocol errors. Lexical handle cleanup closes every
received descriptor on an exception.

## Concurrency and failure properties

- A record publication is one `sendmsg(2)` with one data byte.
- `EAGAIN` returns immediately and publishes no partial record.
- `ENOBUFS`, `ENOMEM`, and `ETOOMANYREFS` remain retryable in nonblocking work
  queues; FD-pressure retries use a timer because the stream may still appear
  writable.
- Multiple writers may share one endpoint without a userspace mutex.
- Multiple workers may block in `recvmsg(1)` on one endpoint; one worker gets
  the notification and its complete ancillary set.
- EOF can occur only between notifications, so no partial parser state exists.
- The native sequence-packet implementation and its raw wire format are not
  changed.

## Component behavior

- `script/lei` and `PublicInbox::LEI` select matching socket paths/types and
  route commands, signals, `umask`, execution requests, and exit status through
  the transport-neutral send/receive wrappers.
- work queues and `PktOp` keep their existing producer/consumer topology.
- the Perl Xapian helper can consume descriptor-backed records, including with
  multiple workers.
- the C++ Xapian helper remains sequence-packet-only. `lei` uses its packaged
  direct Perl Xapian binding on the stream path rather than launching an
  incompatible helper.

The fallback requires working `SCM_RIGHTS`. That was already required by the
affected `lei` IPC paths; the Homebrew formula packages the Inline::C backend.

## Cost and compatibility

The fallback creates and writes an anonymous temporary file per logical
record. That is intentionally more expensive than `SOCK_SEQPACKET`, which
remains preferred everywhere it works. The file is unlinked by construction,
never named in the user's store, and closed after the notification is sent and
consumed.

The design adds no network protocol, daemon privilege, non-core Perl module,
or macOS-only framework. It retains Perl 5.12 syntax and is testable on Linux.

## Required evidence

The source branch gates publication on:

- native sequence-packet and forced-stream Linux runs;
- automatic fallback on macOS 15 and 26, Apple Silicon and Intel;
- both pure-Perl syscall and Inline::C SCM backends;
- 10-descriptor success and deterministic 11-descriptor rejection;
- immediate nonblocking `EAGAIN` with no phantom receive record;
- injected `ETOOMANYREFS` retry classification;
- concurrent passed-FD writers under backpressure;
- concurrent shared readers with exact payload/FD association;
- `t/ipc.t`, `t/cmd_ipc.t`, `t/xap_helper.t`, `t/lei-daemon.t`, `t/lei.t`,
  the focused stream tests, and the full upstream test suite;
- an end-to-end `lei import` and query through the Homebrew formula.

The detailed host and fault matrix is in
[`macos-ipc-test-matrix.md`](macos-ipc-test-matrix.md).

## Upstream submission

public-inbox accepts patches by email at `meta@public-inbox.org`. The fork
keeps the source work based directly on upstream `master` and keeps GitHub-only
CI in a separate commit. The proposed source series is:

```text
[PATCH 0/3] lei: support reliable IPC without SOCK_SEQPACKET
[PATCH 1/3] ipc: probe sequence-packet support at runtime
[PATCH 2/3] ipc: preserve records over SOCK_STREAM
[PATCH 3/3] lei: use portable local IPC transports
```

Generate the series with `git format-patch --cover-letter`, include native and
forced Linux results plus all macOS runner results, and send the plain-text
series with `git send-email`. The Homebrew tap pins the reviewed fork commit
only until upstream merges and releases the change.

## Upstream questions

1. Is an anonymous record file per stream message acceptable for the macOS
   fallback, given that the native fast path remains unchanged?
2. Should the stream protocol magic/version live in `PublicInbox::IPC` or a
   smaller transport module?
3. Is direct Perl Xapian the preferred fallback while the C++ helper remains
   sequence-packet-only?
4. Does upstream want the test override as an environment variable or a
   localized package variable?
