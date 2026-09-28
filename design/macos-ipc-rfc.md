# Historical RFC: one reader and one writer per `lei` stream

Status: superseded proposal. Retained as design history.

Audience: public-inbox maintainers and contributors.

The [record-file design](macos-ipc-record-rfc.md) replaces this proposal.
The implemented transport keeps shared endpoints. It does not use the
per-worker streams or frame format described below.

## Purpose

This proposal examined a stream fallback for `lei` on macOS. It explains
why a length prefix alone cannot preserve records on shared byte streams.
The requirements and procedures below belong to this earlier proposal.

IPC means interprocess communication. A record is one complete logical
message. An FD is a file descriptor for an open file, pipe, or socket.
`SCM_RIGHTS` is socket control data that transfers FDs between processes.
Backpressure makes a sender wait when the receiver cannot accept more data.

## Starting point

Before the portability change, `lei` required `AF_UNIX SOCK_SEQPACKET` for
client sockets, work queues, operation notifications, and the Xapian helper.
Darwin defines the constant but does not implement that UNIX socket type.
Thus, socket creation fails on the affected macOS systems.

The proposal had four parts:

1. Keep the existing sequence-packet path when a runtime probe succeeds.
2. Add an `AF_UNIX SOCK_STREAM` transport with explicit record framing.
3. Give each stream one reader and one writer. Use one connection per client.
   Use a parent broker or separate worker and producer socket pairs internally.
4. Preserve descriptor passing, backpressure, record boundaries, failure
   reporting, and concurrent workers.

## Required IPC behavior

The original code relies on these properties:

- One send corresponds to one receive.
- Records arrive in order, without silent loss.
- `SCM_RIGHTS` descriptors remain associated with their record.
- The receiver detects when its peer closes the connection.
- Workers can share an endpoint and receive complete work records.
- Producers can share an endpoint and send complete records.
- Blocking and nonblocking senders can detect backpressure.

The references below use upstream commit
`6d8fd320c878a99154e6b87c0360d56b7db46b27`, before the three portability
commits. They describe the starting point for this analysis.

[`Documentation/lei-daemon.pod`](https://kernel.googlesource.com/pub/scm/infra/public-inbox/+/6d8fd320c878a99154e6b87c0360d56b7db46b27/Documentation/lei-daemon.pod)
explains the use of sequence packets for reliability and work distribution.
The shared endpoints appear in:

- [`PublicInbox::IPC`](https://kernel.googlesource.com/pub/scm/infra/public-inbox/+/6d8fd320c878a99154e6b87c0360d56b7db46b27/lib/PublicInbox/IPC.pm):
  one producer and several workers.
- [`PublicInbox::PktOp`](https://kernel.googlesource.com/pub/scm/infra/public-inbox/+/6d8fd320c878a99154e6b87c0360d56b7db46b27/lib/PublicInbox/PktOp.pm):
  several producers and one consumer.

These components also depend on record boundaries:

- [`script/lei`](https://kernel.googlesource.com/pub/scm/infra/public-inbox/+/6d8fd320c878a99154e6b87c0360d56b7db46b27/script/lei)
- [`PublicInbox::LEI`](https://kernel.googlesource.com/pub/scm/infra/public-inbox/+/6d8fd320c878a99154e6b87c0360d56b7db46b27/lib/PublicInbox/LEI.pm)
- [`PublicInbox::XapClient`](https://kernel.googlesource.com/pub/scm/infra/public-inbox/+/6d8fd320c878a99154e6b87c0360d56b7db46b27/lib/PublicInbox/XapClient.pm)
- [`PublicInbox::XapHelper`](https://kernel.googlesource.com/pub/scm/infra/public-inbox/+/6d8fd320c878a99154e6b87c0360d56b7db46b27/lib/PublicInbox/XapHelper.pm)
- [`xap_helper.h`](https://kernel.googlesource.com/pub/scm/infra/public-inbox/+/6d8fd320c878a99154e6b87c0360d56b7db46b27/lib/PublicInbox/xap_helper.h)

## Darwin evidence

Apple's XNU source supports the portability concern:

- [`uipc_usrreq.c`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/uipc_usrreq.c)
  lists `SEQPACKET` and `RDM` as work still to do for UNIX sockets.
- [`unix(4)`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/man/man4/unix.4)
  documents UNIX `SOCK_STREAM` and `SOCK_DGRAM`. It does not list
  `SOCK_SEQPACKET`.
- In `uipc_send`, XNU processes control data before it selects the stream or
  datagram path. Thus, the implementation can transfer `SCM_RIGHTS` with local
  datagrams. Its comment warns of datagram loss when a receive queue is full.
  See [`uipc_send`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/uipc_usrreq.c#L498-L546).

This evidence does not establish a safe datagram replacement for work or
completion records. Losing such a record can leave state incomplete or a
command waiting indefinitely. A port must test the selected transport's
behavior on each supported system.

## Goals and limits

The proposal aimed to:

- Run the full `lei` daemon and its workers on Apple Silicon macOS.
- Select a transport by runtime capability, including on other macOS systems.
- Preserve the native sequence-packet path and its performance.
- Preserve FD transfer, ordering, record boundaries, exit status, signal
  forwarding, and disconnect detection.
- Support several workers on the stream path.
- Keep communication local to the same host.
- Add no required non-core Perl module or platform framework.
- Keep the Perl 5.12 baseline.
- Let Linux tests force the stream path.

The proposal did not define a stable external API or support remote clients.
It did not replace the serializer or deprecate sequence packets. It also did
not add Mach IPC, XPC, launchd activation, or unrelated event-notification work.

## Alternatives considered

### Replace sequence packets with streams everywhere

The proposal rejected this option. A byte stream has no record boundaries.
One reader can consume a header while another consumes its payload. Writers
can also mix parts of their frames.

A stream `sendmsg(2)` call can return a short byte count after transferring
the descriptors. Sending the original message again can duplicate data or
FDs. Sending only the remaining bytes still lets another writer interrupt the
frame unless one writer owns the stream.

A receive lock does not solve recovery. If a worker exits after reading part
of a frame, the next worker cannot safely locate the next record. Locks also
require rules for starvation and process failure.

### Use internal datagram socket pairs

Datagrams preserve boundaries and fit shared endpoints. However, XNU warns
of queue-overflow loss. Datagrams also lack orderly EOF behavior. Their size
limits and peer shutdown behavior need separate handling.

A reliable layer would need acknowledgements, retries, record identifiers,
and duplicate detection. Some work cannot safely run twice. That makes retry
handling at least as complex as a stream broker.

### Limit macOS to one worker

A single worker can help with diagnosis. It does not solve multiple producers,
signal-handler writes, partial sends, or Xapian helper assumptions. It also
reduces concurrency, so the proposal did not treat it as a complete port.

### Add Mach or XPC

The proposal rejected a separate macOS transport. It would require compiled
platform code and another IPC model to maintain and review.

### Give each stream one reader and one writer

This was the proposal's preferred option. Connected streams provide reliable
delivery, backpressure, EOF, and descriptor passing on the target platforms.
Separate ownership prevents readers and writers from dividing each other's
frames. The later record-file design avoids this change to process ownership.

## Proposed architecture

### Transport selection

The proposal called for a lazy capability probe:

1. Try `socketpair(AF_UNIX, SOCK_SEQPACKET, 0)` during transport setup.
2. Cache a successful result for the process.
3. Fall back for unsupported-type errors, such as `EPROTONOSUPPORT`,
   `EPROTOTYPE`, `EOPNOTSUPP`, or the platform's `EINVAL` result.
4. Report `EMFILE`, `ENFILE`, `ENOMEM`, `ENOBUFS`, and permission errors as
   operational failures. Do not use them to select a fallback.

An optional startup check could transfer one temporary FD and read it back.
The test suite would need to check that transfer directly. A test-only
setting would force either transport without becoming an end-user setting.

### Socket identity

Keep the existing sequence-packet path. Give the stream protocol a separate
version and path. The proposed examples were:

| Protocol | Historical example |
| --- | --- |
| Existing sequence packet | `5.seq.sock` |
| Proposed framed stream | `6.stream.sock` |

These are historical examples. The implemented record-file transport uses
`5.stream.sock`. A distinct path prevents incompatible clients and daemons
from connecting. Runtime selection also permits native sequence packets if
a future Darwin version implements them.

### Frame format

The proposed frame started with a fixed 12-byte header in network byte order:

| Field | Size | Meaning |
| --- | ---: | --- |
| Magic and version | 4 bytes | Fixed protocol identifier |
| Payload length | 4 bytes | Unsigned byte length |
| FD count | 2 bytes | Expected `SCM_RIGHTS` count |
| Type and flags | 2 bytes | Command, signal, response, or reserved flags |

The proposed parser requirements were:

- Reject unknown versions, reserved flags, excessive lengths, and invalid FD
  counts before allocating payload storage.
- Keep the existing limits for each channel.
- Allow large requests to use a separately passed stream. Frame the control
  record that introduces that stream.
- Frame every logical message, including `STOP`, `CONT`, `WINCH`, `umask`,
  exit status, and empty completion records.
- Accept EOF only between frames. Treat EOF within a header or payload as an
  error.
- Send a header even when the logical payload is empty. Do not depend on a
  zero-byte `sendmsg` call to transfer descriptors.

### Descriptor transfer

The proposed transfer procedure was:

1. Call `sendmsg` with the header, available payload, and all application FDs.
2. After a short send, write the remaining bytes without sending the FDs again.
   Keep exclusive write ownership until the frame is complete.
3. Receive the header with `recvmsg`. Store the received FDs with that frame.
4. Read exactly the declared payload length. Do not consume the next header.
5. Reject `MSG_CTRUNC`, unexpected control messages, and FD count mismatches.
6. Set `FD_CLOEXEC` when the platform cannot set it as part of the receive.
7. On an error, close all descriptors received for the incomplete frame.

### Ownership

Each direction of a stream would have one record reader and one record writer.
A duplex stream could use different owners for its two directions.

For client connections:

- `script/lei` would own writes to the daemon.
- The daemon would own writes to the client.
- Workers would report errors, exit status, pager requests, mail user agent
  (MUA) requests, and barriers through the daemon.
- Signal handlers would queue work through a self-pipe or another wakeup
  mechanism safe for signal handlers. They would not interrupt a framed write.

For `PktOp`:

- Create a separate stream for each producer when its worker starts.
- Register each receive end with the common operation table and event loop.
- Do not share one producer endpoint between processes.

For work queues:

- Create one stream socket pair per worker.
- Keep the producer endpoints in the parent.
- Send a complete frame to one worker that can accept it.
- Queue work in the parent when no worker can accept it.
- Send broadcasts separately to every worker.
- Close and reap a failed worker without disturbing other channels.

Round-robin dispatch could be the initial policy. It would need to respect
backpressure so that one slow worker did not delay unrelated work.

The Xapian helper would also need one channel per worker. Until that change
was ready, the stream path could use the direct Perl Xapian binding. The
Perl and C++ helpers must check the actual socket type with `SO_TYPE`.

### Shutdown and failures

The proposed failure rules were:

- Preserve the existing cancel or detach behavior when a client closes.
- Stop only the affected worker on parent-to-worker EOF.
- Keep a partial frame on one worker's channel from affecting another channel.
- Close a channel after a partial frame. Close its received FDs and report the
  failure. Restart the worker only when the existing policy requires it.
- Keep unassigned work in the parent so another worker can receive it.
- Retry assigned work only when existing command rules make a retry safe.
  Do not replay a command that might already have run.

## Compatibility and validation

The native path would remain the default when the probe succeeds. The fallback
would affect private local IPC for the same user. Runtime-directory permissions
and `umask(077)` would remain required.

Validate lengths and FD counts even for trusted clients. Do not deserialize
an incomplete payload. Test both existing FD backends: the pure-Perl syscall
implementation and Inline::C in `PublicInbox::Spawn`. No new CPAN module was
required by this proposal.

Select the transport from the socket path and the successfully created socket.
Do not infer it from data supplied in a frame.

## Historical implementation plan

The proposal suggested this sequence:

1. Add capability probing and a test override.
2. Add a bounded framed-stream encoder and parser with unit tests.
3. Convert client connections, including daemon-owned writes and signal wakeups.
4. Give each `PktOp` producer a separate stream.
5. Add per-worker streams and parent dispatch for `PublicInbox::IPC`.
6. Port both Xapian helpers or explicitly disable incompatible helper use.
7. Update `lei-daemon`, `lei-store-format`, and platform documentation.

Each step would keep native sequence-packet tests passing. Tests would be
able to force the fallback on Linux.

## Historical upstream submission plan

Upstream's
[`HACKING`](https://kernel.googlesource.com/pub/scm/infra/public-inbox/+/6d8fd320c878a99154e6b87c0360d56b7db46b27/HACKING)
document directs patches and request-pull messages to `meta@public-inbox.org`.
The discussion archive is at [public-inbox.org/meta](https://public-inbox.org/meta/).

This proposal called for a design discussion before implementation:

1. Send a plain-text RFC with this subject:
   `[RFC] lei: reliable IPC fallback for systems without SOCK_SEQPACKET`.
2. Explain the macOS packaging need and include the XNU evidence.
3. Ask whether maintainers prefer per-worker streams or a parent broker.
4. Include a small reproducer showing the defined constant and failed Darwin
   `socketpair` call.
5. Add the archived discussion link to this repository. Use reply-all to keep
   the discussion in one thread; subscription is not required.

After agreement, the proposed procedure was:

1. Rebase on upstream `master`.
2. Split the work into reviewable source changes. Keep Homebrew packaging
   changes outside the upstream series.
3. Generate patches with `git format-patch --cover-letter`.
4. Review the plain-text files, then send them with `git send-email`.
5. Copy relevant authors and reviewers from the affected file histories.
   Retain recipients when replying.
6. Explain the reason for each change and its tests in the commit message.
7. Put actual macOS, forced-stream Linux, and native Linux results in the
   cover letter. Include the compatibility matrix.
8. For a revision, send the complete series with a version such as `v2`.
   Include a change log and a range-diff when useful.

The proposed seven-patch series was:

```text
[PATCH 0/7] lei: support reliable IPC without SOCK_SEQPACKET
[PATCH 1/7] ipc: probe sequence-packet support at runtime
[PATCH 2/7] ipc: add bounded stream record codec
[PATCH 3/7] lei: use framed stream fallback for client connections
[PATCH 4/7] pkt_op: give stream producers independent channels
[PATCH 5/7] ipc: dispatch stream work over per-worker channels
[PATCH 6/7] xap_helper: support or explicitly gate stream transport
[PATCH 7/7] doc: describe portable lei IPC transports
```

This sequence is historical. Use the three-product-commit sequence in the
[current RFC](macos-ipc-record-rfc.md#upstream-submission) for the implemented
record-file design. Neither document establishes that upstream received or
approved a series.

## Historical questions for upstream

1. Should the fallback be a reusable `PublicInbox::IPC` object or stay private
   to the affected callers?
2. Should workers use separate streams or a broker process?
3. Is direct Perl Xapian an acceptable initial fallback while helpers are ported?
4. Should the test override use an environment variable or a localized package
   variable?
5. Which worker-restart policy should follow an incomplete frame or worker exit?
6. Which minimum macOS version should the test results support?
