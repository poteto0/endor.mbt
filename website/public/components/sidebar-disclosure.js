// The sidebar's keyboard behaviour.
//
// astra's theme renders each sidebar group as a `<details class="sidebar-collapse">`
// and hard-codes this URL into the `<aside>` it wraps them in, so the file has to
// exist for the page to hydrate without a 404. Opening and closing already works
// natively; what is missing without this is `aria-expanded` staying truthful and
// arrow-key movement between groups.
//
// Progressive enhancement only: the sidebar is fully usable if this never loads.

/** @param {HTMLElement} root the `<aside>` astra hydrated */
export function hydrate(root) {
  const groups = Array.from(root.querySelectorAll('details.sidebar-collapse'))
  const summaries = groups
    .map((group) => group.querySelector(':scope > summary'))
    .filter(Boolean)

  const focusAt = (index) => {
    if (summaries.length === 0) return
    // wrap, so holding an arrow key cycles rather than dead-ending
    const wrapped = (index + summaries.length) % summaries.length
    summaries[wrapped].focus()
  }

  groups.forEach((group) => {
    const summary = group.querySelector(':scope > summary')
    if (!summary) return

    // `<summary>` reports its state to a screen reader through aria-expanded,
    // and the browser does not update it — the `toggle` event is where it can
    // be kept in step with `details.open`.
    const sync = () => {
      summary.setAttribute('aria-expanded', group.open ? 'true' : 'false')
    }
    group.addEventListener('toggle', sync)
    sync()

    summary.addEventListener('keydown', (event) => {
      // Enter and Space are the browser's own; only movement is added here
      const at = summaries.indexOf(summary)
      if (at === -1) return
      switch (event.key) {
        case 'ArrowDown':
          event.preventDefault()
          focusAt(at + 1)
          break
        case 'ArrowUp':
          event.preventDefault()
          focusAt(at - 1)
          break
        case 'Home':
          event.preventDefault()
          focusAt(0)
          break
        case 'End':
          event.preventDefault()
          focusAt(summaries.length - 1)
          break
        default:
          break
      }
    })
  })

  root.dataset.hydrated = 'true'
}

export default hydrate
