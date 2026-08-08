///|
/// Install a fake injected wallet at `globalThis.ethereum` forwarding EIP-1193
/// requests to Anvil over HTTP JSON-RPC. Anvil's dev accounts are unlocked, so
/// the node answers everything except `wallet_*` methods, which have no
/// node-side counterpart and are emulated here — as is refusing to sign, which
/// the shim does with 4001 for sends from `reject_from`.
///
/// Why a shim rather than a headless extension, and what that does and does not
/// prove: `docs/e2e.md`.
///
/// This is the one `extern "js"` outside `ffi/js`: that package binds the
/// wallet a browser really injected, while this fabricates one. Test-only, and
/// excluded from the published archive — see `docs/e2e.md`.
extern "js" fn install_wallet(rpc_url : String, reject_from : String) -> Unit =
  #| (rpcUrl, rejectFrom) => {
  #|   // tests share one JS context and run concurrently, so the wallet is
  #|   // installed once and never removed
  #|   if (globalThis.ethereum) return
  #|   let nextId = 0
  #|   const call = async (method, params) => {
  #|     const res = await fetch(rpcUrl, {
  #|       method: 'POST',
  #|       headers: { 'content-type': 'application/json' },
  #|       body: JSON.stringify({ jsonrpc: '2.0', id: ++nextId, method, params }),
  #|     })
  #|     if (!res.ok) throw { code: -32603, message: `HTTP ${res.status} from ${rpcUrl}` }
  #|     const body = await res.json()
  #|     if (body.error) {
  #|       // `data` is forwarded because the revert a contract raised is in it,
  #|       // and a wallet that dropped it would leave the SDK nothing to decode
  #|       throw {
  #|         code: typeof body.error.code === 'number' ? body.error.code : -32603,
  #|         message: String(body.error.message ?? 'rpc error'),
  #|         data: body.error.data,
  #|       }
  #|     }
  #|     return body.result === undefined ? null : body.result
  #|   }
  #|   // the node's own chain, asked for once: it cannot change for its lifetime
  #|   let chainId = null
  #|   const currentChain = async () =>
  #|     chainId ??= BigInt(await call('eth_chainId', [])).toString()
  #|   const added = new Set()
  #|   // concurrent tests are otherwise handed the same nonce; a real wallet
  #|   // prompts for one transaction at a time, so serializing is also faithful
  #|   let queue = Promise.resolve()
  #|   const send = (method, args) => {
  #|     const done = queue.then(() => call(method, args))
  #|     queue = done.catch(() => {})
  #|     return done
  #|   }
  #|   globalThis.ethereum = {
  #|     isMetaMask: true,
  #|     request: async ({ method, params }) => {
  #|       const args = params ?? []
  #|       switch (method) {
  #|         case 'eth_requestAccounts':
  #|           return call('eth_accounts', [])
  #|         case 'eth_sendTransaction':
  #|           // the one thing a node cannot do: refuse on the user's behalf.
  #|           // a send from `reject_account()` stands in for declining it
  #|           if (args[0]?.from?.toLowerCase() === rejectFrom) {
  #|             throw { code: 4001, message: 'User rejected the request.' }
  #|           }
  #|           return send(method, args)
  #|         case 'wallet_addEthereumChain':
  #|           added.add(BigInt(args[0].chainId).toString())
  #|           return null
  #|         case 'wallet_switchEthereumChain': {
  #|           const want = BigInt(args[0].chainId).toString()
  #|           if (added.has(want) || want === await currentChain()) return null
  #|           throw { code: 4902, message: `Unrecognized chain ID ${want}` }
  #|         }
  #|         default:
  #|           return call(method, args)
  #|       }
  #|     },
  #|   }
  #| }
