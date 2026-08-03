// ps-export.jsx
// ============================================================
// Photoshop JSX 脚本：导出图层或完整页面为 PNG
// ============================================================
//
// 使用示例（通过 ps-export.ps1 调用）：
//
//   # 导出完整页面：
//   powershell -ExecutionPolicy Bypass -File "G:\ps-export.ps1" "G:\1.psb"
//
//   # 隐藏图层后导出完整页面：
//   powershell -ExecutionPolicy Bypass -File "G:\ps-export.ps1" "G:\1.psb" -Hide "Header/watermark","Footer/old"
//
//   # 显示图层后导出完整页面：
//   powershell -ExecutionPolicy Bypass -File "G:\ps-export.ps1" "G:\1.psb" -Show "Header/new logo"
//
//   # 导出指定图层为单独的 PNG：
//   powershell -ExecutionPolicy Bypass -File "G:\ps-export.ps1" "G:\1.psb" -Export "Header/banner","Content/icon"
//
//   # 组合使用：隐藏图层 + 导出指定图层：
//   powershell -ExecutionPolicy Bypass -File "G:\ps-export.ps1" "G:\1.psb" -Hide "Header/watermark" -Export "Header/banner"
//
// 参数说明（由 PowerShell 传入的 JSON 字符串）：
//   {
//     "hide": ["图层路径", ...],      // 导出前隐藏的图层
//     "show": ["图层路径", ...],      // 导出前显示的图层
//     "export": ["图层路径", ...]     // 要单独导出的图层
//   }
//
// 图层路径格式：
//   - 精确路径：  "组名/子组名/图层名"
//   - 顶层图层：  "图层名"
//   - 路径分隔符：  "/"
//
// 执行逻辑：
//   1. 执行 -Hide：隐藏指定图层
//   2. 执行 -Show：显示指定图层
//   3. 判断 -Export 参数：
//      - 没有：合并所有可见图层，导出完整页面为 "export.png"
//      - 有：逐个导出指定图层为单独 PNG
//        （文件名为图层路径，"/" 替换为 "_"，如 "Header_banner.png"）
//      - 如果指定的图层路径不存在，报错并中止
//   4. 还原所有图层的可见性到脚本执行前的状态
//
// 输出文件（保存在源 PSD/PSB 同目录下）：
//   - 完整页面：export.png
//   - 单独图层：Header_banner.png、Content_icon.png 等
//
// ============================================================

(function () {
    // 没有打开的文档则退出
    if (app.documents.length === 0) {
        return "ERROR: No document is open in Photoshop.";
    }

    var doc = app.activeDocument;

    // --- 全局禁止弹出对话框，防止操作过程中弹窗阻塞脚本 ---
    var globalDialogMode = app.displayDialogs;
    app.displayDialogs = DialogModes.NO;

    // --- 解析参数 ---
    // 参数通过全局变量 __args（JSON 字符串）传入
    var hideList = [];
    var showList = [];
    var exportList = [];

    try {
        var argsStr = "";
        // 优先从全局变量读取，兼容 $.evalFile 传参方式
        if (typeof __args !== "undefined" && __args !== "") {
            argsStr = __args;
        } else if (typeof arguments !== "undefined" && arguments.length > 0) {
            argsStr = arguments[0];
        }
        if (argsStr) {
            var args = eval("(" + argsStr + ")");
            if (args.hide) hideList = args.hide;
            if (args.show) showList = args.show;
            if (args["export"]) exportList = args["export"];
        }
    } catch (e) {
        // 参数解析失败，返回错误信息
        app.displayDialogs = globalDialogMode;
        return "ERROR: Failed to parse arguments: " + e.message;
    }

    // --- 工具函数：按精确路径查找图层 ---
    // 示例：findLayerByPath(doc.layers, "Header/Nav/icon")
    // 逐级进入组，找不到返回 null
    function findLayerByPath(layers, path) {
        var parts = path.split("/");
        var current = layers;

        for (var i = 0; i < parts.length; i++) {
            var name = parts[i];
            var found = null;

            for (var j = 0; j < current.length; j++) {
                if (current[j].name === name) {
                    found = current[j];
                    break;
                }
            }

            // 找不到则返回 null
            if (!found) return null;

            // 到达路径最后一段，返回目标图层
            if (i === parts.length - 1) {
                return found;
            }

            // 不是最后一段，必须是组才能继续深入
            if (found.typename === "LayerSet") {
                current = found.layers;
            } else {
                return null;
            }
        }
        return null;
    }

    // --- 保存修改图层的原始可见性，用于最后还原 ---
    var originalVisibility = [];
    var warnings = [];

    // --- 第 1 步：隐藏指定图层 ---
    for (var i = 0; i < hideList.length; i++) {
        var layer = findLayerByPath(doc.layers, hideList[i]);
        if (layer) {
            originalVisibility.push({ layer: layer, visible: layer.visible });
            layer.visible = false;
        } else {
            warnings.push("WARNING: Hide layer not found: " + hideList[i]);
        }
    }

    // --- 第 2 步：显示指定图层 ---
    for (var i = 0; i < showList.length; i++) {
        var layer = findLayerByPath(doc.layers, showList[i]);
        if (layer) {
            originalVisibility.push({ layer: layer, visible: layer.visible });
            layer.visible = true;
        } else {
            warnings.push("WARNING: Show layer not found: " + showList[i]);
        }
    }

    // --- 第 3 步：导出 ---
    var filePath = doc.fullName.fsName;
    var folder = filePath.replace(/[^\/\\]+$/, "");
    var results = [];

    if (exportList.length === 0) {
        // --- 模式 A：导出完整页面 ---
        var exportPath = folder + "export.png";

        // 记录 flatten 前的历史状态
        var stateBeforeFlatten = doc.activeHistoryState;

        try {
            doc.flatten();

            var pngOptions = new PNGSaveOptions();
            pngOptions.compression = 6;
            pngOptions.interlaced = false;

            var saveFile = new File(exportPath);
            doc.saveAs(saveFile, pngOptions, true, Extension.LOWERCASE);

            results.push(exportPath);
        } catch (flattenErr) {
            warnings.push("WARNING: Full page export failed: " + flattenErr.message);
        }

        // 恢复 flatten 前的状态（恢复图层结构）
        try {
            doc.activeHistoryState = stateBeforeFlatten;
        } catch (restoreErr) {
            // 历史状态恢复失败，无法恢复
        }
    } else {
        // --- 模式 B：导出指定图层 ---
        // 先检查所有路径是否存在
        var notFound = [];

        for (var i = 0; i < exportList.length; i++) {
            var layer = findLayerByPath(doc.layers, exportList[i]);
            if (!layer) {
                notFound.push(exportList[i]);
            }
        }

        // 有路径不存在则报错并中止
        if (notFound.length > 0) {
            // 还原已修改的图层可见性
            for (var i = 0; i < originalVisibility.length; i++) {
                originalVisibility[i].layer.visible = originalVisibility[i].visible;
            }
            // 还原全局对话框设置
            app.displayDialogs = globalDialogMode;
            return "ERROR: Layer not found: " + notFound.join(", ") + "\nPlease run list-layers.ps1 to check the correct layer path.";
        }

        // 逐个导出图层为单独 PNG
        for (var i = 0; i < exportList.length; i++) {
            var layer = findLayerByPath(doc.layers, exportList[i]);
            // 文件名：路径中 "/" 替换为 "_"
            var layerName = exportList[i].replace(/\//g, "_");
            var exportPath = folder + layerName + ".png";

            var tempDoc = null;
            try {
                // 创建临时文档（与原文档同尺寸，透明背景）
                tempDoc = app.documents.add(
                    doc.width, doc.height, doc.resolution,
                    layerName, NewDocumentMode.RGB, DocumentFill.TRANSPARENT
                );

                // 将目标图层复制到临时文档
                app.activeDocument = doc;
                layer.duplicate(tempDoc, ElementPlacement.INSIDE);

                // 切换到临时文档，删除默认空图层
                app.activeDocument = tempDoc;
                if (tempDoc.layers.length > 1) {
                    try {
                        tempDoc.layers[tempDoc.layers.length - 1].remove();
                    } catch (removeErr) {
                        // 删除默认图层失败不影响后续，忽略
                    }
                }

                // 合并所有图层但保持透明度
                if (tempDoc.layers.length > 1) {
                    try {
                        tempDoc.mergeVisibleLayers();
                    } catch (mergeErr) {
                        tempDoc.close(SaveOptions.DONOTSAVECHANGES);
                        app.activeDocument = doc;
                        warnings.push("WARNING: mergeVisibleLayers failed for layer: " + exportList[i] + " (" + mergeErr.message + ")");
                        continue;
                    }
                }

                // 裁剪掉所有透明区域（按透明像素裁切）
                try {
                    tempDoc.trim(TrimType.TRANSPARENT, true, true, true, true);
                } catch (trimErr) {
                    tempDoc.close(SaveOptions.DONOTSAVECHANGES);
                    app.activeDocument = doc;
                    warnings.push("WARNING: trim failed for layer: " + exportList[i] + " (" + trimErr.message + ")");
                    continue;
                }

                // 检查裁剪后是否还有内容
                if (tempDoc.width.as("px") <= 0 || tempDoc.height.as("px") <= 0) {
                    tempDoc.close(SaveOptions.DONOTSAVECHANGES);
                    app.activeDocument = doc;
                    warnings.push("WARNING: Layer has no visible content: " + exportList[i]);
                    continue;
                }

                // 保存为 PNG
                var pngOptions = new PNGSaveOptions();
                pngOptions.compression = 6;
                pngOptions.interlaced = false;

                var saveFile = new File(exportPath);
                tempDoc.saveAs(saveFile, pngOptions, true, Extension.LOWERCASE);

                // 关闭临时文档（不保存）
                tempDoc.close(SaveOptions.DONOTSAVECHANGES);
                app.activeDocument = doc;
                results.push(exportPath);

            } catch (exportErr) {
                // 任何未预期的错误：确保关闭临时文档、切回原文档
                try {
                    if (tempDoc) {
                        tempDoc.close(SaveOptions.DONOTSAVECHANGES);
                    }
                } catch (closeErr) {
                    // 关闭也失败，忽略
                }
                app.activeDocument = doc;
                warnings.push("WARNING: Export failed for layer: " + exportList[i] + " (" + exportErr.message + ")");
                continue;
            }
        }
    }

    // --- 第 4 步：还原所有修改过的图层可见性 ---
    for (var i = 0; i < originalVisibility.length; i++) {
        originalVisibility[i].layer.visible = originalVisibility[i].visible;
    }

    // --- 还原全局对话框设置 ---
    app.displayDialogs = globalDialogMode;

    // 返回导出的文件路径（如有警告一并返回）
    var output = results.join("\n");
    if (warnings.length > 0) {
        output += "\n" + warnings.join("\n");
    }
    return output;
})();
