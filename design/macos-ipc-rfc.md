# RFC: reliable `lei` IPC on systems without `AF_UNIX SOCK_SEQPACKET`

> Superseded by the implemented
> [descriptor-backed record design](macos-ipc-record-rfc.md). This earlier
> topology proposal is retained as design history because its failure analysis
> explains why ordinary framed byte streams and cross-process locks were not
> used.

Status: proposed design for upstream discussion  
Audience: public-inbox maintainers and contributors  
Motivation: make `lei` usable on macOS without weakening IPC guarantees on existing platforms

## Summary

`lei` currently depends on `AF_UNIX SOCK_SEQPACKET` for its client socket,
internal work queues, operation notifications, and the Xapian helper. macOS
exports the `SOCK_SEQPACKET` constant but XNU does not implement that socket
type for the UNIX domain, so the first `socket(2)` call fails at runtime.

This RFC proposes:

1. Keep the existing `SOCK_SEQPACKET` implementation unchanged whenever a
   runtime capability probe succeeds.
2. Add a framed `AF_UNIX SOCK_STREAM` fallback.
3. On the stream path, give every byte stream exactly one record reader and
   one record writer. Use one connection per client and either a parent broker
   or one socketpair per worker/producer for internal IPC.
4. Preserve descriptor passing, backpressure, command boundaries, failure
   propagation, and worker concurrency.

The proposal deliberately does not replace `SOCK_SEQPACKET` globally and does
not use `SOCK_DGRAM` as the compatibility transport.

## Current contract

The socket type is not an incidental implementation choice. Current code
relies on all of these properties:

- one send corresponds to one receive;
- records are delivered in order and are not silently discarded;
- `SCM_RIGHTS` descriptors travel with the associated record;
- closing a peer produces connection-style shutdown behavior;
- a shared receive endpoint distributes complete work records among workers;
- a shared send endpoint accepts complete records from multiple producers;
- backpressure is visible to blocking and nonblocking senders.

The current design is documented in
[`Documentation/lei-daemon.pod`](https://kernel.googlesource.com/pub/scm/infra/public-inbox/+/refs/heads/master/Documentation/lei-daemon.pod),
which cites reliability, load distribution, and avoidance of stream parsers as
reasons for using `SOCK_SEQPACKET`.

The two shared-endpoint patterns are visible in current upstream code:

- [`PublicInbox::IPC`](https://kernel.googlesource.com/pub/scm/infra/public-inbox/+/refs/heads/master/lib/PublicInbox/IPC.pm)
  uses a single producer and multiple workers for work distribution.
- [`PublicInbox::PktOp`](https://kernel.googlesource.com/pub/scm/infra/public-inbox/+/refs/heads/master/lib/PublicInbox/PktOp.pm)
  permits multiple producers and one consumer.

The client protocol and Xapian helper also assume records:

- [`script/lei`](https://kernel.googlesource.com/pub/scm/infra/public-inbox/+/refs/heads/master/script/lei)
- [`PublicInbox::LEI`](https://kernel.googlesource.com/pub/scm/infra/public-inbox/+/refs/heads/master/lib/PublicInbox/LEI.pm)
- [`PublicInbox::XapClient`](https://kernel.googlesource.com/pub/scm/infra/public-inbox/+/refs/heads/master/lib/PublicInbox/XapClient.pm)
- [`PublicInbox::XapHelper`](https://kernel.googlesource.com/pub/scm/infra/public-inbox/+/refs/heads/master/lib/PublicInbox/XapHelper.pm)
- [`xap_helper.h`](https://kernel.googlesource.com/pub/scm/infra/public-inbox/+/refs/heads/master/lib/PublicInbox/xap_helper.h)

## Darwin evidence

Apple's current XNU source is explicit about the gap:

- The UNIX-domain implementation lists `SEQPACKET` and `RDM` as TODO items in
  [`uipc_usrreq.c`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/uipc_usrreq.c#L176-L182).
- Apple's [`unix(4)` source](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/man/man4/unix.4)
  documents UNIX-domain `SOCK_STREAM` and `SOCK_DGRAM`, but not
  `SOCK_SEQPACKET`.
- XNU processes ancillary control data before branching on stream versus
  datagram handling, so its implementation can pass `SCM_RIGHTS` on local
  datagrams. However, the same source explicitly says datagrams can be lost
  when the receiver queue overflows
  ([`uipc_send`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/uipc_usrreq.c#L498-L546)).

The last point makes `SOCK_DGRAM` an unsuitable semantic replacement for work
or completion records whose loss can corrupt state or leave a command hung.

## Goals

- Run the full `lei` daemon and worker architecture on current supported
  macOS releases, on both Apple Silicon and Intel where available.
- Preserve the native `SOCK_SEQPACKET` path and its performance.
- Detect capabilities at runtime rather than hard-coding operating-system
  names.
- Preserve `SCM_RIGHTS`, command ordering, exact record boundaries, exit
  status, signal forwarding, and disconnect detection.
- Support multiple workers on the fallback path.
- Add no network-facing protocol and no cross-host transport.
- Add no required non-core Perl or platform-specific framework dependency.
- Remain compatible with the project's Perl 5.12 baseline.
- Make the fallback testable on Linux even when `SOCK_SEQPACKET` is available.

## Non-goals

- Removing or deprecating `SOCK_SEQPACKET`.
- Defining a stable external IPC API.
- Supporting untrusted remote clients.
- Replacing the existing serializer.
- Introducing Mach IPC, XPC, launchd activation, or a macOS-only helper.
- Solving unrelated event-notification portability work.

## Alternatives considered

### Substitute `SOCK_STREAM` everywhere

Rejected. Framing alone does not make a shared byte stream behave like a
packet socket.

With multiple readers, one worker can consume a header and a second worker can
consume its payload. With multiple writers, frames can interleave. A stream
`sendmsg(2)` may also return a short count: the descriptors have already been
transferred once, so resending the original message can duplicate data or
descriptors, while sending only the remaining bytes allows another writer to
splice its frame between them.

A cross-process receive lock would still leave the stream desynchronized if a
worker died after consuming part of a record. Locks would also add starvation
and crash-recovery behavior that `SOCK_SEQPACKET` does not require.

### Use `SOCK_DGRAM` socketpairs internally

Not recommended as the reliable fallback. It preserves boundaries and fits
the current shared-reader/shared-writer topology, but XNU documents queue
overflow loss. Datagram sockets also lack orderly EOF semantics, have stricter
message-size limits, and require explicit peer-liveness and shutdown records.

Acknowledgements, retransmission, message identifiers, and duplicate
suppression could create a reliable protocol over datagrams, but non-idempotent
work execution makes this difficult. That machinery would be at least as
complex as a stream broker while retaining weaker kernel guarantees.

### Force one worker on macOS

Useful only as a short-lived diagnostic mode. It reduces the shared-reader
problem but does not remove multiple producers, signal-handler writes, partial
`sendmsg` behavior, or Xapian-helper assumptions. It also silently changes
`lei` performance and is not a complete port.

### Add a platform-specific Mach or XPC transport

Rejected. It would add compiled, macOS-only code and a second IPC model, which
conflicts with public-inbox's compatibility and auditability goals.

### Frame streams and give each endpoint a single owner

Recommended. Connection-oriented streams provide reliable delivery,
backpressure, EOF, and `SCM_RIGHTS` on every target of interest. Changing the
topology removes the ambiguity that framing alone cannot solve.

## Proposed architecture

### Capability selection

Probe functionality, not `$^O`:

1. Attempt `socketpair(AF_UNIX, SOCK_SEQPACKET, 0)` during lazy transport
   initialization.
2. Cache success for the process.
3. Fall back only for errors that mean the socket type is unsupported, such as
   `EPROTONOSUPPORT`, `EPROTOTYPE`, `EOPNOTSUPP`, or the platform-equivalent
   `EINVAL`.
4. Treat `EMFILE`, `ENFILE`, `ENOMEM`, `ENOBUFS`, and permission errors as
   operational failures, not evidence that the protocol is unsupported.

An optional startup self-test may round-trip one temporary descriptor to prove
that the selected descriptor-passing implementation works. The main test suite
must exercise this round trip directly.

A test-only override should force either transport. It should not be a
documented end-user compatibility switch.

### Protocol identity and socket path

Keep the existing sequence-packet pathname for compatible clients. Give the
stream protocol a different version and pathname, for example:

- existing: `5.seq.sock`
- proposed: `6.stream.sock`

Including both protocol version and transport prevents an old client from
connecting to a new daemon with incompatible parsing rules. A future Darwin
implementation of `SOCK_SEQPACKET` can select the native path automatically.

### Stream record format

Use a fixed-size, network-byte-order header. One possible 12-byte layout is:

| Field | Size | Meaning |
| --- | ---: | --- |
| magic/version | 4 bytes | fixed protocol identifier |
| payload length | 4 bytes | unsigned byte length |
| descriptor count | 2 bytes | expected `SCM_RIGHTS` count |
| record type/flags | 2 bytes | command, signal, response, or reserved flags |

Requirements:

- Reject unknown versions, reserved flags, oversized lengths, and impossible
  descriptor counts before allocating payload storage.
- Retain existing per-channel size limits. Large work requests may continue to
  use a separately passed stream, but the control record that introduces that
  stream is itself framed.
- Every logical message, including `STOP`, `CONT`, `WINCH`, `umask`, exit
  status, and empty completion records, is a frame.
- EOF is valid only between frames. EOF in a header or payload is a protocol
  error.
- A zero-length logical payload is represented by a nonempty header; descriptor
  transfer never depends on a zero-byte `sendmsg`.

### Descriptor passing

For each frame:

1. The first `sendmsg` includes the frame header, as much payload as practical,
   and the complete `SCM_RIGHTS` control message.
2. If it returns a short byte count, descriptors are not sent again. Remaining
   bytes are written without ancillary data while the writer retains ownership
   of the stream.
3. The receiver calls `recvmsg` while collecting the header and saves any
   ancillary descriptors in that frame's state.
4. After the header is known, it reads exactly the declared payload length and
   does not read into the next header.
5. The receiver rejects `MSG_CTRUNC`, extra control messages, or a descriptor
   count mismatch.
6. Received descriptors get `FD_CLOEXEC` where the platform cannot request it
   atomically.
7. Every error path closes all descriptors already received for the incomplete
   frame.

### Single-owner invariant

Each stream has exactly one record reader and one record writer. Duplex use is
allowed; ownership is directional.

For a `lei` client connection:

- `script/lei` owns client-to-daemon writes.
- the daemon owns daemon-to-client writes;
- workers report exit status, errors, pager/MUA requests, and barriers to the
  daemon through internal channels rather than writing the client socket;
- signal handlers enqueue work through a self-pipe or another async-safe wakeup
  mechanism instead of interrupting an in-progress framed write.

For `PktOp`:

- allocate a separate producer stream for each worker during worker creation;
- register every consumer end with the same operation table/event loop;
- do not give several processes the same producer stream.

For work queues:

- allocate one stream socketpair per worker;
- retain the producer ends in the parent;
- dispatch a complete frame to one available/writable worker;
- queue in the parent when every worker is backpressured;
- broadcast by sending one frame to each worker's channel;
- reap/close one failed worker without desynchronizing the other workers.

This preserves load distribution without allowing multiple workers to consume
parts of the same record. The implementation may begin with round-robin
selection, but it must respect per-worker backpressure so one slow worker does
not block unrelated workers.

For the Xapian helper:

- migrate it to the same one-channel-per-worker model; or
- until that conversion is complete, decline to start the helper on the stream
  fallback and use the direct Perl Xapian path.

The C and Perl helpers must never be told that a stream is a sequence-packet
socket, and their existing `SO_TYPE` checks should remain meaningful.

### Shutdown and failure behavior

- Closing a client stream cancels or detaches its work exactly as today.
- Parent-to-worker EOF stops only that worker.
- A worker that dies during a frame loses at most its assigned work; it cannot
  corrupt another worker's channel.
- A partial frame is never resynchronized heuristically. Close that channel,
  close received descriptors, report the worker/client failure, and recreate
  the worker if existing policy calls for it.
- Queued but unassigned work remains in the parent and can be assigned to
  another worker.
- Once assignment begins, existing command idempotency rules determine whether
  retry is safe. This RFC does not introduce transparent replay of a possibly
  executed command.

## Compatibility and security considerations

- The native path remains the default wherever its runtime probe succeeds.
- The fallback changes only private, same-user local IPC.
- Existing runtime-directory permissions and `umask(077)` remain required.
- Length and descriptor-count validation are mandatory even though clients are
  trusted; malformed state must not cause unbounded allocation or descriptor
  leaks.
- The frame parser must not deserialize a payload until its complete declared
  length has arrived.
- No new CPAN module should be required. Both existing descriptor-passing
  implementations, `Socket::MsgHdr` and the Inline::C/Spawn path, must be
  covered.
- Transport choice must not be inferred from an untrusted frame. It is fixed
  by the socket path and the socket successfully created by both peers.

## Suggested implementation sequence

1. Add transport capability probing and a force-transport test hook, with no
   behavior change on supported systems.
2. Add a small framed-stream codec and exhaustive unit tests.
3. Convert the `script/lei` to daemon connection, including owner-only writes
   and signal wakeups.
4. Add per-producer framed streams for `PktOp`.
5. Add per-worker framed streams and parent dispatch for `PublicInbox::IPC`
   work queues.
6. Port the Perl and C/C++ Xapian helper paths, or explicitly disable the
   helper until that patch lands.
7. Update `lei-daemon`/`lei-store-format` documentation and the platform notes.

Each step should keep native sequence-packet tests passing. Patches that add
the fallback should be independently force-testable on Linux.

## Upstream email submission plan

public-inbox is email-driven. Its
[`HACKING`](https://kernel.googlesource.com/pub/scm/infra/public-inbox/+/8a3c04bb01b243c28515df77e8ca647ec54dec01/HACKING)
document asks contributors to send patches and request-pull messages to
`meta@public-inbox.org`; the archive is at
[`public-inbox.org/meta`](https://public-inbox.org/meta/).

Before writing the full patch series:

1. Send a plain-text design RFC with a subject similar to:
   `[RFC] lei: reliable IPC fallback for systems without SOCK_SEQPACKET`.
2. State the Homebrew/macOS motivation, include the XNU evidence above, and
   ask specifically whether maintainers prefer per-worker streams or a single
   parent broker abstraction.
3. Include small reproducer output showing that the constant exists but the
   Darwin `socketpair` call fails.
4. Link the archived RFC message from this repository after it appears.
5. Reply-all to the thread; subscription is not required.

After design agreement:

1. Rebase on current upstream `master`.
2. Split the work into reviewable patches following the implementation
   sequence above. Avoid a Homebrew-only downstream patch in the series.
3. Generate inline patches with `git format-patch --cover-letter`; send them as
   plain-text mail with `git send-email` to `meta@public-inbox.org`.
4. Cc authors/reviewers found in the history of `IPC.pm`, `PktOp.pm`, `LEI.pm`,
   and the Xapian helper. Preserve all recipients when replying.
5. Put rationale and tests in each commit message. The cover letter should
   include the compatibility matrix, actual macOS results, forced-stream Linux
   results, and native sequence-packet regression results.
6. For revisions, send a complete rerolled series (`v2`, `v3`, and so on) with
   a concise change log and a range-diff when useful.

Suggested series shape:

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

The exact split should follow maintainer feedback; the design RFC should be
sent before committing to the most invasive worker-dispatch changes.

## Open questions for upstream

1. Should the stream fallback be a reusable `PublicInbox::IPC` record object or
   remain private to the few affected call sites?
2. Does upstream prefer one stream per worker or a dedicated broker process?
3. Is direct Perl Xapian an acceptable first release fallback on Darwin while
   the helper is converted?
4. Should the test-only transport override be an environment variable or an
   internal package variable localized by tests?
5. Which existing worker-restart behavior should apply after a partial stream
   frame or unexpected worker exit?
6. Which macOS release floor is acceptable once real results are available?
