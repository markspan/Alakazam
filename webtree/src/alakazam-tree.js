// alakazam-tree.js
// Thin wrapper around yy-tree adding: per-node icons, a custom context menu,
// double-click detection, and Ctrl-aware drop semantics matching Alakazam's
// existing tree (no-modifier drop = real reparent, left entirely to yy-tree;
// Ctrl-held drop = "apply transformation to the node dropped onto" -- the
// visual/data move yy-tree performs is reverted, and only a bridge event is
// emitted, since MATLAB will build the actual new result node itself).
import { Tree } from 'yy-tree'

const ICONS = {
    raw:  '<svg viewBox="0 0 24 24" width="16" height="16"><rect x="3" y="2" width="16" height="20" rx="1" fill="none" stroke="#5a4a2f" stroke-width="1.5"/><path d="M7 7h8M7 11h8M7 15h5" stroke="#5a4a2f" stroke-width="1.2" stroke-linecap="round"/></svg>',
    time: '<svg viewBox="0 0 24 24" width="16" height="16"><rect x="2" y="4" width="20" height="16" rx="1" fill="none" stroke="#2f5a4a" stroke-width="1.5"/><path d="M4 14l3-4 3 5 3-7 3 4 4-3" fill="none" stroke="#2f5a4a" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    freq: '<svg viewBox="0 0 24 24" width="16" height="16"><rect x="2" y="4" width="20" height="16" rx="1" fill="none" stroke="#2f3f5a" stroke-width="1.5"/><path d="M5 17V13M9 17V9M13 17V15M17 17V7M20 17V11" stroke="#2f3f5a" stroke-width="1.4" stroke-linecap="round"/></svg>',
    default: '<svg viewBox="0 0 24 24" width="16" height="16"><rect x="3" y="4" width="18" height="16" rx="1" fill="none" stroke="#555" stroke-width="1.5"/></svg>'
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

        this._root = { id: ROOT_ID, name: '', children: [], expanded: true }

        this._tree = new Tree(this._root, {
            parent: container,
            move: true,
            select: true,
            holdTime: 0 // we drive rename via the context menu, not press-and-hold
        })

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
            if (this._tree._selection) {
                this._tree._selection.name.classList.remove(`${this._tree.prefixClassName}-select`)
            }
            this._tree._selection = leaf
            leaf.name.classList.add(`${this._tree.prefixClassName}-select`)
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
        const iconHtml = ICONS[data.icon] || ICONS.default
        const iconSpan = document.createElement('span')
        iconSpan.className = 'alz-icon'
        iconSpan.innerHTML = iconHtml
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
