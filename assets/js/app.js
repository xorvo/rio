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
      // Handle click with modifier key detection
      this.el.addEventListener("click", (e) => {
        const nodeId = this.el.dataset.nodeId
        if (nodeId) {
          this.pushEvent("focus_node", {
            id: nodeId,
            metaKey: e.metaKey,
            ctrlKey: e.ctrlKey
          })
        }
      })

      this.el.addEventListener("contextmenu", (e) => {
        e.preventDefault()
        e.stopPropagation()
        const nodeId = this.el.dataset.nodeId
        if (nodeId) {
          // Pre-adjust position to keep menu within viewport
          // Menu dimensions (approximate, includes expanded submenu)
          const menuWidth = 240
          const menuHeight = 520
          const padding = 16
          const bottomPadding = 60

          let x = e.clientX
          let y = e.clientY

          // Adjust if menu would overflow right edge
          if (x + menuWidth > window.innerWidth - padding) {
            x = window.innerWidth - menuWidth - padding
          }

          // Adjust if menu would overflow bottom edge
          if (y + menuHeight > window.innerHeight - bottomPadding) {
            y = window.innerHeight - menuHeight - bottomPadding
          }

          // Ensure menu doesn't go off the top or left edges
          x = Math.max(padding, x)
          y = Math.max(padding, y)

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
  SearchModal: {
    mounted() {
      this.input = this.el.querySelector("#search-input")

      // Focus the input when modal opens
      if (this.input) {
        this.input.focus()
      }

      // Handle keyboard navigation
      this.handleKeydown = (e) => {
        if (e.key === "ArrowDown") {
          e.preventDefault()
          e.stopPropagation()
          this.pushEvent("search_select_next", {})
        } else if (e.key === "ArrowUp") {
          e.preventDefault()
          e.stopPropagation()
          this.pushEvent("search_select_prev", {})
        } else if (e.key === "Enter") {
          e.preventDefault()
          e.stopPropagation()
          this.pushEvent("search_confirm", {})
        }
      }

      this.el.addEventListener("keydown", this.handleKeydown)
    },

    updated() {
      // Keep focus on input after updates
      if (this.input && document.activeElement !== this.input) {
        this.input.focus()
      }

      // Scroll selected item into view
      const selected = this.el.querySelector(".search-result-item.selected")
      if (selected) {
        selected.scrollIntoView({ behavior: "smooth", block: "nearest" })
      }
    },

    destroyed() {
      this.el.removeEventListener("keydown", this.handleKeydown)
    }
  },
  TodoFilterModal: {
    mounted() {
      // Stop any ongoing arrow pan animation in MindMapCanvas when modal opens
      const container = document.getElementById("mind-map-container")
      const canvasHook = container?.__liveViewHook
      if (canvasHook) {
        canvasHook.arrowKeysPressed?.clear()
        if (canvasHook.arrowPanAnimationId) {
          cancelAnimationFrame(canvasHook.arrowPanAnimationId)
          canvasHook.arrowPanAnimationId = null
        }
        canvasHook.arrowPanSpeed = 0
      }

      // Handle keyboard navigation - use window with capture to intercept before MindMapCanvas
      this.handleKeydown = (e) => {
        if (e.key === "ArrowDown") {
          e.preventDefault()
          e.stopPropagation()
          e.stopImmediatePropagation()
          this.pushEvent("todo_filter_select_next", {})
        } else if (e.key === "ArrowUp") {
          e.preventDefault()
          e.stopPropagation()
          e.stopImmediatePropagation()
          this.pushEvent("todo_filter_select_prev", {})
        } else if (e.key === "ArrowLeft" || e.key === "ArrowRight") {
          // Block left/right arrows to prevent canvas panning
          e.preventDefault()
          e.stopPropagation()
          e.stopImmediatePropagation()
        } else if (e.key === "Enter") {
          e.preventDefault()
          e.stopPropagation()
          e.stopImmediatePropagation()
          this.pushEvent("todo_filter_confirm", {})
        } else if (e.key === "Tab") {
          e.preventDefault()
          e.stopPropagation()
          e.stopImmediatePropagation()
          this.pushEvent("todo_filter_toggle_scope", {})
        }
      }

      // Also intercept keyup for arrow keys to prevent MindMapCanvas from receiving mismatched keyup events
      this.handleKeyup = (e) => {
        if (["ArrowDown", "ArrowUp", "ArrowLeft", "ArrowRight"].includes(e.key)) {
          e.preventDefault()
          e.stopPropagation()
          e.stopImmediatePropagation()
        }
      }

      // Use capture phase to intercept events before they reach MindMapCanvas
      window.addEventListener("keydown", this.handleKeydown, true)
      window.addEventListener("keyup", this.handleKeyup, true)
    },

    updated() {
      // Scroll selected item into view smoothly
      const selected = this.el.querySelector(".todo-result-item.selected")
      if (selected) {
        selected.scrollIntoView({ behavior: "smooth", block: "nearest" })
      }
    },

    destroyed() {
      window.removeEventListener("keydown", this.handleKeydown, true)
      window.removeEventListener("keyup", this.handleKeyup, true)
    }
  },
  NodeDrag: {
    mounted() {
      this.nodeId = this.el.dataset.nodeId
      this.isRoot = this.el.dataset.isRoot === "true"
      this.isLocked = this.el.dataset.locked === "true"
      this.subtreeCount = parseInt(this.el.dataset.subtreeCount || "0")
      this.descendantIds = JSON.parse(this.el.dataset.descendantIds || "[]")

      // Drag state
      this.isDragging = false
      this.dragStartX = 0
      this.dragStartY = 0
      this.dragThreshold = 5
      this.ghostElement = null
      this.ghostOffsetX = 0
      this.ghostOffsetY = 0
      this.currentTarget = null

      // Edge panning state
      this.edgePanInterval = null
      this.edgePanSpeed = 15
      this.edgePanThreshold = 50

      // Bind handlers
      this.handleMouseDown = this.handleMouseDown.bind(this)
      this.handleMouseMove = this.handleMouseMove.bind(this)
      this.handleMouseUp = this.handleMouseUp.bind(this)
      this.handleKeyDown = this.handleKeyDown.bind(this)
      this.handleContextMenu = this.handleContextMenu.bind(this)
      this.handleDoubleClick = this.handleDoubleClick.bind(this)

      this.el.addEventListener("mousedown", this.handleMouseDown)
      this.el.addEventListener("contextmenu", this.handleContextMenu)
      this.el.addEventListener("dblclick", this.handleDoubleClick)
    },

    updated() {
      // Update data attributes when LiveView updates
      this.isRoot = this.el.dataset.isRoot === "true"
      this.isLocked = this.el.dataset.locked === "true"
      this.subtreeCount = parseInt(this.el.dataset.subtreeCount || "0")
      this.descendantIds = JSON.parse(this.el.dataset.descendantIds || "[]")
    },

    destroyed() {
      this.el.removeEventListener("mousedown", this.handleMouseDown)
      this.el.removeEventListener("contextmenu", this.handleContextMenu)
      this.el.removeEventListener("dblclick", this.handleDoubleClick)
      this.cleanup()
    },

    // Context menu handler (right-click)
    handleContextMenu(e) {
      e.preventDefault()
      e.stopPropagation()

      // Pre-adjust position to keep menu within viewport
      const menuWidth = 240
      const menuHeight = 520
      const padding = 16
      const bottomPadding = 60

      let x = e.clientX
      let y = e.clientY

      if (x + menuWidth > window.innerWidth - padding) {
        x = window.innerWidth - menuWidth - padding
      }
      if (y + menuHeight > window.innerHeight - bottomPadding) {
        y = window.innerHeight - menuHeight - bottomPadding
      }
      x = Math.max(padding, x)
      y = Math.max(padding, y)

      this.pushEvent("open_context_menu", { id: this.nodeId, x: x, y: y })
    },

    // Double-click handler (start inline editing)
    handleDoubleClick(e) {
      e.preventDefault()
      e.stopPropagation()
      this.pushEvent("start_inline_edit", { id: this.nodeId })
    },

    handleMouseDown(e) {
      // Only handle left mouse button
      if (e.button !== 0) return

      // Don't interfere with other interactions
      if (e.target.closest("a, button, input, textarea, form")) return

      // Store meta/ctrl key state for focus handling on mouseup
      this.mouseDownMetaKey = e.metaKey
      this.mouseDownCtrlKey = e.ctrlKey

      // Record start position
      this.dragStartX = e.clientX
      this.dragStartY = e.clientY

      // Add global listeners
      window.addEventListener("mousemove", this.handleMouseMove)
      window.addEventListener("mouseup", this.handleMouseUp)
      window.addEventListener("keydown", this.handleKeyDown)
    },

    handleMouseMove(e) {
      const dx = e.clientX - this.dragStartX
      const dy = e.clientY - this.dragStartY
      const distance = Math.sqrt(dx * dx + dy * dy)

      // Check if we've exceeded the drag threshold
      if (!this.isDragging && distance > this.dragThreshold) {
        // Don't start drag if root node
        if (!this.isRoot) {
          this.startDrag(e)
        }
      }

      if (this.isDragging) {
        this.updateGhostPosition(e.clientX, e.clientY)
        this.updateDropTargets(e.clientX, e.clientY)
        this.checkEdgePan(e.clientX, e.clientY)
      }
    },

    handleMouseUp(e) {
      if (this.isDragging) {
        this.executeDrop()
      } else {
        // If we didn't drag, this was a click - focus the node
        this.pushEvent("focus_node", {
          id: String(this.nodeId),
          metaKey: this.mouseDownMetaKey || false,
          ctrlKey: this.mouseDownCtrlKey || false
        })
      }
      this.cleanup()
    },

    handleKeyDown(e) {
      // Cancel drag with Escape key
      if (e.key === "Escape" && this.isDragging) {
        e.preventDefault()
        this.cleanup()
        this.pushEvent("drag_cancel", {})
      }
    },

    startDrag(e) {
      this.isDragging = true

      // Add dragging class to source node and all descendants
      this.el.classList.add("dragging")
      const canvas = document.getElementById("mind-map-canvas")
      if (canvas) {
        for (const descendantId of this.descendantIds) {
          const descendantEl = canvas.querySelector(`#node-${descendantId}`)
          if (descendantEl) {
            descendantEl.classList.add("dragging")
          }
        }
      }

      // Add global dragging class to body
      document.body.classList.add("dragging-node")

      // Create ghost element
      this.createGhost(e)

      // Notify server
      this.pushEvent("drag_start", { node_id: this.nodeId })
    },

    createGhost(e) {
      const canvas = document.getElementById("mind-map-canvas")
      if (!canvas) return

      // Get the current canvas zoom level
      const container = document.getElementById("mind-map-container")
      const canvasZoom = container?.__liveViewHook?.zoom || 1

      // Get the dragged node's position (in canvas coordinates, unzoomed)
      const draggedX = parseFloat(this.el.style.left) || 0
      const draggedY = parseFloat(this.el.style.top) || 0

      // Collect all nodes in the subtree (dragged node + descendants)
      const subtreeNodeIds = [this.nodeId, ...this.descendantIds]
      const subtreeNodes = []

      for (const id of subtreeNodeIds) {
        const nodeEl = canvas.querySelector(`#node-${id}`)
        if (nodeEl) {
          subtreeNodes.push({
            id,
            el: nodeEl,
            x: parseFloat(nodeEl.style.left) || 0,
            y: parseFloat(nodeEl.style.top) || 0,
            width: parseFloat(nodeEl.style.width) || 200,
            height: parseFloat(nodeEl.style.height) || 44
          })
        }
      }

      // Calculate bounding box of the subtree (in canvas coords)
      let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
      for (const node of subtreeNodes) {
        minX = Math.min(minX, node.x)
        minY = Math.min(minY, node.y)
        maxX = Math.max(maxX, node.x + node.width)
        maxY = Math.max(maxY, node.y + node.height)
      }

      const subtreeWidth = maxX - minX
      const subtreeHeight = maxY - minY

      // Create ghost container
      this.ghostElement = document.createElement("div")
      this.ghostElement.className = "mind-map-subtree-ghost"
      this.ghostElement.style.position = "fixed"
      this.ghostElement.style.width = `${subtreeWidth}px`
      this.ghostElement.style.height = `${subtreeHeight}px`
      this.ghostElement.style.pointerEvents = "none"
      this.ghostElement.style.zIndex = "1000"

      // Scale to match visual size with slight reduction
      const visualScale = canvasZoom * 0.9
      this.ghostElement.style.transform = `scale(${visualScale}) rotate(1deg)`
      this.ghostElement.style.transformOrigin = "top left"

      // Collect edges that connect nodes within the subtree
      const subtreeIdSet = new Set(subtreeNodeIds)
      const svgLayer = canvas.querySelector(".mind-map-svg")
      const subtreeEdges = []

      if (svgLayer) {
        const edgeGroups = svgLayer.querySelectorAll(".mind-map-edge-group")
        edgeGroups.forEach(group => {
          const path = group.querySelector("path")
          if (!path) return

          // Parse path to get source/target - we'll use the path data directly
          // Edges connect parent to child, so we need edges where both ends are in subtree
          // We can identify edges by checking node positions against edge endpoints

          // Get the path's d attribute which contains coordinates
          const d = path.getAttribute("d")
          if (!d) return

          // Parse bezier curve: M sx sy C cx1 cy1, cx2 cy2, ex ey
          const match = d.match(/M\s*([\d.-]+)\s+([\d.-]+)\s*C\s*([\d.-]+)\s+([\d.-]+)[,\s]+([\d.-]+)\s+([\d.-]+)[,\s]+([\d.-]+)\s+([\d.-]+)/)
          if (!match) return

          const [, sx, sy, , , , , ex, ey] = match.map(Number)

          // Check if this edge connects two nodes in our subtree
          // by checking if start and end points are near any subtree nodes
          let sourceInSubtree = false
          let targetInSubtree = false

          for (const node of subtreeNodes) {
            // Check if start point is near this node (likely the right edge)
            if (Math.abs(sx - (node.x + node.width)) < 20 &&
                sy >= node.y && sy <= node.y + node.height) {
              sourceInSubtree = true
            }
            // Check if end point is near this node (likely the left edge)
            if (Math.abs(ex - node.x) < 20 &&
                ey >= node.y && ey <= node.y + node.height) {
              targetInSubtree = true
            }
          }

          if (sourceInSubtree && targetInSubtree) {
            subtreeEdges.push({ path: d, element: path })
          }
        })
      }

      // Create SVG for edges
      if (subtreeEdges.length > 0) {
        const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
        svg.setAttribute("class", "mind-map-ghost-svg")
        svg.style.position = "absolute"
        svg.style.left = "0"
        svg.style.top = "0"
        svg.style.width = `${subtreeWidth}px`
        svg.style.height = `${subtreeHeight}px`
        svg.style.overflow = "visible"
        svg.style.pointerEvents = "none"

        for (const edge of subtreeEdges) {
          const path = document.createElementNS("http://www.w3.org/2000/svg", "path")

          // Translate the path coordinates relative to subtree bounding box
          const translatedD = edge.path.replace(
            /M\s*([\d.-]+)\s+([\d.-]+)\s*C\s*([\d.-]+)\s+([\d.-]+)[,\s]+([\d.-]+)\s+([\d.-]+)[,\s]+([\d.-]+)\s+([\d.-]+)/,
            (match, sx, sy, cx1, cy1, cx2, cy2, ex, ey) => {
              const nsx = parseFloat(sx) - minX
              const nsy = parseFloat(sy) - minY
              const ncx1 = parseFloat(cx1) - minX
              const ncy1 = parseFloat(cy1) - minY
              const ncx2 = parseFloat(cx2) - minX
              const ncy2 = parseFloat(cy2) - minY
              const nex = parseFloat(ex) - minX
              const ney = parseFloat(ey) - minY
              return `M ${nsx} ${nsy} C ${ncx1} ${ncy1}, ${ncx2} ${ncy2}, ${nex} ${ney}`
            }
          )

          path.setAttribute("d", translatedD)
          path.setAttribute("class", "mind-map-ghost-edge")
          svg.appendChild(path)
        }

        this.ghostElement.appendChild(svg)
      }

      // Clone each node and position relative to bounding box
      for (const node of subtreeNodes) {
        const clonedNode = node.el.cloneNode(true)

        // Remove IDs and hooks
        clonedNode.removeAttribute("id")
        clonedNode.querySelectorAll("[id]").forEach(el => el.removeAttribute("id"))
        clonedNode.removeAttribute("phx-hook")
        clonedNode.querySelectorAll("[phx-hook]").forEach(el => el.removeAttribute("phx-hook"))

        // Add ghost styling class
        clonedNode.classList.add("mind-map-ghost-node")
        clonedNode.classList.remove("focused", "selected", "multi-selected", "dragging")

        // Position relative to subtree bounding box
        clonedNode.style.left = `${node.x - minX}px`
        clonedNode.style.top = `${node.y - minY}px`

        this.ghostElement.appendChild(clonedNode)
      }

      // Calculate cursor offset relative to the dragged node within the ghost
      const draggedRect = this.el.getBoundingClientRect()
      const cursorOffsetInNodeX = e.clientX - draggedRect.left
      const cursorOffsetInNodeY = e.clientY - draggedRect.top

      // Offset from ghost top-left to cursor position
      // Ghost top-left is at minX, minY in canvas coords
      // Dragged node is at draggedX, draggedY
      // So dragged node offset within ghost is (draggedX - minX, draggedY - minY)
      this.ghostOffsetX = ((draggedX - minX) * canvasZoom + cursorOffsetInNodeX) * 0.9
      this.ghostOffsetY = ((draggedY - minY) * canvasZoom + cursorOffsetInNodeY) * 0.9

      // Position ghost so dragged node appears under cursor
      this.ghostElement.style.left = `${e.clientX - this.ghostOffsetX}px`
      this.ghostElement.style.top = `${e.clientY - this.ghostOffsetY}px`

      document.body.appendChild(this.ghostElement)
    },

    updateGhostPosition(clientX, clientY) {
      if (this.ghostElement) {
        this.ghostElement.style.left = `${clientX - this.ghostOffsetX}px`
        this.ghostElement.style.top = `${clientY - this.ghostOffsetY}px`
      }
    },

    updateDropTargets(clientX, clientY) {
      const canvas = document.getElementById("mind-map-canvas")
      if (!canvas) return

      const nodes = canvas.querySelectorAll(".mind-map-node:not(.dragging)")

      // Clear previous highlights
      document.querySelectorAll(".drop-target, .drop-target-invalid").forEach(el => {
        el.classList.remove("drop-target", "drop-target-invalid")
      })

      this.currentTarget = null

      // Find node under cursor
      for (const node of nodes) {
        const rect = node.getBoundingClientRect()
        if (clientX >= rect.left && clientX <= rect.right &&
            clientY >= rect.top && clientY <= rect.bottom) {

          const targetId = node.dataset.nodeId

          if (this.isValidDropTarget(targetId, node)) {
            node.classList.add("drop-target")
            this.currentTarget = targetId
          } else {
            node.classList.add("drop-target-invalid")
          }

          return
        }
      }
    },

    isValidDropTarget(targetId, targetNode) {
      // Cannot drop on self
      if (targetId === this.nodeId) return false

      // Cannot drop on descendant
      if (this.descendantIds.includes(targetId)) return false

      // Cannot drop on root node as target (would make this a sibling of root, not valid in this tree)
      // Actually, we CAN drop on root to make it a child of root - that's valid
      // The restriction is: cannot drop on a node that is the current root of the view
      // But for now, let's allow dropping on any non-descendant

      return true
    },

    checkEdgePan(clientX, clientY) {
      const container = document.getElementById("mind-map-container")
      if (!container) return

      const rect = container.getBoundingClientRect()
      const threshold = this.edgePanThreshold

      let panX = 0
      let panY = 0

      if (clientX < rect.left + threshold) {
        panX = this.edgePanSpeed
      } else if (clientX > rect.right - threshold) {
        panX = -this.edgePanSpeed
      }

      if (clientY < rect.top + threshold) {
        panY = this.edgePanSpeed
      } else if (clientY > rect.bottom - threshold) {
        panY = -this.edgePanSpeed
      }

      if (panX !== 0 || panY !== 0) {
        this.startEdgePan(panX, panY)
      } else {
        this.stopEdgePan()
      }
    },

    startEdgePan(panX, panY) {
      // If already panning, update the direction
      if (this.edgePanInterval) {
        this.edgePanX = panX
        this.edgePanY = panY
        return
      }

      this.edgePanX = panX
      this.edgePanY = panY

      const container = document.getElementById("mind-map-container")
      const hook = container?.__liveViewHook

      if (!hook) return

      this.edgePanInterval = setInterval(() => {
        hook.panX += this.edgePanX
        hook.panY += this.edgePanY
        hook.applyTransform()
      }, 16) // ~60fps
    },

    stopEdgePan() {
      if (this.edgePanInterval) {
        clearInterval(this.edgePanInterval)
        this.edgePanInterval = null

        // Save viewport state after edge pan
        const container = document.getElementById("mind-map-container")
        container?.__liveViewHook?.saveViewportState()
      }
    },

    executeDrop() {
      if (this.currentTarget) {
        this.pushEvent("drag_end", {
          node_id: this.nodeId,
          target_id: this.currentTarget
        })
      } else {
        this.pushEvent("drag_cancel", {})
      }
    },

    cleanup() {
      // Remove drag state
      this.isDragging = false

      // Remove dragging class from source node and all descendants
      this.el.classList.remove("dragging")
      const canvas = document.getElementById("mind-map-canvas")
      if (canvas) {
        for (const descendantId of this.descendantIds) {
          const descendantEl = canvas.querySelector(`#node-${descendantId}`)
          if (descendantEl) {
            descendantEl.classList.remove("dragging")
          }
        }
      }

      // Remove global dragging class
      document.body.classList.remove("dragging-node")

      // Remove ghost element
      if (this.ghostElement) {
        this.ghostElement.remove()
        this.ghostElement = null
      }

      // Clear drop target highlights
      document.querySelectorAll(".drop-target, .drop-target-invalid").forEach(el => {
        el.classList.remove("drop-target", "drop-target-invalid")
      })

      // Stop edge panning
      this.stopEdgePan()

      // Remove global listeners
      window.removeEventListener("mousemove", this.handleMouseMove)
      window.removeEventListener("mouseup", this.handleMouseUp)
      window.removeEventListener("keydown", this.handleKeyDown)

      this.currentTarget = null
    }
  },
  MindMapCanvas: {
    mounted() {
      this.canvas = this.el.querySelector("#mind-map-canvas")
      this.rootId = this.el.dataset.rootId

      // Handle Cmd+P / Ctrl+P to open search (need to prevent browser print dialog)
      this.handleCmdP = (e) => {
        if ((e.metaKey || e.ctrlKey) && e.key === 'p') {
          e.preventDefault()
          this.pushEvent("open_search", {})
        }
      }
      window.addEventListener("keydown", this.handleCmdP)

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

      // Arrow key panning state
      this.arrowKeysPressed = new Set()
      this.arrowPanSpeed = 0
      this.arrowPanMinSpeed = 2
      this.arrowPanMaxSpeed = 20
      this.arrowPanAcceleration = 0.5
      this.arrowPanAnimationId = null

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

      // Listen for center-node events from LiveView (used when editing a node)
      this.handleEvent("center-node", ({ id }) => {
        this.centerNode(id)
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
      window.removeEventListener("keydown", this.handleCmdP)
      if (this.saveTimer) clearTimeout(this.saveTimer)
      if (this.arrowPanAnimationId) cancelAnimationFrame(this.arrowPanAnimationId)
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

      // Middle mouse button or left click on empty space = start panning
      if (e.button === 1 || (e.button === 0 && isEmptySpace)) {
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
        this.el.style.cursor = ""
        this.saveViewportState()
      }
    },

    handleKeyDown(e) {
      // Check if target is an input/textarea (with safety check for non-element targets)
      const isInputTarget = e.target?.matches?.("input, textarea")

      // Check if any modal is open (todo filter, search, etc.)
      const isModalOpen = document.getElementById("todo-filter-modal") ||
                          document.getElementById("search-modal") ||
                          document.querySelector(".priority-picker") ||
                          document.querySelector(".due-date-picker") ||
                          document.querySelector(".link-input-modal")

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
        } else if (["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(e.key) && !isModalOpen) {
          e.preventDefault()
          if (!this.arrowKeysPressed.has(e.key)) {
            this.arrowKeysPressed.add(e.key)
            if (this.arrowKeysPressed.size === 1) {
              this.arrowPanSpeed = this.arrowPanMinSpeed
              this.startArrowPan()
            }
          }
        }
      }
    },

    handleKeyUp(e) {
      if (["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(e.key)) {
        this.arrowKeysPressed.delete(e.key)
        if (this.arrowKeysPressed.size === 0) {
          this.stopArrowPan()
        }
      }
    },

    startArrowPan() {
      const animate = () => {
        if (this.arrowKeysPressed.size === 0) return

        this.arrowPanSpeed = Math.min(this.arrowPanMaxSpeed, this.arrowPanSpeed + this.arrowPanAcceleration)

        if (this.arrowKeysPressed.has("ArrowLeft")) this.panX += this.arrowPanSpeed
        if (this.arrowKeysPressed.has("ArrowRight")) this.panX -= this.arrowPanSpeed
        if (this.arrowKeysPressed.has("ArrowUp")) this.panY += this.arrowPanSpeed
        if (this.arrowKeysPressed.has("ArrowDown")) this.panY -= this.arrowPanSpeed

        this.applyTransform()
        this.arrowPanAnimationId = requestAnimationFrame(animate)
      }
      this.arrowPanAnimationId = requestAnimationFrame(animate)
    },

    stopArrowPan() {
      if (this.arrowPanAnimationId) {
        cancelAnimationFrame(this.arrowPanAnimationId)
        this.arrowPanAnimationId = null
      }
      this.arrowPanSpeed = 0
      this.saveViewportState()
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
        // Use CSS zoom for scaling (keeps text crisp) and transform only for panning
        // The pan values need to be adjusted for zoom since zoom affects the coordinate space
        this.canvas.style.zoom = this.zoom
        this.canvas.style.transform = `translate(${this.panX / this.zoom}px, ${this.panY / this.zoom}px)`
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

    centerNode(nodeId) {
      const node = this.canvas?.querySelector(`#node-${nodeId}`)
      if (!node) return

      // Reset scroll position - pan should handle all positioning
      this.el.scrollTop = 0
      this.el.scrollLeft = 0

      const rect = this.el.getBoundingClientRect()
      const nodeX = parseFloat(node.style.left) || 0
      const nodeY = parseFloat(node.style.top) || 0
      const nodeWidth = parseFloat(node.style.width) || 200
      const nodeHeight = parseFloat(node.style.height) || 32

      // Center the node in the viewport
      const targetViewX = (rect.width - nodeWidth * this.zoom) / 2
      const targetViewY = (rect.height - nodeHeight * this.zoom) / 2

      const targetPanX = targetViewX - nodeX * this.zoom
      const targetPanY = targetViewY - nodeY * this.zoom

      // Animate the pan smoothly
      this.animatePan(targetPanX, targetPanY, 300)
    },

    animatePan(targetX, targetY, duration) {
      const startX = this.panX
      const startY = this.panY
      const startTime = performance.now()

      const animate = (currentTime) => {
        const elapsed = currentTime - startTime
        const progress = Math.min(elapsed / duration, 1)

        // Ease out cubic for smooth deceleration
        const eased = 1 - Math.pow(1 - progress, 3)

        this.panX = startX + (targetX - startX) * eased
        this.panY = startY + (targetY - startY) * eased

        this.applyTransform()

        if (progress < 1) {
          requestAnimationFrame(animate)
        } else {
          this.saveViewportState()
        }
      }

      requestAnimationFrame(animate)
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

