// alakazam-tree.js
// Thin wrapper around yy-tree adding: per-node icons, a custom context menu,
// double-click detection, Ctrl-aware drop semantics matching Alakazam's
// existing tree (no-modifier drop = real reparent, left entirely to yy-tree;
// Ctrl-held drop = "apply transformation to the node dropped onto" -- the
// visual/data move yy-tree performs is reverted, and only a bridge event is
// emitted, since MATLAB will build the actual new result node itself), and a
// modernised look (see TREE_STYLES/icons override below and
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
        padding: '3px 6px',
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
        padding: '2px 4px',
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
        background: '#4a7fc9',
        height: '3px',
        width: '100px',
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
// colour and glyph shape, not colour alone) -- freq's blue matches the
// accent colour used throughout the rest of the app (ribbon, tile
// selection, tree row selection below). 'raw' doubles as the tree's root/
// branch icon key (root imports AND the "Grand Averages" branch, see
// WorkSpace.loadBVAFile/loadGrandAverages) -- a folder glyph, the same
// closed-folder-tab silhouette AlakazamRibbon's own "Tabs" view-mode icon
// uses (src/AlakazamRibbon.m's viewItems), recoloured white-on-badge to
// match this set instead of that icon's outline style.
const ICONS = {
    raw:  '<svg viewBox="0 0 24 24" width="16" height="16"><rect x="1" y="1" width="22" height="22" rx="5" fill="#d9a441"/><path d="M5 8a1 1 0 0 1 1-1h4l1.6 1.8H18a1 1 0 0 1 1 1V17a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1z" fill="#fff"/></svg>',
    time: '<svg viewBox="0 0 24 24" width="16" height="16"><rect x="1" y="1" width="22" height="22" rx="5" fill="#2f9e6e"/><path d="M4 14l3-4 3 5 3-7 3 4 4-3" fill="none" stroke="#fff" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    freq: '<svg viewBox="0 0 24 24" width="16" height="16"><rect x="1" y="1" width="22" height="22" rx="5" fill="#4a7fc9"/><path d="M6 17V13M10 17V9M14 17V15M18 17V7" stroke="#fff" stroke-width="1.8" stroke-linecap="round"/></svg>',
    default: '<svg viewBox="0 0 24 24" width="16" height="16"><rect x="1" y="1" width="22" height="22" rx="5" fill="#8a8a8a"/><rect x="6" y="5" width="12" height="14" rx="1" fill="none" stroke="#fff" stroke-width="1.4"/></svg>'
}

const ROOT_ID = '__root__'
const DOUBLE_CLICK_MS = 400
const CONTEXT_ITEMS = [
    { action: 'listEvents', label: 'List events' },
    { separator: true },
    { action: 'rename', label: 'Rename' },
    { action: 'recalculate', label: 'Recalculate', disabled: true },
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
        this._ctrlDown = false
        this._lastClick = { id: null, time: 0 }
        this._menuEl = null
        this._highlightedLeaf = null // see _applySelectionHighlight

        this._root = { id: ROOT_ID, name: '', children: [], expanded: true }

        this._tree = new Tree(this._root, {
            parent: container,
            move: true,
            select: true,
            holdTime: 0 // we drive rename via the context menu, not press-and-hold
        }, TREE_STYLES)

        this._tree.on('render', (leaf) => this._onRender(leaf))
        this._tree.on('clicked', (leaf) => this._onClicked(leaf))
        this._tree.on('move-pending', (leaf) => this._onMovePending(leaf))
        this._tree.on('move', (leaf) => this._onMove(leaf))
        this._tree.on('name-change', (leaf, name) => this._onNameChange(leaf, name))

        window.addEventListener('keydown', (e) => { if (e.key === 'Control') this._ctrlDown = true })
        window.addEventListener('keyup', (e) => { if (e.key === 'Control') this._ctrlDown = false })
        window.addEventListener('blur', () => { this._ctrlDown = false })
        document.addEventListener('mousedown', (e) => this._maybeCloseMenu(e))
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
                canListEvents: !!n.canListEvents
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
            this._openMenu(e.pageX, e.pageY, data)
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
        // Remember the pre-drag position so a Ctrl-held drop can be reverted.
        this._pending = {
            data: leaf.data,
            oldParent: leaf.data.parent,
            oldIndex: leaf.data.parent.children.indexOf(leaf.data)
        }
    }

    _onMove(leaf) {
        const data = leaf.data
        const newParent = data.parent
        const targetId = newParent.id === ROOT_ID ? null : newParent.id

        if (this._ctrlDown && this._pending && this._pending.data === data) {
            // "Apply transformation" gesture: undo the reparent yy-tree just
            // performed, then tell MATLAB about source/target; MATLAB builds
            // the actual new result node (if any) itself.
            const { oldParent, oldIndex } = this._pending
            newParent.children.splice(newParent.children.indexOf(data), 1)
            oldParent.children.splice(oldIndex, 0, data)
            data.parent = oldParent
            this._tree.update()
            this._onEvent({ type: 'nodeDropped', sourceId: data.id, targetId, reparented: false })
        } else {
            // Real reparent: yy-tree has already updated its own data/DOM.
            this._onEvent({ type: 'nodeDropped', sourceId: data.id, targetId, reparented: true })
        }
        this._pending = null
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
            const disabled = item.disabled || (item.action === 'listEvents' && !data.canListEvents)
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
