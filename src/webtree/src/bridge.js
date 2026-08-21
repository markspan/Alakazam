// bridge.js -- glue between uihtml's MATLAB<->JS contract and AlakazamTree.
// Data shape from MATLAB (htmlComponent.Data):
//   { nodes: [ {id, label, icon, parentId, expanded, canListEvents}, ... ],
//     selectedId: <id|null> }
// Events sent to MATLAB (htmlComponent.sendEventToMATLAB(name, payload)):
//   nodeClicked        {id}
//   nodeDoubleClicked  {id}
//   nodeDropped        {sourceId, targetId, reparented}
//   nodeRenamed        {id, name}
//   contextMenuAction  {action, id}
//   renderError        {message, stack} -- see applyData's catch below
function setup(htmlComponent) {
    var container = document.getElementById('tree')
    var tree = AlakazamTree.create(container, {
        onEvent: function (e) {
            var name = e.type
            var payload = {}
            for (var k in e) { if (k !== 'type') payload[k] = e[k] }
            htmlComponent.sendEventToMATLAB(name, payload)
        }
    })

    function applyData(data) {
        // Any fresh Data push from MATLAB means it's no longer busy handling
        // whatever caused the push (a drop's evaluateDroppedBranch is the
        // main case -- see alakazam-tree.js's _onMove/alakazam-tree.css's
        // html.alz-busy rule); WorkSpaceTree.notifyDropHandled guarantees a
        // push happens for every drop outcome, so this always fires.
        document.documentElement.classList.remove('alz-busy')
        try {
            if (data && data.nodes) {
                tree.setNodes(data.nodes, data.selectedId)
                htmlComponent.sendEventToMATLAB('rendered', {
                    nodeCount: data.nodes.length,
                    iconCount: document.querySelectorAll('.alz-icon').length
                })
            }
        } catch (e) {
            // A JS exception here would otherwise die silently in this
            // embedded CEF browser's own console (not visible from MATLAB
            // at all) and surface on the MATLAB side only as a generic,
            // unactionable "HTMLSource may be referencing unsupported
            // functionality or may have a JavaScript error" warning with no
            // message or stack -- exactly what happened for the "nodes is
            // not iterable" single-node-array bug this replaces. Log it
            // here too in case devtools ever is attached, but the real
            // point is telling MATLAB directly via a dedicated event, since
            // sendEventToMATLAB('rendered', ...) above never runs when this
            // throws, so MATLAB would otherwise get no signal at all that
            // anything went wrong.
            console.error('WorkSpaceTree render failed:', e)
            htmlComponent.sendEventToMATLAB('renderError', {
                message: String((e && e.message) || e),
                stack: String((e && e.stack) || '')
            })
        }
    }
    applyData(htmlComponent.Data)
    htmlComponent.addEventListener('DataChanged', function () {
        applyData(htmlComponent.Data)
    })
}
