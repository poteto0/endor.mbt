///|
/// One call sitting in the window: what was asked, under which id, and the
/// answer the sender writes back into it.
priv struct Pending {
  id : Int
  method_name : String
  params : Json
  mut answer : Result[Json, @provider.ProviderError]?
}

///|
/// The window itself. No background task and no lifecycle: `HttpProvider` is a
/// value that `at()` hands back, and a resident flusher would make it a
/// resource that has to be closed. The call that finds the window empty becomes
/// the sender instead, and the rest wait on `flushed` for their own answer.
///
/// `filled` is the other direction: a call that fills the window to `max_size`
/// wakes the sender early, so a burst does not sit out the whole `wait`.
priv struct Window {
  policy : @provider.BatchPolicy
  pending : Array[Pending]
  flushed : @cond_var.Cond
  filled : @cond_var.Cond
  mut sending : Bool
}

///|
fn Window::new(policy : @provider.BatchPolicy) -> Window {
  Window::{
    policy,
    pending: [],
    flushed: @cond_var.Cond(),
    filled: @cond_var.Cond(),
    sending: false,
  }
}

///|
/// Take a call back out of the window: it gave up before the window closed, so
/// the next batch should not carry a request nobody is waiting for. Ids are
/// unique within a provider, so the id is the identity.
fn Window::drop(self : Window, slot : Pending) -> Unit {
  self.pending.retain(other => other.id != slot.id)
}

///|
/// Put this call in the window and wait for the answer that comes back for its
/// id.
///
/// The loop is the whole cancellation story. Every pass asks three questions in
/// order: is my answer here, is somebody sending, and — if not — am I now the
/// sender. A sender that is cancelled while the window is still open hands the
/// role back and broadcasts, so the next one awake picks it up; nothing in the
/// window is stranded by the departure of the call that happened to be first.
async fn[T : HttpTransport] HttpProvider::send_batched(
  self : HttpProvider[T],
  window : Window,
  method_name~ : String,
  params~ : Json,
) -> Json raise @provider.ProviderError {
  let id = self.next_id
  self.next_id = id + 1
  let slot = Pending::{ id, method_name, params, answer: None }
  window.pending.push(slot)
  if window.pending.length() >= window.policy.max_size() {
    window.filled.broadcast()
  }
  for ;; {
    match slot.answer {
      Some(Ok(result)) => return result
      Some(Err(e)) => raise e
      None => ()
    }
    if window.sending {
      window.flushed.wait() catch {
        cancelled => {
          window.drop(slot)
          raise @provider.Transport(
            "the batched \{method_name} was cancelled: \{cancelled}",
          )
        }
      }
    } else {
      window.sending = true
      // Whatever the send did, the role goes back and the rest are woken: one
      // of them promotes itself on the next pass.
      let outcome = try self.flush(window) catch {
        e => Err(e)
      } noraise {
        _ => Ok(())
      }
      window.sending = false
      window.flushed.broadcast()
      // A failure that never reached the slots — a cancelled window — is this
      // call's own. One that did is already sitting in `answer`, for everyone.
      if outcome is Err(e) && slot.answer is None {
        window.drop(slot)
        raise e
      }
    }
  }
}

///|
/// Hold the window open, then send what is in it.
///
/// The drain and the POST are protected from cancellation together, because
/// between them the calls in `batch` are in no window any more: if the sender
/// went away here, nothing would send them and nothing would wake them.
async fn[T : HttpTransport] HttpProvider::flush(
  self : HttpProvider[T],
  window : Window,
) -> Unit raise @provider.ProviderError {
  if window.pending.length() < window.policy.max_size() {
    try
      @async.with_timeout_opt(window.policy.wait(), () => window.filled.wait())
      |> ignore
    catch {
      cancelled =>
        raise @provider.Transport(
          "the batch window was cancelled: \{cancelled}",
        )
    }
  }
  // Nothing awaits between here and the POST, so the drain cannot be the place
  // a cancellation strands the batch.
  let batch = []
  let take = window.policy.max_size().min(window.pending.length())
  for _ in 0..<take {
    batch.push(window.pending.remove(0))
  }
  if batch.is_empty() {
    return
  }
  // The cancellation this delays until the answers are written lands on
  // whatever the sender awaits next, outside the window.
  @async.protect_from_cancel(() => self.deliver(batch)) catch {
    cancelled =>
      raise @provider.Transport("the batch sender was cancelled: \{cancelled}")
  }
}

///|
/// POST one batch and write every answer into the call it belongs to.
///
/// It raises nothing: a failure of the whole POST is *each* call's failure, and
/// a caller waiting on `flushed` has to find something in its slot or it waits
/// forever.
async fn[T : HttpTransport] HttpProvider::deliver(
  self : HttpProvider[T],
  batch : Array[Pending],
) -> Unit {
  let answers = self.post_batch(batch) catch {
    e => {
      for slot in batch {
        slot.answer = Some(Err(e))
      }
      return
    }
  }
  for slot in batch {
    slot.answer = Some(
      answers
      .get(slot.id)
      .unwrap_or(
        Err(
          @provider.MalformedResponse(
            "the batch answered nothing for id \{slot.id} (\{slot.method_name})",
          ),
        ),
      ),
    )
  }
}

///|
/// One POST of a JSON-RPC array, read back as `id` → answer.
///
/// The retry sits here rather than around each call: N calls in one window are
/// one POST, and retrying them separately would turn a single `429` into N
/// resends of a request that was never sent N times.
async fn[T : HttpTransport] HttpProvider::post_batch(
  self : HttpProvider[T],
  batch : Array[Pending],
) -> Map[Int, Result[Json, @provider.ProviderError]] raise @provider.ProviderError {
  let payload = Json::array(
    batch.map(slot => {
      Json::object({
        "jsonrpc": Json::string("2.0"),
        "id": Json::number(slot.id.to_double()),
        "method": Json::string(slot.method_name),
        "params": slot.params,
      })
    }),
  )
  // Every call in a window is idempotent — `request` keeps the send-once ones
  // out — so the batch as a whole is, and this name is only what a cancellation
  // message reads back.
  let parsed = @provider.retry_loop(
    method_name="a batch of \{batch.length()} calls",
    policy=self.retry,
    () => self.send_batch_once(payload),
  )
  guard parsed is Array(elements) else {
    raise @provider.MalformedResponse("batch response is not an array")
  }
  let sent = Set::from_array(batch.map(slot => slot.id))
  let answers : Map[Int, Result[Json, @provider.ProviderError]] = Map([])
  for element in elements {
    guard element is Object(fields) else {
      raise @provider.MalformedResponse(
        "a batch answer is not an object: \{element.stringify()}",
      )
    }
    guard fields.get("id") is Some(Number(raw, ..)) else {
      raise @provider.MalformedResponse(
        "a batch answer carries no id: \{element.stringify()}",
      )
    }
    let id = raw.to_int()
    // An id that was never sent, or one answered twice, says the mapping cannot
    // be trusted at all — and a wrong mapping hands one call another's answer,
    // silently. The whole batch fails instead.
    guard sent.contains(id) else {
      raise @provider.MalformedResponse(
        "the batch answered an id it was not sent: \{id}",
      )
    }
    guard !answers.contains(id) else {
      raise @provider.MalformedResponse("the batch answered id \{id} twice")
    }
    answers[id] = if fields.get("error") is Some(error) && !(error is Null) {
      Err(@provider.ProviderError::from_error_object(error))
    } else if fields.get("result") is Some(result) {
      Ok(result)
    } else {
      raise @provider.MalformedResponse(
        "a batch answer carries neither result nor error: \{element.stringify()}",
      )
    }
  }
  answers
}

///|
/// One attempt at the array: POST, parse, and tell an array of answers from the
/// single error object a node returns when it refused the batch as a whole.
///
/// That object is not one call's failure, so it is raised rather than mapped
/// into an element — which also puts a `{ code: 429 }` inside a 200 back in
/// front of the retry, where it belongs.
async fn[T : HttpTransport] HttpProvider::send_batch_once(
  self : HttpProvider[T],
  payload : Json,
) -> Json raise @provider.ProviderError {
  let body = self.transport.post(payload.stringify())
  let parsed = @json.parse(body) catch {
    e => raise @provider.MalformedResponse("batch response is not JSON: \{e}")
  }
  match parsed {
    Array(_) => parsed
    Object(fields) =>
      if fields.get("error") is Some(error) && !(error is Null) {
        raise @provider.ProviderError::from_error_object(error)
      } else {
        raise @provider.MalformedResponse(
          "batch response is a single object carrying no error: \{body}",
        )
      }
    _ =>
      raise @provider.MalformedResponse(
        "batch response is neither an array nor an error object: \{body}",
      )
  }
}
