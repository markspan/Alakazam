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
        if (data && data.nodes) {
            tree.setNodes(data.nodes, data.selectedId)
            htmlComponent.sendEventToMATLAB('rendered', {
                nodeCount: data.nodes.length,
                iconCount: document.querySelectorAll('.alz-icon').length
            })
        }
    }
    applyData(htmlComponent.Data)
    htmlComponent.addEventListener('DataChanged', function () {
        applyData(htmlComponent.Data)
    })
}
