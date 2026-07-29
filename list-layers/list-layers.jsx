// list-layers.jsx
// ============================================================
// Photoshop JSX 脚本：列出所有图层（包括隐藏图层），输出 JSON 格式
// ============================================================
//
// 输出 JSON 结构：
// {
//   "document": "文件名.psb",
//   "layers": [
//     {
//       "path": "Header",
//       "name": "Header",
//       "type": "Group",
//       "visible": true,
//       "children": [
//         {
//           "path": "Header/banner",
//           "name": "banner",
//           "type": "NORMAL",
//           "visible": true
//         }
//       ]
//     }
//   ]
// }
//
// path 字段可直接复制给 ps-export.ps1 的 -Hide / -Show / -Export 参数使用
//
// ============================================================

(function () {
    if (app.documents.length === 0) {
        return '{"error": "No document is open."}';
    }

    var doc = app.activeDocument;

    function getLayerType(layer) {
        switch (layer.typename) {
            case "ArtLayer": return layer.kind.toString().replace("LayerKind.", "");
            case "LayerSet": return "Group";
            default: return layer.typename;
        }
    }

    // 转义 JSON 字符串中的特殊字符
    function escapeStr(str) {
        return str.replace(/\\/g, "\\\\")
                  .replace(/"/g, '\\"')
                  .replace(/\n/g, "\\n")
                  .replace(/\r/g, "\\r")
                  .replace(/\t/g, "\\t");
    }

    function buildLayerJson(layers, parentPath, indent) {
        var items = [];

        for (var i = 0; i < layers.length; i++) {
            var layer = layers[i];
            var fullPath = parentPath ? (parentPath + "/" + layer.name) : layer.name;
            var type = getLayerType(layer);
            var pad = indent + "    ";

            var obj = indent + "{\n";
            obj += pad + '"path": "' + escapeStr(fullPath) + '",\n';
            obj += pad + '"name": "' + escapeStr(layer.name) + '",\n';
            obj += pad + '"type": "' + type + '",\n';
            obj += pad + '"visible": ' + (layer.visible ? "true" : "false");

            // 如果是组，递归添加 children
            if (layer.typename === "LayerSet" && layer.layers.length > 0) {
                obj += ',\n';
                obj += pad + '"children": [\n';
                obj += buildLayerJson(layer.layers, fullPath, pad + "  ");
                obj += "\n" + pad + "]";
            }

            obj += "\n" + indent + "}";
            items.push(obj);
        }

        return items.join(",\n");
    }

    var json = '{\n';
    json += '  "document": "' + escapeStr(doc.name) + '",\n';
    json += '  "layers": [\n';
    json += buildLayerJson(doc.layers, "", "    ");
    json += '\n  ]\n';
    json += '}';

    return json;
})();
