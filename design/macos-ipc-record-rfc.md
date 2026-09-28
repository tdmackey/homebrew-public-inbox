# RFC: preserve `lei` records without `SOCK_SEQPACKET`

Status: implemented in the portability fork; prepared for upstream review.

Audience: public-inbox maintainers, package maintainers, and contributors.

## Scope and terms

This document describes product commit
[`7b106f5f`](https://github.com/tdmackey/public-inbox/commit/7b106f5fa70585820cfeb937a62ad7ac25ede312).
The Homebrew formula uses that commit. The
[test matrix](macos-ipc-test-matrix.md) defines the required evidence. It does
not certify that all tests have passed.

| Term | Meaning in this document |
| --- | --- |
| IPC | Interprocess communication: data transfer between processes. |
| Record | One complete logical message. |
| FD | File descriptor: a process handle for an open file, pipe, or socket. |
| Application FD | A descriptor that the caller sends with a record. |
| Record FD | The descriptor for the anonymous file that holds a stream record. |
| `SCM_RIGHTS` | Socket control data that transfers file descriptors. |
| Backpressure | A condition in which a sender must wait because the receiver cannot accept more data. |

## Operation

public-inbox and `lei` prefer `AF_UNIX SOCK_SEQPACKET`. This socket type keeps
each message and its descriptors together. Processes can share an endpoint
to distribute complete work records. On the macOS systems targeted by this
port, Darwin defines `SOCK_SEQPACKET` but does not implement it for UNIX sockets.

The fork first tries a sequence-packet socket. If that operation succeeds,
the fork uses the existing protocol. If the socket type is unsupported, the
fork selects `SOCK_STREAM`.

The stream transport uses this sequence for each record:

1. Write an eight-byte header and the complete payload to an anonymous file.
2. Set the file offset to zero.
3. Send one NUL byte with `SCM_RIGHTS`. Put the record FD first, followed by
   the application FDs.
4. Receive exactly one byte and its descriptors.
5. Validate the record file and read its contents.
6. Return the payload and application FDs to the caller. Close the record FD.

A successful one-byte send transfers the complete notification. There is no
short positive byte count. The kernel transfers the descriptors with that
byte. Thus, concurrent writers do not mix record contents, and concurrent
readers do not divide a record.

If a writer exits before the notification, it publishes no record. If the
notification succeeds, the receiver can read the complete file after the
writer exits. This design retains the existing shared endpoints.

## Design choices

### Datagram sockets

Darwin UNIX datagrams preserve message boundaries. However, XNU documents
possible data loss when a receive queue is full. See the
[Darwin evidence](macos-ipc-rfc.md#darwin-evidence) in the earlier proposal.
Loss of work, completion, or barrier records can leave a command incomplete.
Datagrams also lack the end-of-file (EOF) behavior of a connected stream.

### Length-prefixed stream frames

A length prefix and a mutex do not meet the requirements for shared endpoints.
Several readers can divide a header and its payload. Several writers can mix
partial writes. A writer can exit after it sends part of a frame.

A Perl signal handler can also interrupt a writer and try to acquire its lock
again. Recovery from a partial frame would require another protocol to reject
the damaged channel or find the next valid boundary.

### A broker or separate worker streams

A parent broker, or one stream per producer and worker, can preserve records.
Either design changes work distribution, backpressure, broadcasts,
cancellation, and worker shutdown. The record-file design keeps the existing
process relationships and limits the size of the portability change.

## Transport selection

`PublicInbox::IPCSocket` selects the transport when it creates a socket or
socket pair. It does not select by operating-system name (`$^O`).

1. Try `socket` or `socketpair` with `AF_UNIX SOCK_SEQPACKET`.
2. Use that socket if the operation succeeds.
3. Select `SOCK_STREAM` only after an unsupported-protocol error.
4. Report resource exhaustion and other operational errors to the caller.

The recognized unsupported-protocol errors are `EPROTONOSUPPORT`,
`ESOCKTNOSUPPORT`, `EPROTOTYPE`, `EOPNOTSUPP`, `EAFNOSUPPORT`, and `EINVAL`.
The last error covers platforms that use `EINVAL` for the unsupported type.

For tests, `PI_TEST_LEI_STREAM=1` forces the stream transport. This variable is
a test hook. It is not a supported end-user setting.

Named `lei` sockets use different paths for the two transports:

| Transport | Socket filename |
| --- | --- |
| Sequence packet | `5.seq.sock` |
| Stream record | `5.stream.sock` |

The paths prevent a client from connecting to a daemon that expects the other
protocol.

## Record protocol

The anonymous file starts with this eight-byte header:

| Field | Size | Encoding |
| --- | ---: | --- |
| Magic and version | 4 bytes | `PI\0\1`: hexadecimal bytes `50 49 00 01` |
| Application FD count | 4 bytes | Unsigned integer in network byte order |

All remaining bytes form the payload. The receiver uses `fstat(2)` to get
the file size. The header therefore adds no 32-bit payload-length limit.
Existing callers reserve an empty payload for EOF. The stream sender rejects
an empty logical payload.

Each notification carries the record FD and zero to ten application FDs.
Both descriptor-passing backends can hold eleven FDs. The extra slot keeps
the existing capacity of ten application FDs available to the stream caller.
The receiver verifies the application FD count and hides the record FD from
the caller.

The receiver reports a protocol error for:

- A notification byte other than NUL.
- A missing record FD.
- A record FD that is not a readable and writable regular file.
- An incomplete header or an unknown magic or version.
- An empty payload.
- A record that exceeds a receive site's explicit size limit.
- A declared FD count that differs from the received application FD count.

Received handles have local scope. Their cleanup closes them if record
validation raises an exception.

## Concurrency and failure behavior

- One `sendmsg(2)` call publishes one notification byte.
- A nonblocking send that returns `EAGAIN` publishes no record.
- Nonblocking work queues can retry `ENOBUFS`, `ENOMEM`, and `ETOOMANYREFS`.
- Descriptor-pressure retries use a timer. A socket can still appear writable
  while descriptor transfer cannot proceed.
- Several writers can share one endpoint without a cross-process mutex.
- Several workers can wait on the receive endpoint. Each worker requests one
  byte with `recvmsg(2)` and receives the associated descriptors.
- EOF occurs between notifications. The receiver has no partial stream frame
  to retain.
- The native sequence-packet wire format stays the same.

## Component behavior

| Component | Stream behavior |
| --- | --- |
| `script/lei` and `PublicInbox::LEI` | Select matching socket types and paths. Use common send and receive functions for commands, signals, `umask`, execution requests, and exit status. |
| Work queues and `PktOp` | Retain their existing producer and consumer relationships. |
| Perl Xapian helper | Accepts record files, including when several workers share an endpoint. |
| C++ Xapian helper | Requires sequence-packet sockets. `lei` uses the direct Perl Xapian binding on the stream transport. |

The fallback requires `SCM_RIGHTS`. The affected `lei` paths already require
descriptor passing. The Homebrew formula includes the Inline::C backend.

## Cost and compatibility

The stream transport creates and writes one anonymous temporary file per
record. This adds work compared with `SOCK_SEQPACKET`, which remains the first
choice. The file has no persistent pathname in the user's store. The sender
closes its handle after the send; the receiver closes its handle after reading.

The design adds no network protocol, daemon privilege, non-core Perl module,
or macOS framework. It uses Perl 5.12 syntax. Tests can force it on Linux.

## Required evidence

Collect these results before release:

- Native sequence-packet and forced-stream runs on Linux.
- Automatic fallback on the Apple Silicon macOS runner.
- Tests of both the pure-Perl syscall and Inline::C descriptor backends.
- Successful transfer of ten application FDs and rejection of eleven.
- Immediate `EAGAIN` from a saturated nonblocking sender, with no extra record
  at the receiver.
- Correct retry handling after an injected `ETOOMANYREFS` error.
- Concurrent writers with passed FDs under backpressure.
- Concurrent readers, with each payload matched to its FDs.
- Focused tests: `t/ipc-socket.t`, `t/ipc-stream.t`, `t/lei-stream.t`,
  `t/ipc.t`, `t/cmd_ipc.t`, `t/xap_helper.t`, `t/lei-daemon.t`, and `t/lei.t`.
- The full upstream test suite, with failures, skips, and exclusions reported.
- An installed-formula test that imports a message with `lei` and queries it.

The [test matrix](macos-ipc-test-matrix.md) gives the host requirements, fault
cases, commands, and result template. Passing the formula test alone does
not satisfy that matrix.

## Upstream submission

public-inbox accepts patches at `meta@public-inbox.org`. The source series
starts from upstream commit `6d8fd320c878a99154e6b87c0360d56b7db46b27`.
The three product commits end at `7b106f5f`. Later fork commits contain the
GitHub CI setup and a Darwin test adjustment; exclude them from the product
series.

The proposed subjects are:

```text
[PATCH 0/3] lei: support reliable IPC without SOCK_SEQPACKET
[PATCH 1/3] ipc: probe sequence-packet support at runtime
[PATCH 2/3] ipc: preserve records over SOCK_STREAM
[PATCH 3/3] lei: use portable local IPC transports
```

In the source fork, generate the three patches and a cover letter:

```sh
git format-patch --cover-letter \
  6d8fd320c878a99154e6b87c0360d56b7db46b27..7b106f5fa70585820cfeb937a62ad7ac25ede312
```

Add the native Linux, forced-stream Linux, and Apple Silicon macOS results
to the cover letter. Identify all excluded tests. Review the generated files
before sending the plain-text series with `git send-email`.

The tap keeps the immutable fork snapshot until an upstream release includes
the change. These instructions do not establish that a series has been sent
or reviewed.

## Questions for upstream

1. Is one anonymous record file per stream message an acceptable fallback cost?
2. Should the record magic and version stay in `PublicInbox::IPC`, or move to
   a smaller transport module?
3. Is direct Perl Xapian the preferred fallback while the C++ helper requires
   sequence-packet sockets?
4. Should tests use an environment variable or a localized package variable
   to force the transport?
