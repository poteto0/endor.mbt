---
title: Retries
description: Both providers already retry the failures worth retrying — what the defaults are, how to change them, and which calls are sent exactly once.
---

# Retries

A `429` from a hosted RPC, a socket that closed mid-request, a node that
answered `-32005`: none of those is an answer, and all of them go away on their
own. Every provider in the SDK sends such a request again, backing off between
attempts, before the failure ever reaches your `catch`.

This is **on by default**. There is nothing to wrap and nothing to enable:

```moonbit
async fn already_retrying(url : String) -> Unit raise {
  let node = @endpoint.at(url)
  // three retries behind this one line, if it needs them
  println("chain \{@provider.chain_id(node).to_uint64()}")
}
```

The defaults are viem's, so a dapp ported from it behaves the same way:

|              |                          |
| ------------ | ------------------------ |
| first wait   | 150 ms                   |
| growth       | doubling, capped at 2 s  |
| retries      | 3 — four attempts in all |

Which failures are retried at all is `ProviderError::is_retryable()`, whose
table lives on the [Errors](./errors/#what-to-retry) page. The line it draws:
a failure that is about *this attempt* is tried again, and a failure that is
already decided — a rejected prompt, a revert, a wrong API key — is handed
straight back.

## Changing the policy

`with_retry` takes a `RetryPolicy` and gives back a provider that uses it. It is
on both providers, and it copies rather than mutates, so the one you were
holding is unchanged:

```moonbit
async fn patient_node(url : String) -> Unit raise {
  let node = @endpoint
    .at(url)
    .with_retry(
      @provider.RetryPolicy::new(
        strategy=ExponentialDelay(initial=500, factor=2.0, maximum=10_000),
        max_retry=6,
      ),
    )
  println("chain \{@provider.chain_id(node).to_uint64()}")
}
```

`max_retry` counts the attempts *after* the first one: `max_retry=6` is seven
requests at worst. `strategy` is `moonbitlang/async`'s `RetryMethod` —
`Immediate`, `FixedDelay(ms)` or `ExponentialDelay` as above — and either
argument can be left out to keep its default. Naming one of those constructors
means `"moonbitlang/async"` in your own `moon.pkg`; nothing else on this page
does.

Two policies are named: `RetryPolicy::default()`, which is what every provider
starts with, and `RetryPolicy::none()`, which is the one to reach for when **you
already retry**. Two backoffs stacked on each other multiply — a queue that
gives a failed job four attempts, over a provider that gives each of them four,
is sixteen requests for one call, and the waiting multiplies with them. Turn one
of the two off, and it should be this one:

```moonbit
async fn my_layer_owns_the_retrying(url : String) -> Unit raise {
  let node = @endpoint.at(url).with_retry(@provider.RetryPolicy::none())
  println("chain \{@provider.chain_id(node).to_uint64()}")
}
```

## What is never retried

A retry behind a wallet is a **second dialog in the user's face**, for a request
they may already have answered. So the calls that open one are sent exactly
once, whatever the policy says and whatever the failure looked like:

- every `wallet_*` method — `wallet_switchEthereumChain` and
  `wallet_addEthereumChain`, which is what `switch_chain` and `add_chain` send
- `eth_requestAccounts`
- `personal_sign` and `eth_signTypedData_v4`
- `eth_sendTransaction` — the wallet builds and signs it, so a resend is a
  second transaction, not the same one

This is a **deliberate difference from viem**, whose retry never looks at the
method name.

`eth_sendRawTransaction` is deliberately *not* on that list. The transaction is
already signed by then, so a resend is byte-identical and hashes the same: the
node either accepts the one it lost or drops the duplicate it already has.
Sending a signed transaction is therefore retried like any other read.

## When the node says how long

A `429` or a `503` from a node may carry a `Retry-After`. When it does, and it
is a plain number of seconds, that wins: the node saying how long it wants to be
left alone beats any backoff guessed from outside, and the loop waits exactly
that instead of its own delay. The header's HTTP-date form is not read — it
needs a clock to compare against, and is not what a rate limiter sends — so a
response carrying one backs off as if it had said nothing.

Past a minute it stops waiting and hands the failure back. A node asking for
longer than that is not asking for a moment — it is saying the quota is spent —
and holding your call for an hour helps nobody. The value stays on the error, so
a caller who does want to wait that long can read it and decide for itself:

```moonbit
async fn read_the_wait(url : String) -> Unit {
  try {
    let node = @endpoint.at(url)
    println("chain \{@provider.chain_id(node).to_uint64()}")
  } catch {
    HttpStatus(code=429, info~, ..) =>
      match info.retry_after() {
        Some(seconds) => println("rate limited for \{seconds}s")
        None => println("rate limited")
      }
    e => println(e.message())
  }
}
```

## What it does not do

**No jitter.** Several requests that hit the same `429` together back off by the
same amount and come back together. With one provider and a handful of calls
that is not worth solving; if you are fanning out hundreds of requests at once,
spread them yourself before they leave.

**It does not outlive a cancellation.** A retry that is waiting when its task is
cancelled stops waiting and raises `Transport` saying so, rather than holding the
cancellation open for another backoff; one cancelled before the wait begins
re-raises the failure it was about to retry, unchanged.

**It does not make a failure disappear.** After the last attempt the original
error is raised — the same variant, from the same source — so everything on the
[Errors](./errors/) page reads the same whether it was retried once or four
times.
