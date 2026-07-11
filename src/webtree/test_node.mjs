import { JSDOM } from 'jsdom'
import fs from 'fs'
import assert from 'assert'

const bundleSrc = fs.readFileSync('dist/alakazam-tree.bundle.js', 'utf8')

const dom = new JSDOM('<!doctype html><html><body><div id="tree"></div></body></html>', {
    url: 'http://localhost/',
    pretendToBeVisual: true,
    runScripts: 'dangerously'
})
const { window } = dom
global.window = window
global.document = window.document

// Load the bundle via a real <script> tag, matching how a browser (and
// uihtml) actually loads it -- more faithful than window.eval, whose
// top-level scoping in jsdom does not reliably land on window.
const scriptEl = window.document.createElement('script')
scriptEl.textContent = bundleSrc
window.document.head.appendChild(scriptEl)
assert.ok(window.AlakazamTree, 'AlakazamTree global should exist after loading the bundle')

const events = []
const container = window.document.getElementById('tree')
const tree = window.AlakazamTree.create(container, { onEvent: (e) => events.push(e) })

const FAKE_ICON_URI = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='

tree.setNodes([
    { id: 'a', label: 'RawImport', icon: 'raw', parentId: null },
    { id: 'b', label: 'Fourier1', icon: 'freq', parentId: 'a' },
    { id: 'c', label: 'Average1', icon: 'time', parentId: 'a', canListEvents: false },
    { id: 'd', label: 'RawImport2', icon: 'raw', parentId: null },
    { id: 'e', label: 'FourierResult1', icon: FAKE_ICON_URI, parentId: 'a' }
])

// --- 1. rendering + icons ---
const icons = container.querySelectorAll('.alz-icon')
console.log(`icons rendered: ${icons.length} (expect 5)`)
assert.strictEqual(icons.length, 5, 'one icon per node')
assert.ok(icons[0].innerHTML.includes('<svg'), 'key-based icon contains inline svg')

// A data:-URI icon (WorkSpaceTree.iconForResult, a per-transformation icon)
// must render as a scaled <img>, not be looked up in the fixed ICONS map.
const leafE = findLeafByLabel('FourierResult1')
const imgEl = leafE.content.querySelector('.alz-icon img.alz-icon-img')
assert.ok(imgEl, 'data-URI icon should render as an <img class="alz-icon-img">')
assert.strictEqual(imgEl.src, FAKE_ICON_URI, 'img src should be the exact data URI passed in')
assert.strictEqual(imgEl.width, 16, 'icon should be scaled down to 16px wide')
assert.strictEqual(imgEl.height, 16, 'icon should be scaled down to 16px tall')

// --- 2. single click ---
function findLeafByLabel(label) {
    const walk = (el) => {
        if (el.isLeaf && el.data.name === label) return el
        for (const child of el.children || []) {
            const r = walk(child)
            if (r) return r
        }
        return null
    }
    return walk(tree._tree.element)
}

// yy-tree's Input._down/_up read e.pageX/e.pageY directly, which jsdom's
// MouseEvent constructor does not populate. Call the handlers with plain
// objects carrying the fields yy-tree actually reads, exactly as its own
// leaf.name 'mousedown' listener invokes this._input._down(e).
function down(leaf, x, y) {
    tree._tree._input._down({
        currentTarget: leaf.name, pageX: x, pageY: y,
        preventDefault() {}, stopPropagation() {}
    })
}
function up(x, y) {
    tree._tree._input._up({ pageX: x, pageY: y })
}

events.length = 0
const leafB = findLeafByLabel('Fourier1')
down(leafB, 10, 10); up(10, 10)   // no movement -> a click, not a drag
console.log('after single click:', JSON.stringify(events))
assert.strictEqual(events.length, 1, 'one click event');
assert.strictEqual(JSON.stringify(events[0]), JSON.stringify({ type: 'nodeClicked', id: 'b' }))

// --- 3. double click (second click on the same node within 400ms) ---
events.length = 0
down(leafB, 10, 10); up(10, 10)
console.log('after second click (should be double):', JSON.stringify(events))
assert.strictEqual(events.length, 1)
assert.strictEqual(JSON.stringify(events[0]), JSON.stringify({ type: 'nodeDoubleClicked', id: 'b' }))

// --- 4. context menu ---
events.length = 0
const leafC = findLeafByLabel('Average1')   // canListEvents:false
leafC.content.dispatchEvent(new window.MouseEvent('contextmenu', { bubbles: true, cancelable: true, pageX: 50, pageY: 50 }))
const menu = window.document.querySelector('.alz-menu')
assert.ok(menu, 'context menu should be shown')
const items = [...menu.querySelectorAll('.alz-menu-item')].map(el => el.textContent)
console.log('menu items:', items);
assert.strictEqual(JSON.stringify(items), JSON.stringify(['List events', 'Rename', 'Recalculate', 'Delete']))
const listEventsItem = [...menu.querySelectorAll('.alz-menu-item')].find(el => el.textContent === 'List events')
assert.ok(listEventsItem.classList.contains('alz-menu-item-disabled'), 'List events should be disabled for canListEvents:false node')
const renameItem = [...menu.querySelectorAll('.alz-menu-item')].find(el => el.textContent === 'Rename')
renameItem.dispatchEvent(new window.MouseEvent('click', { bubbles: true }))
console.log('after clicking Rename:', JSON.stringify(events))
assert.strictEqual(JSON.stringify(events[events.length - 1]), JSON.stringify({ type: 'contextMenuAction', action: 'rename', id: 'c' }))
assert.ok(!window.document.querySelector('.alz-menu'), 'menu should close after an action')

console.log('\nREAL-DOM CHECKS OK (render/click/double-click/context-menu)\n')

// --- 5. move / Ctrl-revert logic ---
// Real pixel-accurate drag can't be simulated in jsdom (no layout engine:
// getBoundingClientRect() is always zero), so this drives the wrapper via
// the same event contract yy-tree's own Input._up() uses: 'move-pending'
// fires before the drag, then the library mutates leaf.data.parent/children
// itself (verified directly in yy-tree's input.js _moveData()) before
// 'move' fires. We simulate exactly that mutation, then emit the events,
// to test OUR OWN logic (the Ctrl-revert) against that real contract.
function simulateDrag(tree, leaf, newParentData, ctrlDown) {
    tree._ctrlDown = ctrlDown
    tree._tree.emit('move-pending', leaf, tree._tree)
    // Mimic yy-tree's Input._moveData(): splice out of the old parent,
    // splice into the new parent, repoint .parent.
    const data = leaf.data
    const oldParent = data.parent
    oldParent.children.splice(oldParent.children.indexOf(data), 1)
    newParentData.children.push(data)
    data.parent = newParentData
    tree._tree.emit('move', leaf, tree._tree)
    tree._ctrlDown = false
}

function childIds(parentData) {
    return parentData.children.map(c => c.id)
}

// --- 5a. no Ctrl: real reparent, yy-tree's mutation stands ---
events.length = 0
const leafD = findLeafByLabel('RawImport2')     // top-level node 'd'
const parentAData = tree._byId.get('a')          // move 'd' under 'a'
console.log('before: root children =', childIds(tree._root), ' a children =', childIds(parentAData))
simulateDrag(tree, leafD, parentAData, false)
console.log('after no-ctrl move: root children =', childIds(tree._root), ' a children =', childIds(parentAData))
console.log('events:', JSON.stringify(events))
assert.strictEqual(JSON.stringify(events), JSON.stringify([{ type: 'nodeDropped', sourceId: 'd', targetId: 'a', reparented: true }]))
assert.ok(childIds(parentAData).includes('d'), 'd should now be a child of a (real reparent kept)')
assert.ok(!childIds(tree._root).includes('d'), 'd should no longer be a top-level/root child')

// --- 5b. Ctrl held: apply-transformation signal, move must be reverted ---
events.length = 0
const leafC2 = findLeafByLabel('Average1')       // currently a child of 'a'
const parentAContentsBefore = childIds(parentAData)
console.log('before ctrl-drag: a children =', parentAContentsBefore)
simulateDrag(tree, leafC2, parentAData, true)    // drop 'c' back onto its own parent 'a', Ctrl held
console.log('after ctrl-drag: a children =', childIds(parentAData))
console.log('events:', JSON.stringify(events))
assert.strictEqual(JSON.stringify(events), JSON.stringify([{ type: 'nodeDropped', sourceId: 'c', targetId: 'a', reparented: false }]))
assert.strictEqual(JSON.stringify(childIds(parentAData)), JSON.stringify(parentAContentsBefore), 'tree structure must be unchanged (reverted) when Ctrl was held')

// --- 5c. Ctrl held, dropped onto a DIFFERENT parent: must revert to the true original parent ---
events.length = 0
const leafB2 = findLeafByLabel('Fourier1')       // child of 'a'
const rootChildrenBefore = childIds(tree._root)
const aChildrenBefore = childIds(parentAData)
simulateDrag(tree, leafB2, tree._root, true)     // drag 'b' out to root level, Ctrl held
console.log('after ctrl-drag to root: root children =', childIds(tree._root), ' a children =', childIds(parentAData))
console.log('events:', JSON.stringify(events))
assert.strictEqual(JSON.stringify(events), JSON.stringify([{ type: 'nodeDropped', sourceId: 'b', targetId: null, reparented: false }]))
assert.strictEqual(JSON.stringify(childIds(tree._root)), JSON.stringify(rootChildrenBefore), 'root children reverted')
assert.strictEqual(JSON.stringify(childIds(parentAData)), JSON.stringify(aChildrenBefore), 'b should be back under a, not left at root')

console.log('\nMOVE / CTRL-REVERT LOGIC OK\n')
