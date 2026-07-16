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
    { id: 'e', label: 'FourierResult1', icon: FAKE_ICON_URI, parentId: 'a' },
    { id: 'f', label: 'GrandAverage1', icon: 'grandAverage', parentId: null }
])

// --- 1. rendering + icons ---
const icons = container.querySelectorAll('.alz-icon')
console.log(`icons rendered: ${icons.length} (expect 6)`)
assert.strictEqual(icons.length, 6, 'one icon per node')
assert.ok(icons[0].innerHTML.includes('<svg'), 'key-based icon contains inline svg')

// 'grandAverage' is its own dedicated icon (see alakazam-tree.js's ICONS
// map), not a fallback to ICONS.default -- confirm it renders its own
// distinct purple badge, not the grey default-icon badge.
const grandAverageLeaf = findLeafByLabel('GrandAverage1')
const gaIconHtml = grandAverageLeaf.content.querySelector('.alz-icon').innerHTML
assert.ok(gaIconHtml.includes('#2e5c8a'), 'grandAverage icon should render its own dedicated navy-blue badge, not fall back to default')
console.log('grandAverage renders its own dedicated icon, not the default fallback: OK')

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
function move(x, y) {
    tree._tree._input._move({ pageX: x, pageY: y })
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

// --- 3b. a small, sub-threshold cursor movement during a click must still
//     register as a click, not a drag -- this is the actual bug being
//     regression-tested here: yy-tree's Input._checkThreshold used to check
//     only whether the mouse moved AT ALL since mousedown, never comparing
//     it against the tree's own configured `threshold` (10px), so ordinary
//     mouse jitter while clicking (a few pixels) was silently registered as
//     a drag instead. Uses a different node (leafD, not leafB) so this does
//     not disturb leafB's double-click timing state above. ---
events.length = 0
const leafJitter = findLeafByLabel('RawImport2')
down(leafJitter, 10, 10)
move(13, 12) // distance ~3.6px, well under the 10px threshold -- must NOT start a drag
assert.ok(!tree._tree._input._moving, 'a few pixels of jitter must not cross the drag threshold')
up(13, 12)
console.log('after click with sub-threshold jitter:', JSON.stringify(events))
assert.strictEqual(events.length, 1, 'jitter within the threshold should still be one click event, not a drag')
assert.strictEqual(JSON.stringify(events[0]), JSON.stringify({ type: 'nodeClicked', id: 'd' }))
console.log('sub-threshold mouse jitter during a click is not mistaken for a drag: OK')

// --- 4. context menu ---
events.length = 0
const leafC = findLeafByLabel('Average1')   // canListEvents:false
leafC.content.dispatchEvent(new window.MouseEvent('contextmenu', { bubbles: true, cancelable: true, pageX: 50, pageY: 50 }))
const menu = window.document.querySelector('.alz-menu')
assert.ok(menu, 'context menu should be shown')
const items = [...menu.querySelectorAll('.alz-menu-item')].map(el => el.textContent)
console.log('menu items:', items);
assert.strictEqual(JSON.stringify(items), JSON.stringify(['List events', 'Rename', 'Recalculate', 'Apply to All Raw Files...', 'Save Template...', 'Apply Template...', 'Delete']))
const listEventsItem = [...menu.querySelectorAll('.alz-menu-item')].find(el => el.textContent === 'List events')
assert.ok(listEventsItem.classList.contains('alz-menu-item-disabled'), 'List events should be disabled for canListEvents:false node')
const applyToAllItem = [...menu.querySelectorAll('.alz-menu-item')].find(el => el.textContent === 'Apply to All Raw Files...')
assert.ok(applyToAllItem.classList.contains('alz-menu-item-disabled'), 'Apply to All Raw Files should be disabled when canApplyToAll is not set')
const saveTemplateItem = [...menu.querySelectorAll('.alz-menu-item')].find(el => el.textContent === 'Save Template...')
assert.ok(saveTemplateItem.classList.contains('alz-menu-item-disabled'), 'Save Template should be disabled when canApplyToAll is not set (same eligibility as Apply to All)')
const applyTemplateItem = [...menu.querySelectorAll('.alz-menu-item')].find(el => el.textContent === 'Apply Template...')
assert.ok(!applyTemplateItem.classList.contains('alz-menu-item-disabled'), 'Apply Template should always be enabled, regardless of node capability flags')
const renameItem = [...menu.querySelectorAll('.alz-menu-item')].find(el => el.textContent === 'Rename')
renameItem.dispatchEvent(new window.MouseEvent('click', { bubbles: true }))
console.log('after clicking Rename:', JSON.stringify(events))
assert.strictEqual(JSON.stringify(events[events.length - 1]), JSON.stringify({ type: 'contextMenuAction', action: 'rename', id: 'c' }))
assert.ok(!window.document.querySelector('.alz-menu'), 'menu should close after an action')

console.log('\nREAL-DOM CHECKS OK (render/click/double-click/context-menu)\n')

// --- 5. drop-always-reverts logic ---
// Real pixel-accurate drag can't be simulated in jsdom (no layout engine:
// getBoundingClientRect() is always zero), so this drives the wrapper via
// the same event contract yy-tree's own Input._up() uses: 'move-pending'
// fires before the drag, then the library mutates leaf.data.parent/children
// itself (verified directly in yy-tree's input.js _moveData()) before
// 'move' fires. We simulate exactly that mutation, then emit the events,
// to test OUR OWN logic (the always-revert) against that real contract.
function simulateDrag(tree, leaf, newParentData) {
    tree._tree.emit('move-pending', leaf, tree._tree)
    // Mimic yy-tree's Input._moveData(): splice out of the old parent,
    // splice into the new parent, repoint .parent.
    const data = leaf.data
    const oldParent = data.parent
    oldParent.children.splice(oldParent.children.indexOf(data), 1)
    newParentData.children.push(data)
    data.parent = newParentData
    tree._tree.emit('move', leaf, tree._tree)
}

function childIds(parentData) {
    return parentData.children.map(c => c.id)
}

// --- 5a. dropping a node onto another must revert the move (yy-tree's own
//     mutation undone) and emit a plain nodeDropped event -- no Ctrl needed,
//     no "real reparent" path exists at all in this tree ---
events.length = 0
const parentAData = tree._byId.get('a')
const leafC2 = findLeafByLabel('Average1')       // currently a child of 'a'
const parentAContentsBefore = childIds(parentAData)
console.log('before drag: a children =', parentAContentsBefore)
simulateDrag(tree, leafC2, parentAData)          // drop 'c' back onto its own parent 'a'
console.log('after drag: a children =', childIds(parentAData))
console.log('events:', JSON.stringify(events))
assert.strictEqual(JSON.stringify(events), JSON.stringify([{ type: 'nodeDropped', sourceId: 'c', targetId: 'a' }]))
assert.strictEqual(JSON.stringify(childIds(parentAData)), JSON.stringify(parentAContentsBefore), 'tree structure must be unchanged (reverted)')

// --- 5b. dropped onto a DIFFERENT parent: must revert to the true original parent ---
events.length = 0
const leafB2 = findLeafByLabel('Fourier1')       // child of 'a'
const rootChildrenBefore = childIds(tree._root)
const aChildrenBefore = childIds(parentAData)
simulateDrag(tree, leafB2, tree._root)           // drag 'b' out to root level
console.log('after drag to root: root children =', childIds(tree._root), ' a children =', childIds(parentAData))
console.log('events:', JSON.stringify(events))
assert.strictEqual(JSON.stringify(events), JSON.stringify([{ type: 'nodeDropped', sourceId: 'b', targetId: null }]))
assert.strictEqual(JSON.stringify(childIds(tree._root)), JSON.stringify(rootChildrenBefore), 'root children reverted')
assert.strictEqual(JSON.stringify(childIds(parentAData)), JSON.stringify(aChildrenBefore), 'b should be back under a, not left at root')

// --- 5c. dragging a top-level node onto another top-level node must also
//     revert (this used to be the "real reparent" case with no modifier) ---
events.length = 0
const leafD = findLeafByLabel('RawImport2')      // top-level node 'd'
console.log('before drag: root children =', childIds(tree._root), ' a children =', childIds(parentAData))
simulateDrag(tree, leafD, parentAData)           // drop 'd' onto 'a'
console.log('after drag: root children =', childIds(tree._root), ' a children =', childIds(parentAData))
console.log('events:', JSON.stringify(events))
assert.strictEqual(JSON.stringify(events), JSON.stringify([{ type: 'nodeDropped', sourceId: 'd', targetId: 'a' }]))
assert.ok(!childIds(parentAData).includes('d'), 'd must NOT end up as a child of a -- there is no move/reparent gesture anymore')
assert.ok(childIds(tree._root).includes('d'), 'd should still be a top-level/root child, unchanged')

console.log('\nDROP-ALWAYS-REVERTS LOGIC OK\n')

// --- 6. cursor feedback: the "copy"/apply cursor is on for the duration of
//     a drag (move-pending .. move) and off both before and after -- a drop
//     never moves the node, so the native browser "move" cursor would be
//     misleading (see alakazam-tree.css's html.alz-dragging rule). ---
const html = window.document.documentElement
assert.ok(!html.classList.contains('alz-dragging'), 'cursor override should be off before any drag starts')
const leafC3 = findLeafByLabel('Average1')
tree._tree.emit('move-pending', leafC3, tree._tree)
assert.ok(html.classList.contains('alz-dragging'), 'cursor override should turn on once a drag crosses the move threshold')
const dataC = leafC3.data
const oldParentC = dataC.parent
oldParentC.children.splice(oldParentC.children.indexOf(dataC), 1)
parentAData.children.push(dataC)
dataC.parent = parentAData
tree._tree.emit('move', leafC3, tree._tree)
assert.ok(!html.classList.contains('alz-dragging'), 'cursor override should turn off again once the drop completes')
console.log('drag-cursor override toggles on for move-pending..move, off otherwise: OK')
// This drop also turned alz-busy on (see test 7); clear it here to simulate
// bridge.js's applyData reporting MATLAB is done, which isn't exercised by
// this bundle-only test (bridge.js isn't part of the built bundle -- see
// build.mjs), so the next test starts from a clean, known state.
html.classList.remove('alz-busy')

// --- 7. busy cursor: turns on once a drop is sent (MATLAB now has to
//     actually run the dropped branch's transformations), independent of
//     the alz-dragging cursor which is already off by then. Clearing it
//     again is bridge.js's job (applyData, not bundled/exercised here --
//     bridge.js is 3 lines, reviewed by hand) once MATLAB reports back.
//     Every leaf reference used below is re-fetched fresh via
//     findLeafByLabel immediately before use: _onMove's revert calls
//     tree._tree.update(), which rebuilds the whole DOM from the data
//     graph, so any leaf element captured before an earlier revert is
//     already detached and stale. ---
assert.ok(!html.classList.contains('alz-busy'), 'busy cursor should be off before any drop')
const leafC4 = findLeafByLabel('Average1')
tree._tree.emit('move-pending', leafC4, tree._tree)
const dataC2 = leafC4.data
const oldParentC2 = dataC2.parent
oldParentC2.children.splice(oldParentC2.children.indexOf(dataC2), 1)
parentAData.children.push(dataC2)
dataC2.parent = parentAData
tree._tree.emit('move', leafC4, tree._tree)
assert.ok(html.classList.contains('alz-busy'), 'busy cursor should turn on once the drop is sent to MATLAB')
console.log('busy cursor turns on once a drop is sent: OK')

// --- 8. drop-target highlight: whichever node the drag indicator is
//     currently parented under gets alz-drop-target -- real pixel-based
//     hit-testing can't be simulated in jsdom (see the file header comment
//     above), so this drives _onDragPointerMove directly against a
//     manually-repositioned indicator element, exactly mirroring what
//     yy-tree's own Input._move() would have just done to it. ---
events.length = 0
const leafBDrag = findLeafByLabel('Fourier1')       // the node being dragged
tree._tree.emit('move-pending', leafBDrag, tree._tree)
const indicatorEl = tree._tree._input._indicator.get()

let leafTarget = findLeafByLabel('FourierResult1')  // a different node, not being dragged
indicatorEl.remove()
leafTarget.appendChild(indicatorEl)
tree._onDragPointerMove()
assert.ok(leafTarget.content.classList.contains('alz-drop-target'), 'the node the indicator is parented under should be highlighted')
console.log('drop-target highlight follows the indicator to a real node: OK')

indicatorEl.remove()
tree._tree.element.appendChild(indicatorEl) // root/no-target position
tree._onDragPointerMove()
assert.ok(!leafTarget.content.classList.contains('alz-drop-target'), 'highlight should clear when the indicator moves to the root (no target)')
console.log('drop-target highlight clears for a root/no-target position: OK')

indicatorEl.remove()
leafBDrag.appendChild(indicatorEl) // the dragged node's own element -- must never highlight itself
tree._onDragPointerMove()
assert.ok(!leafBDrag.content.classList.contains('alz-drop-target'), 'the dragged node must never highlight itself as its own drop target')
console.log('drop-target highlight never targets the node being dragged: OK')

leafTarget = findLeafByLabel('FourierResult1')
indicatorEl.remove()
leafTarget.appendChild(indicatorEl)
tree._onDragPointerMove()
tree._tree.emit('move', leafBDrag, tree._tree)
assert.ok(!leafTarget.content.classList.contains('alz-drop-target'), 'drop-target highlight should clear once the drop completes')
console.log('drop-target highlight clears once the drop completes: OK')

// --- 9-12: cursor leaving the tree mid-drag, using a REAL Input pickup
//     (down() + move() past the threshold, not the emit('move-pending')
//     shortcut the earlier tests use -- that shortcut only fires OUR own
//     event handlers, it never touches Input._target/_moving/indicator at
//     all, so it can't exercise _cancelDrag's interaction with real Input
//     state). mouseleave/mouseenter/mouseup are dispatched as real DOM
//     events on document.body so the actual listener wiring (registration
//     order, stopImmediatePropagation) is what's under test, not a direct
//     call into internals. ---
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
const input = tree._tree._input
const LEAVE_GRACE_MS = 250 // must match alakazam-tree.js's own LEAVE_GRACE_MS (not exported)

// --- 9. mouseleave mid-drag must be intercepted before Input's own
//     listener ever sees it -- Input._target/_moving stay set (proving
//     Input._up() did NOT run), and no nodeDropped is sent yet. ---
html.classList.remove('alz-busy') // left on by test 8's final drop; bridge.js (not exercised here) normally clears it
events.length = 0
const leafReal = findLeafByLabel('Fourier1')
down(leafReal, 10, 10)
move(30, 30) // distance ~28px, past yy-tree's threshold (10px, see alakazam-tree.js's _checkThreshold patch), triggers a real Input._pickup()
assert.ok(html.classList.contains('alz-dragging'), 'sanity: dragging cursor should be on mid-drag')
assert.ok(input._target && input._moving, 'sanity: a real Input drag should be in progress')
window.document.body.dispatchEvent(new window.MouseEvent('mouseleave'))
assert.ok(input._target && input._moving, 'Input._up() must not have run -- its own mouseleave listener should have been intercepted')
assert.strictEqual(JSON.stringify(events), '[]', 'no nodeDropped yet -- only the grace period has started, not a cancel or a drop')
console.log('mouseleave mid-drag is intercepted before Input can finalize it: OK')

// --- 10. no re-entry within LEAVE_GRACE_MS: the drag is cancelled --
//     Input._target/_moving are cleared by _cancelDrag itself (not by
//     Input._up()), no nodeDropped is ever sent, and the tree/data is
//     completely unaffected (nothing was ever actually dropped). ---
await sleep(LEAVE_GRACE_MS + 150)
assert.ok(!input._target && !input._moving, 'Input state should be cleared by _cancelDrag after the grace period lapses')
assert.ok(!html.classList.contains('alz-dragging'), 'dragging cursor should turn off once the drag is cancelled')
assert.strictEqual(JSON.stringify(events), '[]', 'a lapsed grace period must not send a nodeDropped event')
assert.ok(!html.classList.contains('alz-busy'), 'busy cursor must not turn on for a cancelled drag -- nothing was sent to MATLAB to report back on')
const leafAfterCancel = findLeafByLabel('Fourier1')
assert.strictEqual(leafAfterCancel.data.parent.id, 'a', 'the node must still be exactly where it started -- nothing was ever mutated')
console.log('no re-entry within the grace period cancels the drag, leaving everything untouched: OK')

// --- 11. re-entering within the grace period keeps the SAME drag alive --
//     no manual "resume" needed: Input's own state was never touched, so
//     a real mouseup after coming back finishes the drag normally. ---
events.length = 0
const leafResume = findLeafByLabel('Fourier1')
down(leafResume, 10, 10)
move(30, 30) // past the threshold -- see the comment on the identical call above
window.document.body.dispatchEvent(new window.MouseEvent('mouseleave'))
await sleep(LEAVE_GRACE_MS / 2) // well within the grace period
window.document.body.dispatchEvent(new window.MouseEvent('mouseenter'))
await sleep(LEAVE_GRACE_MS + 150) // long enough that a *lapsed* timer would have fired by now
assert.ok(input._target && input._moving, 'the drag should still be alive -- the cancel timer must have been cleared by mouseenter')
window.document.body.dispatchEvent(new window.MouseEvent('mouseup'))
assert.strictEqual(events.length, 1, 'a real mouseup after returning in time should complete the drag normally')
assert.strictEqual(events[0].type, 'nodeDropped')
assert.strictEqual(events[0].sourceId, 'b')
assert.ok(html.classList.contains('alz-busy'), 'busy cursor should turn on for this real, completed drop')
console.log('returning to the tree within the grace period keeps the drag alive: OK')

// --- 12. a stray mouseleave/mouseenter with no drag in progress must not
//     misbehave (the interceptor only arms when this._pending is set). ---
html.classList.remove('alz-busy')
events.length = 0
window.document.body.dispatchEvent(new window.MouseEvent('mouseleave'))
window.document.body.dispatchEvent(new window.MouseEvent('mouseenter'))
await sleep(LEAVE_GRACE_MS + 150)
assert.strictEqual(JSON.stringify(events), '[]', 'a stray mouseleave/mouseenter with no drag in progress must not emit anything')
console.log('a stray mouseleave with no drag in progress is a no-op: OK')
