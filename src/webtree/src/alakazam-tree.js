// alakazam-tree.js
// Thin wrapper around yy-tree adding: per-node icons, a custom context menu,
// double-click detection, drop semantics matching Alakazam's existing tree
// (dropping a node onto another never moves/reparents it -- the visual/data
// move yy-tree performs internally is always reverted, and a nodeDropped
// bridge event is emitted instead, so MATLAB can apply the dropped branch's
// transformation chain to the target dataset itself, building the actual new
// result node(s) -- see Alakazam.evaluateDroppedBranch), and a modernised
// look (see TREE_STYLES/icons override below and
// alakazam-tree.css): yy-tree ships with its own default row styling
// injected at runtime (Tree._addStyles, from its styleDefaults) unless a
// custom `styles` argument is passed to `new Tree(...)` -- left at its
// defaults, node names render as small fixed-100px-wide grey boxes with a
// barely-distinguishable selection shade (200,200,200 selected vs 230,230,230
// unselected), and expand/collapse uses a boxed +/- glyph. TREE_STYLES below
// replaces all of that; actual row selection highlighting is handled by our
// own alz-row-selected class on the *whole* row (leaf.content), not
// yy-tree's own -select class (which only ever touches the name span) --
// see _applySelectionHighlight.
import { Tree } from 'yy-tree'
import { icons } from 'yy-tree/src/icons.js'

// yy-tree's own expand/collapse glyphs are a bordered box with a +/- sign
// (see node_modules/yy-tree/src/icons.js) -- replaced here with simple flat
// chevrons (closed = pointing right, open = pointing down), matching modern
// tree UIs. `icons` is the same object instance yy-tree's own tree.js uses
// internally (both import the same underlying module file, so mutating it
// here propagates), not a public/documented override point, but this is
// vendored, pinned, build-time-only code (see webtree/README.md), not a live
// dependency -- an acceptable place to reach in.
icons.closed = '<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg"><path d="M35 20 L70 50 L35 80" fill="none" stroke="#666" stroke-width="12" stroke-linecap="round" stroke-linejoin="round"/></svg>'
icons.open = '<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg"><path d="M20 35 L50 70 L80 35" fill="none" stroke="#666" stroke-width="12" stroke-linecap="round" stroke-linejoin="round"/></svg>'

// Passed as the `styles` argument to `new Tree(...)`: yy-tree merges this
// shallowly, one whole sub-object at a time (see node_modules/yy-tree/src/
// utils.js's options()), so providing e.g. `nameStyles` at all replaces the
// *entire* default nameStyles object -- including its fixed `width: 100px`,
// which is why that doesn't need to be explicitly overridden to something
// else here.
const TREE_STYLES = {
    nameStyles: {
        padding: '1px 6px',
        margin: '0',
        background: 'transparent',
        'user-select': 'none',
        cursor: 'pointer',
        'white-space': 'nowrap',
        'font-size': '12px'
    },
    contentStyles: {
        display: 'flex',
        'align-items': 'center',
        padding: '1px 4px',
        'border-radius': '4px',
        cursor: 'pointer'
    },
    expandStyles: {
        width: '13px',
        height: '13px',
        'margin-right': '2px',
        flex: 'none'
    },
    indicatorStyles: {
        // The prospective drop position is shown by our own dashed outline on
        // the whole target row (alz-drop-target, see _setDropTargetHighlight),
        // not yy-tree's thin insertion line. A travelling line would also
        // reflow the rows we deliberately keep static during a drag (see the
        // _pickup wrap in the constructor), so the built-in indicator is
        // collapsed to nothing here. It still sits in the DOM at the
        // prospective drop parent, which is all _onDragPointerMove and
        // Input._up ever read off it -- never its size.
        background: 'transparent',
        height: '0',
        width: '0',
        padding: '0'
    },
    selectStyles: {
        // Real selection highlighting is the alz-row-selected class on the
        // whole row (leaf.content, applied by _applySelectionHighlight),
        // not yy-tree's own -select (name-only) class -- left inert here.
        background: 'transparent'
    }
}

// Per-node-type icons: a coloured rounded-square "badge" holding a simple
// white glyph, a common modern flat-icon pattern (distinguishable by both
// colour and glyph shape, not colour alone) -- freq's blue (#4a7fc9)
// matches the accent colour used throughout the rest of the app (ribbon,
// tile selection, tree row selection below). 'raw' and 'grandAverage'
// (see below) are deliberately two more shades from that same blue
// family (lighter/darker, not a different hue) rather than an unrelated
// colour, on request -- distinguished from freq and each other by
// lightness plus glyph shape, not hue alone. 'raw' is the icon for a
// freshly imported subject dataset's own root node (see
// WorkSpace.loadBVAFile/loadMATFile/loadSETFile) -- a simple person
// silhouette, since that root node represents one subject's own
// recording, not a generic file/folder. 'grandAverage' is its own
// dedicated icon (three source nodes merging into one, the group-
// combination idea) for WorkSpace.GrandAveragesTree's own root nodes
// (see Alakazam.saveGrandAverage/WorkSpace.loadGrandAverages) -- these
// used to just borrow 'time'/'freq' (the same badge a plain per-subject
// Average result gets), which read as generic rather than as its own
// distinct concept.
const ICONS = {
    raw:  '<svg viewBox="0 0 24 24" width="16" height="16"><rect x="1" y="1" width="22" height="22" rx="5" fill="#6fa8dc"/><circle cx="12" cy="8.5" r="3.3" fill="#fff"/><path d="M5.5 19c0-3.6 2.9-6 6.5-6s6.5 2.4 6.5 6" fill="#fff"/></svg>',
    time: '<svg viewBox="0 0 24 24" width="16" height="16"><rect x="1" y="1" width="22" height="22" rx="5" fill="#2f9e6e"/><path d="M4 14l3-4 3 5 3-7 3 4 4-3" fill="none" stroke="#fff" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    freq: '<svg viewBox="0 0 24 24" width="16" height="16"><rect x="1" y="1" width="22" height="22" rx="5" fill="#4a7fc9"/><path d="M6 17V13M10 17V9M14 17V15M18 17V7" stroke="#fff" stroke-width="1.8" stroke-linecap="round"/></svg>',
    grandAverage: '<svg viewBox="0 0 24 24" width="16" height="16"><rect x="1" y="1" width="22" height="22" rx="5" fill="#2e5c8a"/><line x1="7" y1="6.5" x2="12" y2="16" stroke="#fff" stroke-width="1.4" stroke-linecap="round"/><line x1="12" y1="5.5" x2="12" y2="16" stroke="#fff" stroke-width="1.4" stroke-linecap="round"/><line x1="17" y1="6.5" x2="12" y2="16" stroke="#fff" stroke-width="1.4" stroke-linecap="round"/><circle cx="7" cy="6.5" r="1.7" fill="#fff"/><circle cx="12" cy="5.5" r="1.7" fill="#fff"/><circle cx="17" cy="6.5" r="1.7" fill="#fff"/><circle cx="12" cy="17" r="2.6" fill="#fff"/></svg>',
    default: '<svg viewBox="0 0 24 24" width="16" height="16"><rect x="1" y="1" width="22" height="22" rx="5" fill="#8a8a8a"/><rect x="6" y="5" width="12" height="14" rx="1" fill="none" stroke="#fff" stroke-width="1.4"/></svg>'
}

const ROOT_ID = '__root__'
const DOUBLE_CLICK_MS = 400
// How long a drag survives the pointer leaving the tree's own rendering
// area before it's treated as abandoned -- see the constructor's early
// mouseleave/mouseenter listeners and _cancelDrag. Long enough to absorb
// ordinary mouse imprecision grazing a narrow panel edge mid-drag, short
// enough that genuinely dragging away and letting go still cancels
// promptly.
const LEAVE_GRACE_MS = 250
// Pixels of mouse movement since mousedown before a click becomes a drag --
// see the _checkThreshold patch in the constructor. yy-tree documents a
// `threshold` constructor option for exactly this, but never actually
// exposes or reads it back anywhere (confirmed against its real source,
// node_modules/yy-tree/src/tree.js has no `get threshold()`, unlike every
// other documented option) -- it is a dead option, so this is defined here
// as our own constant instead of trying to read tree.threshold/
// tree._options.threshold back off the library.
const DRAG_THRESHOLD_PX = 10
const CONTEXT_ITEMS = [
    { action: 'listEvents', label: 'List events' },
    { separator: true },
    { action: 'rename', label: 'Rename' },
    { action: 'recalculate', label: 'Recalculate' },
    { action: 'applyToAll', label: 'Apply to All Raw Files...' },
    { separator: true },
    { action: 'saveTemplate', label: 'Save Template...' },
    { action: 'applyTemplate', label: 'Apply Template...' },
    { separator: true },
    { action: 'exportErpset', label: 'Export as ERPset...' },
    { separator: true },
    { action: 'delete', label: 'Delete' }
]

export function create(container, options) {
    return new AlakazamTree(container, options)
}

class AlakazamTree {
    constructor(container, options) {
        this._onEvent = (options && options.onEvent) || function () {}
        this._byId = new Map()               // id -> data node
        this._lastClick = { id: null, time: 0 }
        this._menuEl = null
        this._highlightedLeaf = null // see _applySelectionHighlight
        this._dropTargetLeaf = null  // see _setDropTargetHighlight
        this._leaveGraceTimer = null // see _cancelDrag
        this._dragPlaceholder = null // see the _pickup wrap / _removeDragPlaceholder

        this._root = { id: ROOT_ID, name: '', children: [], expanded: true }

        // Registered BEFORE `new Tree(...)` below (whose Input constructor
        // registers its OWN 'mouseleave' listener on document.body, which
        // would otherwise instantly finalize/"drop" the drag exactly like a
        // real mouseup -- yy-tree has no separate cancel concept, see
        // node_modules/yy-tree/src/input.js's Input._up(), fired by
        // mouseleave/mouseup/touchend alike). Listeners on the same element
        // for the same event run in registration order, so registering ours
        // first lets stopImmediatePropagation() below keep Input's own
        // listener from ever seeing a mouseleave that happens mid-drag.
        // uihtml renders in its own embedded document with no window/app-
        // level "pointer left the app" signal of its own, and dropping one
        // node onto another (overlay or apply-transformation alike -- see
        // the file header comment) is a genuine tree-node-to-tree-node
        // gesture that never needs to leave this tree's own bounds, so an
        // instant cancel on every mouseleave (an earlier version of this
        // fix) turned out to be too eager: ordinary mouse imprecision
        // easily grazes a narrow panel's edge for an instant while
        // dragging toward a row near the boundary. A short grace period
        // instead: if the pointer comes back within LEAVE_GRACE_MS, the
        // drag just continues untouched (Input's own mousemove listener
        // picks up right where it left off, since it never saw the leave
        // at all); if it doesn't, _cancelDrag manually restores everything.
        document.body.addEventListener('mouseleave', (e) => {
            if (!this._pending) return
            e.stopImmediatePropagation()
            clearTimeout(this._leaveGraceTimer)
            this._leaveGraceTimer = setTimeout(() => this._cancelDrag(), LEAVE_GRACE_MS)
        })
        document.body.addEventListener('mouseenter', () => {
            clearTimeout(this._leaveGraceTimer)
            this._leaveGraceTimer = null
        })

        this._tree = new Tree(this._root, {
            parent: container,
            move: true,
            select: true,
            holdTime: 0 // we drive rename via the context menu, not press-and-hold
        }, TREE_STYLES)

        // yy-tree's Input._checkThreshold (node_modules/yy-tree/src/input.js)
        // has a bug: it computes the mouse-move distance since mousedown but
        // only checks its TRUTHINESS, never actually compares it against any
        // threshold -- so literally any cursor movement at all, even a single
        // pixel of mouse jitter during an ordinary click, starts a drag
        // (reported as "clicking a tree branch sometimes gets registered as a
        // drag"). yy-tree's own docs promise a `threshold` constructor option
        // for exactly this, but the library never actually reads it back (see
        // DRAG_THRESHOLD_PX above), so this patches Input._checkThreshold
        // directly as an instance override (not a source edit -- yy-tree is a
        // vendored npm dependency, not part of this file) to add the missing
        // comparison: a click only becomes a drag once the cursor has
        // actually moved past DRAG_THRESHOLD_PX pixels from the mousedown
        // point. Logic otherwise identical to the original.
        this._tree._input._checkThreshold = function (e) {
            if (!this._tree.move) return false
            if (this._moving) return true
            const dx = this._isDown.x - e.pageX
            const dy = this._isDown.y - e.pageY
            if (Math.sqrt(dx * dx + dy * dy) > DRAG_THRESHOLD_PX) {
                this._moving = true
                this._pickup()
                return true
            }
            return false
        }

        // Keep the tree visually static during a drag. yy-tree's Input._pickup()
        // lifts the dragged row out to document.body (floating it under the
        // cursor), which collapses its slot and shifts every row below it up --
        // "the original node is cut first", moving the very target the user is
        // aiming at. A drop here never actually reorders anything (see _onMove),
        // so there is nothing to be gained from that reflow: reserve the vacated
        // space with an inert, same-height spacer so nothing below moves. Removed
        // on drop/cancel (see _removeDragPlaceholder). Wrapping _pickup (rather
        // than acting on the 'move-pending' event) is deliberate -- that event
        // fires INSIDE the original _pickup, before it relocates the row, so the
        // slot to backfill does not exist yet at that point.
        const input = this._tree._input
        const originalPickup = input._pickup.bind(input)
        input._pickup = () => {
            const target = input._target
            const height = target ? target.offsetHeight : 0
            originalPickup()
            if (target && height) {
                const spacer = document.createElement('div')
                spacer.className = 'alz-drag-placeholder'
                spacer.style.height = height + 'px'
                // The indicator now sits where the row was (Input._pickup inserts
                // it there before floating the row out); drop the spacer into that
                // same slot so the gap stays put even as the indicator travels.
                const indicator = input._indicator.get()
                if (indicator.parentNode) {
                    indicator.parentNode.insertBefore(spacer, indicator)
                }
                this._dragPlaceholder = spacer
            }
        }

        this._tree.on('render', (leaf) => this._onRender(leaf))
        this._tree.on('clicked', (leaf) => this._onClicked(leaf))
        this._tree.on('move-pending', (leaf) => this._onMovePending(leaf))
        this._tree.on('move', (leaf) => this._onMove(leaf))
        this._tree.on('name-change', (leaf, name) => this._onNameChange(leaf, name))

        document.addEventListener('mousedown', (e) => this._maybeCloseMenu(e))
        // Registered on `document`, not `document.body` (where yy-tree's own
        // Input registers its mousemove handler): bubble-phase dispatch
        // always reaches document AFTER body, regardless of source order,
        // so by the time this runs, Input._move() has already repositioned
        // the drop indicator for this event -- see _onDragPointerMove.
        document.addEventListener('mousemove', () => this._onDragPointerMove())
    }

    /**
     * Replace the whole node set. `nodes` is a flat array:
     *   { id, label, icon, parentId, expanded }
     * parentId === null (or omitted) means top-level (child of the root).
     */
    setNodes(nodes, selectedId) {
        this._byId.clear()
        const byId = new Map()
        for (const n of nodes) {
            byId.set(n.id, {
                id: n.id, name: n.label, icon: n.icon || 'default',
                expanded: n.expanded !== false, children: [], parent: null,
                canListEvents: !!n.canListEvents, canRecalculate: !!n.canRecalculate,
                canApplyToAll: !!n.canApplyToAll, canExportErpset: !!n.canExportErpset
            })
        }
        this._root.children = []
        for (const n of nodes) {
            const data = byId.get(n.id)
            const parent = n.parentId != null ? byId.get(n.parentId) : null
            if (parent) {
                parent.children.push(data)
            } else {
                this._root.children.push(data)
            }
        }
        this._byId = byId
        this._tree.update()
        if (selectedId != null && byId.has(selectedId)) {
            this._selectById(selectedId)
        }
    }

    _selectById(id) {
        const leaf = this._findLeafByData(this._byId.get(id))
        if (leaf) {
            this._tree._selection = leaf
            this._applySelectionHighlight(leaf)
        }
    }

    // Highlights the whole row (leaf.content), not just the name span --
    // yy-tree's own -select class (toggled internally on native click, and
    // by _selectById above for programmatic selection) only ever touches
    // leaf.name, which read as barely-distinguishable-from-unselected once
    // TREE_STYLES took over row styling (see the file header comment). This
    // is called from both _onClicked (native click path) and _selectById
    // (programmatic path, e.g. MATLAB pushing a new selectedId), so both
    // stay visually in sync.
    _applySelectionHighlight(leaf) {
        if (this._highlightedLeaf) {
            this._highlightedLeaf.content.classList.remove('alz-row-selected')
        }
        this._highlightedLeaf = leaf
        if (leaf) {
            leaf.content.classList.add('alz-row-selected')
        }
    }

    // Highlights whichever node is the current prospective drop target while
    // dragging -- distinct from _applySelectionHighlight (click selection),
    // so a drag over a different node doesn't fight the tree's own
    // selection colour. Mirrors _applySelectionHighlight's leaf.content/
    // single-previous-highlight pattern.
    _setDropTargetHighlight(leaf) {
        if (this._dropTargetLeaf === leaf) return
        if (this._dropTargetLeaf) {
            this._dropTargetLeaf.content.classList.remove('alz-drop-target')
        }
        this._dropTargetLeaf = leaf
        if (leaf) {
            leaf.content.classList.add('alz-drop-target')
        }
    }

    // Figures out which node the drag would drop onto *right now* and
    // highlights it, so the user always has a clear answer to "what am I
    // about to apply this branch to" while dragging (yy-tree's own
    // indicator is just a thin insertion line, easy to lose track of once
    // the row list has collapsed around it during the drag).
    //
    // There is no per-frame hook from yy-tree for this, so this reads its
    // internal state directly (vendored, pinned, build-time-only code, same
    // justification as the icons override above): Input._up() always does
    // `indicator.parentNode.insertBefore(this._target, indicator)` then
    // `_moveData()` reads `this._target.parentNode.data` as the new
    // parent -- i.e. the indicator's CURRENT parentNode, at any moment
    // during the drag, already tells us exactly what dropping right now
    // would resolve to: either a rendered leaf element (a real node, whose
    // own `.data` is the prospective target) or this._tree.element itself
    // (the root container, i.e. a targetId:null/no-target drop -- nothing
    // to highlight).
    _onDragPointerMove() {
        if (!this._pending) return
        const indicatorEl = this._tree._input._indicator.get()
        const parentEl = indicatorEl && indicatorEl.parentNode
        if (parentEl && parentEl.isLeaf && parentEl.data !== this._pending.data) {
            this._setDropTargetHighlight(parentEl)
        } else {
            this._setDropTargetHighlight(null)
        }
    }

    _findLeafByData(data) {
        // Walk the rendered DOM directly: yy-tree's own findInTree() searches
        // (and returns) the *data* tree, not the leaf elements we need here.
        const walk = (el) => {
            if (el.isLeaf && el.data === data) { return el }
            for (const child of el.children || []) {
                const r = walk(child)
                if (r) return r
            }
            return null
        }
        return walk(this._tree.element)
    }

    _onRender(leaf) {
        const data = leaf.data
        const iconSpan = document.createElement('span')
        iconSpan.className = 'alz-icon'
        if (typeof data.icon === 'string' && data.icon.startsWith('data:')) {
            // A per-transformation icon (Transformations/<id>/<id>.png, see
            // WorkSpaceTree.iconForResult), not one of the fixed ICONS
            // badge keys -- rendered as a real <img>, scaled down to the
            // same footprint the badge icons use, rather than a raw SVG
            // innerHTML swap.
            const img = document.createElement('img')
            img.src = data.icon
            img.width = 16
            img.height = 16
            img.className = 'alz-icon-img'
            iconSpan.appendChild(img)
        } else {
            iconSpan.innerHTML = ICONS[data.icon] || ICONS.default
        }
        leaf.content.insertBefore(iconSpan, leaf.name)
        leaf.content.addEventListener('contextmenu', (e) => {
            e.preventDefault()
            e.stopPropagation()
            this._selectById(data.id)
            // clientX/clientY (viewport-relative), not pageX/pageY: the menu is
            // positioned against the viewport in _positionMenu, and the tree's
            // own scroll container (#tree) can be scrolled -- so page coords
            // would be offset by the scroll amount.
            this._openMenu(e.clientX, e.clientY, data)
        })
    }

    _onClicked(leaf) {
        const data = leaf.data
        const now = Date.now()
        const isDouble = this._lastClick.id === data.id && (now - this._lastClick.time) < DOUBLE_CLICK_MS
        this._lastClick = { id: data.id, time: now }
        this._applySelectionHighlight(leaf)
        this._onEvent({ type: isDouble ? 'nodeDoubleClicked' : 'nodeClicked', id: data.id })
    }

    _onMovePending(leaf) {
        // Remember the pre-drag position so the drop can be reverted (see _onMove).
        this._pending = {
            data: leaf.data,
            oldParent: leaf.data.parent,
            oldIndex: leaf.data.parent.children.indexOf(leaf.data)
        }
        // A drag is now in progress: swap the cursor to signal "apply", not
        // "move" (see alakazam-tree.css). yy-tree's Input._up() always
        // pairs a 'move-pending' with a later 'move' once the drag
        // threshold is crossed (confirmed in node_modules/yy-tree/src/
        // input.js), so _onMove is guaranteed to run and clear this --
        // UNLESS the drag is cancelled instead via _cancelDrag (the
        // pointer leaving the tree and not coming back within
        // LEAVE_GRACE_MS -- see the constructor), which clears it itself.
        document.documentElement.classList.add('alz-dragging')
    }

    _onMove(leaf) {
        const data = leaf.data
        const newParent = data.parent
        const targetId = newParent.id === ROOT_ID ? null : newParent.id
        document.documentElement.classList.remove('alz-dragging')
        this._setDropTargetHighlight(null)
        this._removeDragPlaceholder()

        // Always undo the reparent yy-tree just performed: dropping a node
        // onto another applies that node's transformation chain to the
        // target dataset instead of moving it (see the file header comment)
        // -- there is no plain "move a branch" gesture in this tree. MATLAB
        // builds the actual new result node(s) itself.
        if (this._pending && this._pending.data === data) {
            const { oldParent, oldIndex } = this._pending
            newParent.children.splice(newParent.children.indexOf(data), 1)
            oldParent.children.splice(oldIndex, 0, data)
            data.parent = oldParent
            this._tree.update()
        }
        this._pending = null

        // MATLAB now has to actually do something with this (run the
        // dropped branch's transformations against the target -- see
        // Alakazam.evaluateDroppedBranch), which can take a moment; show a
        // busy cursor until it reports back. Cleared by bridge.js's
        // applyData the moment a fresh Data push arrives -- guaranteed to
        // happen for every drop, success/ignored/error alike, since
        // Alakazam.onNodeDropped pushes via onCleanup (see alakazam-tree.css
        // for why cursor:wait, not a custom image).
        document.documentElement.classList.add('alz-busy')
        this._onEvent({ type: 'nodeDropped', sourceId: data.id, targetId })
    }

    // Called after the pointer has been outside the tree for LEAVE_GRACE_MS
    // during a drag (see the constructor's mouseleave listener, which
    // intercepts the leave before yy-tree's own Input ever sees it -- so
    // Input's internal state, e.g. Input._target/_moving, is exactly as it
    // was mid-drag and needs manually unwinding here, mirroring what
    // Input._up() itself does on a normal drop (node_modules/yy-tree/src/
    // input.js) minus _moveData()/emit('move'): nothing was ever actually
    // dropped, so the data graph was never touched and needs no revert --
    // just discard the floating dragged row/indicator and rebuild the real
    // tree fresh from the (unmutated) data.
    _cancelDrag() {
        this._leaveGraceTimer = null
        const input = this._tree._input
        const target = input._target
        if (!target) return // already finished normally in the meantime
        input._indicator.get().remove()
        target.remove()
        input._target = null
        input._moving = null
        this._pending = null
        document.documentElement.classList.remove('alz-dragging')
        this._setDropTargetHighlight(null)
        this._removeDragPlaceholder()
        this._tree.update()
    }

    // Removes the drag spacer that reserved the dragged row's slot (see the
    // _pickup wrap in the constructor). Called on every drop (_onMove) and
    // every abandoned drag (_cancelDrag); a no-op if none is present.
    _removeDragPlaceholder() {
        if (this._dragPlaceholder) {
            this._dragPlaceholder.remove()
            this._dragPlaceholder = null
        }
    }

    _onNameChange(leaf, name) {
        this._onEvent({ type: 'nodeRenamed', id: leaf.data.id, name })
    }

    _openMenu(x, y, data) {
        this._closeMenu()
        const menu = document.createElement('div')
        menu.className = 'alz-menu'
        menu.style.left = x + 'px'
        menu.style.top = y + 'px'
        for (const item of CONTEXT_ITEMS) {
            if (item.separator) {
                const sep = document.createElement('div')
                sep.className = 'alz-menu-sep'
                menu.appendChild(sep)
                continue
            }
            const row = document.createElement('div')
            row.className = 'alz-menu-item'
            row.textContent = item.label
            // 'saveTemplate' reuses canApplyToAll: same eligibility as "Apply
            // to All Raw Files" (a non-root branch in the Data & Analyses
            // tree) -- both act on "this branch" as a structural unit, see
            // Alakazam.persistResultNode. 'applyTemplate' has no data-driven
            // eligibility at all: it is valid for any node whatsoever (like
            // rename/delete), so it is never disabled here.
            const disabled = item.disabled || (item.action === 'listEvents' && !data.canListEvents)
                || (item.action === 'recalculate' && !data.canRecalculate)
                || (item.action === 'applyToAll' && !data.canApplyToAll)
                || (item.action === 'saveTemplate' && !data.canApplyToAll)
                || (item.action === 'exportErpset' && !data.canExportErpset)
            if (disabled) {
                row.classList.add('alz-menu-item-disabled')
            } else {
                row.addEventListener('click', () => {
                    this._closeMenu()
                    this._onEvent({ type: 'contextMenuAction', action: item.action, id: data.id })
                })
            }
            menu.appendChild(row)
        }
        document.body.appendChild(menu)
        this._menuEl = menu
        this._positionMenu(menu, x, y)
    }

    // Keeps the whole menu inside the tree's own viewport. uihtml renders in a
    // fixed-size iframe whose <body> is overflow:hidden, so a menu opened near
    // the right or bottom edge would otherwise be clipped by the panel. Opens
    // at the click point, then shifts back (leftward/upward) by whatever would
    // overflow; if the menu is taller than the panel, caps its height and lets
    // it scroll rather than run off the bottom. Must run after the menu is in
    // the DOM so offsetWidth/offsetHeight are measurable.
    _positionMenu(menu, x, y) {
        const pad = 2
        const vw = document.documentElement.clientWidth
        const vh = document.documentElement.clientHeight
        if (menu.offsetHeight > vh - 2 * pad) {
            menu.style.maxHeight = (vh - 2 * pad) + 'px'
            menu.style.overflowY = 'auto'
        }
        const w = menu.offsetWidth
        const h = menu.offsetHeight
        let left = x
        let top = y
        if (left + w + pad > vw) { left = Math.max(pad, vw - w - pad) }
        if (top + h + pad > vh) { top = Math.max(pad, vh - h - pad) }
        menu.style.left = left + 'px'
        menu.style.top = top + 'px'
    }

    _closeMenu() {
        if (this._menuEl) {
            this._menuEl.remove()
            this._menuEl = null
        }
    }

    _maybeCloseMenu(e) {
        if (this._menuEl && !this._menuEl.contains(e.target)) {
            this._closeMenu()
        }
    }
}
