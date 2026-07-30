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

    // 获取文本图层的样式信息（字号、颜色、粗细等）
    function getTextStyle(layer) {
        var style = {};
        try {
            var textItem = layer.textItem;

            // 字号
            try {
                style.fontSize = textItem.size.as("px") + "px";
            } catch (e) {
                style.fontSize = null;
            }

            // 字体名称
            try {
                style.fontName = textItem.font;
            } catch (e) {
                style.fontName = null;
            }

            // 字体样式（粗体/斜体等，通过 fauxBold / fauxItalic）
            try {
                style.fauxBold = textItem.fauxBold;
            } catch (e) {
                style.fauxBold = null;
            }
            try {
                style.fauxItalic = textItem.fauxItalic;
            } catch (e) {
                style.fauxItalic = null;
            }

            // 颜色
            try {
                var color = textItem.color;
                var r = Math.round(color.rgb.red);
                var g = Math.round(color.rgb.green);
                var b = Math.round(color.rgb.blue);
                style.color = "#" +
                    (r < 16 ? "0" : "") + r.toString(16) +
                    (g < 16 ? "0" : "") + g.toString(16) +
                    (b < 16 ? "0" : "") + b.toString(16);
            } catch (e) {
                style.color = null;
            }

            // 对齐方式
            try {
                style.justification = textItem.justification.toString().replace("Justification.", "");
            } catch (e) {
                style.justification = null;
            }

            // 行距（自动行距时可能报错）
            try {
                style.leading = textItem.leading.as("px") + "px";
            } catch (e) {
                style.leading = "auto";
            }

            // 字间距
            try {
                style.tracking = textItem.tracking;
            } catch (e) {
                style.tracking = null;
            }

            // 文本内容
            try {
                style.contents = textItem.contents;
            } catch (e) {
                style.contents = null;
            }

        } catch (e) {
            style.error = e.message || "Failed to read text style";
        }
        return style;
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

            // 如果是文本图层，添加样式信息
            if (type === "TEXT") {
                var style = getTextStyle(layer);
                obj += ',\n';
                obj += pad + '"textStyle": {\n';
                var styleItems = [];
                if (style.fontSize !== undefined && style.fontSize !== null)
                    styleItems.push(pad + '  "fontSize": "' + escapeStr(style.fontSize) + '"');
                if (style.fontName !== undefined && style.fontName !== null)
                    styleItems.push(pad + '  "fontName": "' + escapeStr(style.fontName) + '"');
                if (style.fauxBold !== undefined && style.fauxBold !== null)
                    styleItems.push(pad + '  "fauxBold": ' + (style.fauxBold ? "true" : "false"));
                if (style.fauxItalic !== undefined && style.fauxItalic !== null)
                    styleItems.push(pad + '  "fauxItalic": ' + (style.fauxItalic ? "true" : "false"));
                if (style.color !== undefined && style.color !== null)
                    styleItems.push(pad + '  "color": "' + escapeStr(style.color) + '"');
                if (style.justification !== undefined && style.justification !== null)
                    styleItems.push(pad + '  "justification": "' + escapeStr(style.justification) + '"');
                if (style.leading !== undefined && style.leading !== null)
                    styleItems.push(pad + '  "leading": "' + escapeStr(style.leading) + '"');
                if (style.tracking !== undefined && style.tracking !== null)
                    styleItems.push(pad + '  "tracking": ' + style.tracking);
                if (style.contents !== undefined && style.contents !== null)
                    styleItems.push(pad + '  "contents": "' + escapeStr(style.contents) + '"');
                if (style.error !== undefined)
                    styleItems.push(pad + '  "error": "' + escapeStr(style.error) + '"');
                obj += styleItems.join(",\n");
                obj += "\n" + pad + "}";
            }

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
