// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/work_tree"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const Hooks = {
  FocusEnd: {
    mounted() {
      const input = this.el
      input.focus()
      input.setSelectionRange(input.value.length, input.value.length)
    }
  },
  InlineEditTextarea: {
    mounted() {
      const textarea = this.el
      textarea.focus()
      // Select all text so user can start typing to replace
      textarea.select()

      textarea.addEventListener("keydown", (e) => {
        if (e.key === "Enter" && !e.shiftKey) {
          e.preventDefault()
          textarea.form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
        }
      })
    }
  },
  DisableTab: {
    mounted() {
      this.handleKeydown = (e) => {
        if (e.key === "Tab") {
          e.preventDefault()
        }
      }
      window.addEventListener("keydown", this.handleKeydown)
    },
    destroyed() {
      window.removeEventListener("keydown", this.handleKeydown)
    }
  },
  NodeContextMenu: {
    mounted() {
      this.el.addEventListener("contextmenu", (e) => {
        e.preventDefault()
        e.stopPropagation()
        const nodeId = this.el.dataset.nodeId
        if (nodeId) {
          // Get viewport dimensions
          const viewportWidth = window.innerWidth
          const viewportHeight = window.innerHeight

          // Estimated menu dimensions (w-56 = 224px, typical height ~400px)
          const menuWidth = 224
          const menuHeight = 400

          // Calculate position, adjusting if menu would go off-screen
          let x = e.clientX
          let y = e.clientY

          // Adjust horizontal position if menu would overflow right edge
          if (x + menuWidth > viewportWidth - 16) {
            x = viewportWidth - menuWidth - 16
          }

          // Adjust vertical position if menu would overflow bottom edge
          // Account for bottom hints bar (~50px)
          if (y + menuHeight > viewportHeight - 60) {
            y = viewportHeight - menuHeight - 60
          }

          // Ensure menu doesn't go off the top or left edges
          x = Math.max(16, x)
          y = Math.max(16, y)

          this.pushEvent("open_context_menu", { id: nodeId, x: x, y: y })
        }
      })

      this.el.addEventListener("dblclick", (e) => {
        e.preventDefault()
        e.stopPropagation()
        const nodeId = this.el.dataset.nodeId
        if (nodeId) {
          this.pushEvent("start_inline_edit", { id: nodeId })
        }
      })
    }
  },
  MindMapCanvas: {
    mounted() {
      this.canvas = this.el.querySelector("#mind-map-canvas")
      this.rootId = this.el.dataset.rootId

      // Viewport state
      this.panX = 0
      this.panY = 0
      this.zoom = 1.0
      this.minZoom = 0.25
      this.maxZoom = 2.0
      this.zoomStep = 0.1

      // Panning state
      this.isPanning = false
      this.startX = 0
      this.startY = 0
      this.startPanX = 0
      this.startPanY = 0
      this.spacePressed = false

      // Debounce timer for localStorage
      this.saveTimer = null

      // Load saved viewport state
      this.loadViewportState()

      // If no saved state, center the root node
      if (!this.hasSavedState) {
        this.centerRootNode()
      }

      this.applyTransform()
      this.updateZoomDisplay()

      // Bind event handlers
      this.handleWheel = this.handleWheel.bind(this)
      this.handleMouseDown = this.handleMouseDown.bind(this)
      this.handleMouseMove = this.handleMouseMove.bind(this)
      this.handleMouseUp = this.handleMouseUp.bind(this)
      this.handleKeyDown = this.handleKeyDown.bind(this)
      this.handleKeyUp = this.handleKeyUp.bind(this)

      // Attach event listeners
      this.el.addEventListener("wheel", this.handleWheel, { passive: false })
      this.el.addEventListener("mousedown", this.handleMouseDown)
      window.addEventListener("mousemove", this.handleMouseMove)
      window.addEventListener("mouseup", this.handleMouseUp)
      window.addEventListener("keydown", this.handleKeyDown)
      window.addEventListener("keyup", this.handleKeyUp)

      // Listen for scroll-to-node events from LiveView
      this.handleEvent("scroll-to-node", ({ id }) => {
        this.scrollToNode(id)
      })

      // Listen for open-focused-node-link events from LiveView (keyboard shortcut 'g')
      // We read the link from the DOM data attribute to open it directly
      this.handleEvent("open-focused-node-link", ({ node_id }) => {
        const nodeEl = this.canvas?.querySelector(`#node-${node_id}`)
        const url = nodeEl?.dataset?.nodeLink
        console.log("open-focused-node-link event for node:", node_id, "URL:", url)
        if (url) {
          // Open using window.open - since we're triggered by keyboard,
          // browser might still block, but we try our best
          window.open(url, '_blank', 'noopener,noreferrer')
        }
      })

      // Expose hook methods for onclick handlers
      this.el.__liveViewHook = this
    },

    updated() {
      // Re-apply transform and update display after LiveView patches the DOM
      this.canvas = this.el.querySelector("#mind-map-canvas")
      this.applyTransform()
      this.updateZoomDisplay()
    },

    destroyed() {
      this.el.removeEventListener("wheel", this.handleWheel)
      this.el.removeEventListener("mousedown", this.handleMouseDown)
      window.removeEventListener("mousemove", this.handleMouseMove)
      window.removeEventListener("mouseup", this.handleMouseUp)
      window.removeEventListener("keydown", this.handleKeyDown)
      window.removeEventListener("keyup", this.handleKeyUp)
      if (this.saveTimer) clearTimeout(this.saveTimer)
    },

    handleWheel(e) {
      e.preventDefault()

      // Shift + wheel = horizontal pan, otherwise zoom at cursor position
      if (e.shiftKey) {
        // Shift + wheel = horizontal pan
        this.panX -= e.deltaY
        this.applyTransform()
        this.saveViewportState()
      } else if (e.ctrlKey || e.metaKey) {
        // Ctrl/Cmd + wheel = pan (vertical and horizontal)
        this.panX -= e.deltaX
        this.panY -= e.deltaY
        this.applyTransform()
        this.saveViewportState()
      } else {
        // Normal wheel = zoom at cursor position
        const rect = this.el.getBoundingClientRect()
        const mouseX = e.clientX - rect.left
        const mouseY = e.clientY - rect.top

        // Calculate zoom
        const delta = e.deltaY > 0 ? -this.zoomStep : this.zoomStep
        const newZoom = Math.min(this.maxZoom, Math.max(this.minZoom, this.zoom + delta))

        if (newZoom !== this.zoom) {
          // Zoom towards cursor position
          const zoomRatio = newZoom / this.zoom
          this.panX = mouseX - (mouseX - this.panX) * zoomRatio
          this.panY = mouseY - (mouseY - this.panY) * zoomRatio
          this.zoom = newZoom

          this.applyTransform()
          this.updateZoomDisplay()
          this.saveViewportState()
        }
      }
    },

    handleMouseDown(e) {
      // Check if clicking on empty space (container, canvas, or SVG layer - not on a node)
      const isEmptySpace = e.target === this.el ||
                           e.target === this.canvas ||
                           e.target.classList.contains("mind-map-svg") ||
                           e.target.tagName === "svg" ||
                           e.target.tagName === "path" ||
                           e.target.tagName === "g"

      // Middle mouse button, space + left click, or left click on empty space = start panning
      if (e.button === 1 || (e.button === 0 && this.spacePressed) || (e.button === 0 && isEmptySpace)) {
        e.preventDefault()
        this.isPanning = true
        this.startX = e.clientX
        this.startY = e.clientY
        this.startPanX = this.panX
        this.startPanY = this.panY
        this.el.style.cursor = "grabbing"
      }
    },

    handleMouseMove(e) {
      if (this.isPanning) {
        const dx = e.clientX - this.startX
        const dy = e.clientY - this.startY
        this.panX = this.startPanX + dx
        this.panY = this.startPanY + dy
        this.applyTransform()
      }
    },

    handleMouseUp(e) {
      if (this.isPanning) {
        this.isPanning = false
        this.el.style.cursor = this.spacePressed ? "grab" : ""
        this.saveViewportState()
      }
    },

    handleKeyDown(e) {
      // Check if target is an input/textarea (with safety check for non-element targets)
      const isInputTarget = e.target?.matches?.("input, textarea")

      // Space key for pan mode
      if (e.code === "Space" && !isInputTarget) {
        if (!this.spacePressed) {
          this.spacePressed = true
          this.el.style.cursor = "grab"
        }
      }

      // Zoom shortcuts (only when not in input)
      if (!isInputTarget) {
        if (e.key === "=" || e.key === "+") {
          e.preventDefault()
          this.zoomTo(this.zoom + this.zoomStep)
        } else if (e.key === "-") {
          e.preventDefault()
          this.zoomTo(this.zoom - this.zoomStep)
        } else if (e.key === "0" && (e.ctrlKey || e.metaKey)) {
          e.preventDefault()
          this.zoomTo(1.0)
        }
      }
    },

    handleKeyUp(e) {
      if (e.code === "Space") {
        this.spacePressed = false
        if (!this.isPanning) {
          this.el.style.cursor = ""
        }
      }
    },

    zoomTo(newZoom) {
      newZoom = Math.min(this.maxZoom, Math.max(this.minZoom, newZoom))
      if (newZoom !== this.zoom) {
        // Zoom towards center of viewport
        const rect = this.el.getBoundingClientRect()
        const centerX = rect.width / 2
        const centerY = rect.height / 2

        const zoomRatio = newZoom / this.zoom
        this.panX = centerX - (centerX - this.panX) * zoomRatio
        this.panY = centerY - (centerY - this.panY) * zoomRatio
        this.zoom = newZoom

        this.applyTransform()
        this.updateZoomDisplay()
        this.saveViewportState()
      }
    },

    applyTransform() {
      if (this.canvas) {
        this.canvas.style.transform = `translate(${this.panX}px, ${this.panY}px) scale(${this.zoom})`
      }
    },

    updateZoomDisplay() {
      const display = this.el.querySelector("[data-zoom-level]")
      if (display) {
        display.textContent = `${Math.round(this.zoom * 100)}%`
      }
    },

    centerRootNode() {
      const rootNode = this.canvas?.querySelector(".mind-map-node")
      if (!rootNode) return

      const rect = this.el.getBoundingClientRect()

      // Calculate canvas position of root node (before any transforms)
      const rootX = parseFloat(rootNode.style.left) || 0
      const rootY = parseFloat(rootNode.style.top) || 0
      const rootWidth = parseFloat(rootNode.style.width) || 200
      const rootHeight = parseFloat(rootNode.style.height) || 44

      // Center the root node in the viewport
      this.panX = (rect.width / 2) - rootX - (rootWidth / 2)
      this.panY = (rect.height / 2) - rootY - (rootHeight / 2)
    },

    scrollToNode(nodeId) {
      const node = this.canvas?.querySelector(`#node-${nodeId}`)
      if (!node) return

      const rect = this.el.getBoundingClientRect()
      const nodeX = parseFloat(node.style.left) || 0
      const nodeY = parseFloat(node.style.top) || 0
      const nodeWidth = parseFloat(node.style.width) || 200
      const nodeHeight = parseFloat(node.style.height) || 44

      // Calculate where node is in viewport coordinates
      const nodeViewX = nodeX * this.zoom + this.panX
      const nodeViewY = nodeY * this.zoom + this.panY
      const nodeViewWidth = nodeWidth * this.zoom
      const nodeViewHeight = nodeHeight * this.zoom

      const padding = 100
      let needsUpdate = false

      // Check if node is outside viewport bounds
      if (nodeViewX < padding) {
        this.panX += (padding - nodeViewX)
        needsUpdate = true
      } else if (nodeViewX + nodeViewWidth > rect.width - padding) {
        this.panX -= (nodeViewX + nodeViewWidth - rect.width + padding)
        needsUpdate = true
      }

      if (nodeViewY < padding) {
        this.panY += (padding - nodeViewY)
        needsUpdate = true
      } else if (nodeViewY + nodeViewHeight > rect.height - padding) {
        this.panY -= (nodeViewY + nodeViewHeight - rect.height + padding)
        needsUpdate = true
      }

      if (needsUpdate) {
        this.applyTransform()
        this.saveViewportState()
      }
    },

    loadViewportState() {
      this.hasSavedState = false
      if (!this.rootId) return

      try {
        const saved = localStorage.getItem(`work_tree:viewport:${this.rootId}`)
        if (saved) {
          const state = JSON.parse(saved)
          this.panX = state.panX ?? 0
          this.panY = state.panY ?? 0
          this.zoom = state.zoom ?? 1.0
          this.hasSavedState = true
        }
      } catch (e) {
        console.warn("Failed to load viewport state:", e)
      }
    },

    saveViewportState() {
      if (!this.rootId) return

      // Debounce saves
      if (this.saveTimer) clearTimeout(this.saveTimer)
      this.saveTimer = setTimeout(() => {
        try {
          localStorage.setItem(`work_tree:viewport:${this.rootId}`, JSON.stringify({
            panX: this.panX,
            panY: this.panY,
            zoom: this.zoom,
            lastUpdated: Date.now()
          }))
        } catch (e) {
          console.warn("Failed to save viewport state:", e)
        }
      }, 200)
    },

    // Public methods for zoom controls
    zoomIn() {
      this.zoomTo(this.zoom + this.zoomStep)
    },

    zoomOut() {
      this.zoomTo(this.zoom - this.zoomStep)
    },

    resetZoom() {
      this.zoomTo(1.0)
    },

    fitToView() {
      this.centerRootNode()
      this.zoom = 1.0
      this.applyTransform()
      this.updateZoomDisplay()
      this.saveViewportState()
    }
  }
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
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

