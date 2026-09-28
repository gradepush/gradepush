import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/gradepush"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const CopyToClipboard = {
  mounted() {
    this.button = this.el.querySelector("button")
    this.label = this.button.getAttribute("aria-label")
    this.reset = () => {
      clearTimeout(this.timer)
      this.el.querySelector("[data-copy-icon]").hidden = false
      this.el.querySelector("[data-copy-success-icon]").hidden = true
      this.el.querySelector("[data-copy-error-icon]").hidden = true
      this.el.querySelector("[data-copy-tooltip]").hidden = true
      this.el.querySelector('[role="status"]').textContent = ""
      this.button.setAttribute("aria-label", this.label)
      this.button.title = this.label
    }
    this.copy = async () => {
      if (this.button.disabled || this.pending) return
      this.pending = true
      this.reset()
      let success = false
      try {
        await navigator.clipboard.writeText(this.el.dataset.copy)
        success = true
      } catch {
        if (!this.disposed) {
          const code = this.el.querySelector("code")
          if (code) {
            const range = document.createRange()
            range.selectNodeContents(code)
            const selection = window.getSelection()
            selection.removeAllRanges()
            selection.addRange(range)
          }
        }
      }
      this.pending = false
      if (this.disposed) return
      const message = success ? this.el.dataset.success : this.el.dataset.error
      this.el.querySelector("[data-copy-icon]").hidden = true
      this.el.querySelector("[data-copy-success-icon]").hidden = !success
      this.el.querySelector("[data-copy-error-icon]").hidden = success
      const tooltip = this.el.querySelector("[data-copy-tooltip]")
      tooltip.textContent = message
      tooltip.hidden = false
      this.el.querySelector('[role="status"]').textContent = message
      this.button.setAttribute("aria-label", message)
      this.button.removeAttribute("title")
      this.timer = setTimeout(this.reset, success ? 2000 : 5000)
    }
    this.button.addEventListener("click", this.copy)
  },
  updated() { this.reset() },
  destroyed() {
    this.disposed = true
    clearTimeout(this.timer)
    this.button.removeEventListener("click", this.copy)
  },
}
const HeaderDisclosure = {
  mounted() {
    this.closeOutside = event => {
      if (!this.el.contains(event.target)) this.el.open = false
    }
    this.closeOnEscape = event => {
      if (event.key === "Escape" && this.el.open) {
        this.el.open = false
        this.el.querySelector("summary").focus()
      }
    }
    this.closeOnNavigation = event => {
      if (event.target.closest("a")) this.el.open = false
    }
    document.addEventListener("pointerdown", this.closeOutside)
    document.addEventListener("keydown", this.closeOnEscape)
    this.el.addEventListener("click", this.closeOnNavigation)
  },
  destroyed() {
    document.removeEventListener("pointerdown", this.closeOutside)
    document.removeEventListener("keydown", this.closeOnEscape)
    this.el.removeEventListener("click", this.closeOnNavigation)
  },
}
let setupTokenFromLink = null
if (window.location.pathname === "/setup" && window.location.hash) {
  setupTokenFromLink = new URLSearchParams(window.location.hash.slice(1)).get("setup_token")
  window.history.replaceState(
    window.history.state,
    "",
    window.location.pathname + window.location.search,
  )
}

const SetupToken = {
  mounted() {
    const token = setupTokenFromLink
    setupTokenFromLink = null
    if (!token) return
    if (new TextEncoder().encode(token).length > 128) {
      this.pushEvent("invalid_setup_token_link", {})
      return
    }

    const input = this.el.querySelector('input[name="setup[setup_token]"]')
    if (!input) return

    input.value = token
    input.dispatchEvent(new Event("input", {bubbles: true}))
  },
}
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, CopyToClipboard, HeaderDisclosure, SetupToken},
})

topbar.config({barColors: {0: "#2052F2"}, shadowColor: "transparent"})
window.addEventListener("phx:focus-invalid", ({detail: {id}}) => {
  requestAnimationFrame(() => {
    document.getElementById(id)?.querySelector('[aria-invalid="true"]')?.focus()
  })
})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

liveSocket.connect()

window.liveSocket = liveSocket

if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    reloader.enableServerLogs()

    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
