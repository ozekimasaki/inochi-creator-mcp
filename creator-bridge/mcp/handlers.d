module creator.mcp.handlers;

import creator;
import creator.actions;
import creator.core.actionstack;
import creator.ext;
import creator.io;
import creator.io.inpexport;
import creator.io.imageexport;
import creator.viewport;
import inochi2d;
import std.base64 : Base64;
import std.conv : to;
import std.exception : enforce;
import std.file : exists, read, tempDir, mkdirRecurse, copy, isDir;
import std.json;
import std.path : buildPath, setExtension, dirName;
import std.string : toLower;

JSONValue incMcpHandle(string method, JSONValue params) {
    if (params.type != JSONType.object) {
        params = parseJSON("{}");
    }

    switch (method) {
        case "ping": return handlePing();
        case "get_status": return handleGetStatus();
        case "set_edit_mode": return handleSetEditMode(params);
        case "new_project": return handleNewProject();
        case "open_project": return handleOpenProject(params);
        case "save_project": return handleSaveProject(params);
        case "export_inp": return handleExportInp(params);
        case "list_nodes": return handleListNodes(params);
        case "get_node": return handleGetNode(params);
        case "select_node": return handleSelectNode(params);
        case "focus_camera": return handleFocusCamera(params);
        case "rename_node": return handleRenameNode(params);
        case "set_node_enabled": return handleSetNodeEnabled(params);
        case "set_node_transform": return handleSetNodeTransform(params);
        case "create_node": return handleCreateNode(params);
        case "duplicate_node": return handleDuplicateNode(params);
        case "delete_node": return handleDeleteNode(params);
        case "reparent_node": return handleReparentNode(params);
        case "list_parameters": return handleListParameters();
        case "set_parameter": return handleSetParameter(params);
        case "arm_parameter": return handleArmParameter(params);
        case "disarm_parameter": return handleDisarmParameter();
        case "add_parameter": return handleAddParameter(params);
        case "remove_parameter": return handleRemoveParameter(params);
        case "undo": return handleUndo();
        case "redo": return handleRedo();
        case "import_psd": return handleImportPsd(params);
        case "import_kra": return handleImportKra(params);
        case "import_inp": return handleImportInp(params);
        case "import_folder": return handleImportFolder(params);
        case "import_images": return handleImportImages(params);
        case "list_animations": return handleListAnimations();
        case "set_animation": return handleSetAnimation(params);
        case "play_animation": return handlePlayAnimation(params);
        case "pause_animation": return handlePauseAnimation();
        case "stop_animation": return handleStopAnimation(params);
        case "seek_animation": return handleSeekAnimation(params);
        case "add_keyframe": return handleAddKeyframe(params);
        case "remove_keyframe": return handleRemoveKeyframe(params);
        case "capture_viewport": return handleCaptureViewport(params);
        default: throw new Exception("Unknown method: " ~ method);
    }
}

private bool hasKey(JSONValue obj, string key) {
    return obj.type == JSONType.object && (key in obj.object) !is null;
}

private string requireStr(JSONValue obj, string key) {
    enforce(hasKey(obj, key), key ~ " is required");
    return obj[key].str;
}

private uint parseUuid(JSONValue value) {
    switch (value.type) {
        case JSONType.string: return to!uint(value.str);
        case JSONType.integer: return cast(uint)value.integer;
        case JSONType.uinteger: return cast(uint)value.uinteger;
        default: throw new Exception("uuid must be a number or string");
    }
}

private double jsonNum(JSONValue value) {
    switch (value.type) {
        case JSONType.integer: return cast(double)value.integer;
        case JSONType.uinteger: return cast(double)value.uinteger;
        case JSONType.float_: return value.floating;
        case JSONType.string: return to!double(value.str);
        default: throw new Exception("expected a number");
    }
}

private bool jsonBool(JSONValue value, bool fallback = false) {
    switch (value.type) {
        case JSONType.true_: return true;
        case JSONType.false_: return false;
        case JSONType.integer: return value.integer != 0;
        case JSONType.string:
            auto s = value.str.toLower;
            if (s == "true" || s == "1") return true;
            if (s == "false" || s == "0") return false;
            return fallback;
        default: return fallback;
    }
}

private JSONValue okTrue() {
    JSONValue[string] aa;
    aa["ok"] = JSONValue(true);
    return JSONValue(aa);
}

private Node requireNode(JSONValue params, string key = "uuid") {
    enforce(hasKey(params, key), key ~ " is required");
    auto uuid = parseUuid(params[key]);
    auto node = incActivePuppet().find!Node(uuid);
    enforce(node !is null, "Node not found: " ~ to!string(uuid));
    return node;
}

private Parameter requireParam(JSONValue params) {
    auto puppet = incActivePuppet();

    Parameter search(Parameter[] list, bool byUuid, uint uuid, string name) {
        foreach (p; list) {
            if (auto group = cast(ExParameterGroup)p) {
                if (auto found = search(group.children, byUuid, uuid, name)) return found;
            } else {
                if (byUuid && p.uuid == uuid) return p;
                if (!byUuid && p.name == name) return p;
            }
        }
        return null;
    }

    if (hasKey(params, "uuid")) {
        auto uuid = parseUuid(params["uuid"]);
        auto found = search(puppet.parameters, true, uuid, "");
        enforce(found !is null, "Parameter not found: " ~ to!string(uuid));
        return found;
    }
    if (hasKey(params, "name")) {
        auto name = params["name"].str;
        auto found = search(puppet.parameters, false, 0, name);
        enforce(found !is null, "Parameter not found: " ~ name);
        return found;
    }
    throw new Exception("uuid or name is required");
}

private string editModeName(EditMode mode) {
    switch (mode) {
        case EditMode.ModelEdit: return "model";
        case EditMode.VertexEdit: return "vertex";
        case EditMode.AnimEdit: return "anim";
        case EditMode.ModelTest: return "test";
        default: return "unknown";
    }
}

private EditMode parseEditMode(string name) {
    switch (name.toLower) {
        case "model": return EditMode.ModelEdit;
        case "vertex": return EditMode.VertexEdit;
        case "anim": return EditMode.AnimEdit;
        case "test": return EditMode.ModelTest;
        default: throw new Exception("Unknown edit mode: " ~ name);
    }
}

private JSONValue nodeToJson(Node node, bool recursive, bool detail) {
    JSONValue[string] aa;
    aa["uuid"] = JSONValue(cast(long)node.uuid);
    aa["name"] = JSONValue(node.name);
    aa["type"] = JSONValue(node.typeId());
    aa["enabled"] = JSONValue(node.enabled);
    aa["zsort"] = JSONValue(cast(double)node.zSort);

    if (detail) {
        auto t = node.localTransform;
        aa["translation"] = JSONValue([
            JSONValue(cast(double)t.translation.x),
            JSONValue(cast(double)t.translation.y),
            JSONValue(cast(double)t.translation.z),
        ]);
        aa["rotation"] = JSONValue([
            JSONValue(cast(double)t.rotation.x),
            JSONValue(cast(double)t.rotation.y),
            JSONValue(cast(double)t.rotation.z),
        ]);
        aa["scale"] = JSONValue([
            JSONValue(cast(double)t.scale.x),
            JSONValue(cast(double)t.scale.y),
        ]);
        if (node.parent) aa["parent_uuid"] = JSONValue(cast(long)node.parent.uuid);
        else aa["parent_uuid"] = JSONValue();
        if (auto part = cast(Part)node) {
            aa["opacity"] = JSONValue(cast(double)part.opacity);
        }
    }

    if (recursive) {
        JSONValue[] children;
        foreach (child; node.children) {
            children ~= nodeToJson(child, true, detail);
        }
        aa["children"] = JSONValue(children);
    } else {
        JSONValue[] children;
        foreach (child; node.children) {
            JSONValue[string] ch;
            ch["uuid"] = JSONValue(cast(long)child.uuid);
            ch["name"] = JSONValue(child.name);
            ch["type"] = JSONValue(child.typeId());
            children ~= JSONValue(ch);
        }
        aa["children"] = JSONValue(children);
    }

    return JSONValue(aa);
}

private JSONValue paramToJson(Parameter param) {
    JSONValue[string] aa;
    aa["uuid"] = JSONValue(cast(long)param.uuid);
    aa["name"] = JSONValue(param.name);

    if (auto group = cast(ExParameterGroup)param) {
        aa["is_group"] = JSONValue(true);
        JSONValue[] children;
        foreach (child; group.children) children ~= paramToJson(child);
        aa["children"] = JSONValue(children);
        return JSONValue(aa);
    }

    aa["is_group"] = JSONValue(false);
    aa["is_vec2"] = JSONValue(param.isVec2);
    aa["value"] = JSONValue([
        JSONValue(cast(double)param.value.x),
        JSONValue(cast(double)param.value.y),
    ]);
    aa["min"] = JSONValue([
        JSONValue(cast(double)param.min.x),
        JSONValue(cast(double)param.min.y),
    ]);
    aa["max"] = JSONValue([
        JSONValue(cast(double)param.max.x),
        JSONValue(cast(double)param.max.y),
    ]);
    return JSONValue(aa);
}

private JSONValue handlePing() {
    JSONValue[string] aa;
    aa["bridge"] = JSONValue("inochi-creator-mcp");
    aa["version"] = JSONValue("0.1.0");
    return JSONValue(aa);
}

private JSONValue handleGetStatus() {
    JSONValue[string] aa;
    aa["project_path"] = JSONValue(incProjectPath());
    aa["edit_mode"] = JSONValue(editModeName(incEditMode()));
    aa["can_undo"] = JSONValue(incActionCanUndo());
    aa["can_redo"] = JSONValue(incActionCanRedo());

    JSONValue[] selected;
    foreach (node; incSelectedNodes()) {
        if (node is null) continue;
        JSONValue[string] sn;
        sn["uuid"] = JSONValue(cast(long)node.uuid);
        sn["name"] = JSONValue(node.name);
        sn["type"] = JSONValue(node.typeId());
        selected ~= JSONValue(sn);
    }
    aa["selected"] = JSONValue(selected);

    if (auto armed = incArmedParameter()) {
        JSONValue[string] ap;
        ap["uuid"] = JSONValue(cast(long)armed.uuid);
        ap["name"] = JSONValue(armed.name);
        aa["armed_parameter"] = JSONValue(ap);
    } else {
        aa["armed_parameter"] = JSONValue();
    }

    return JSONValue(aa);
}

private JSONValue handleSetEditMode(JSONValue params) {
    auto mode = parseEditMode(requireStr(params, "mode"));
    incSetEditMode(mode);
    JSONValue[string] aa;
    aa["edit_mode"] = JSONValue(editModeName(incEditMode()));
    return JSONValue(aa);
}

private JSONValue handleNewProject() {
    incNewProject();
    return okTrue();
}

private JSONValue handleOpenProject(JSONValue params) {
    auto path = requireStr(params, "path");
    enforce(exists(path), "File not found: " ~ path);
    enforce(incOpenProject(path, ""), "Failed to open project: " ~ path);
    JSONValue[string] aa;
    aa["project_path"] = JSONValue(incProjectPath());
    return JSONValue(aa);
}

private JSONValue handleSaveProject(JSONValue params) {
    string path = hasKey(params, "path") ? params["path"].str : incProjectPath();
    enforce(path.length > 0, "path is required because the project has not been saved yet");
    incSaveProject(path);
    JSONValue[string] aa;
    aa["project_path"] = JSONValue(incProjectPath());
    return JSONValue(aa);
}

private JSONValue handleExportInp(JSONValue params) {
    auto path = setExtension(requireStr(params, "path"), ".inp");
    auto dir = dirName(path);
    if (dir.length && !exists(dir)) mkdirRecurse(dir);
    incINPExport(incActivePuppet(), IncINPExportSettings.init, path);
    JSONValue[string] aa;
    aa["path"] = JSONValue(path);
    return JSONValue(aa);
}

private JSONValue handleListNodes(JSONValue params) {
    bool detail = hasKey(params, "detail") ? jsonBool(params["detail"]) : false;
    JSONValue[string] aa;
    aa["root"] = nodeToJson(incActivePuppet().root, true, detail);
    return JSONValue(aa);
}

private JSONValue handleGetNode(JSONValue params) {
    return nodeToJson(requireNode(params), false, true);
}

private JSONValue handleSelectNode(JSONValue params) {
    if (!hasKey(params, "uuid")) {
        incSelectNode(null);
        return okTrue();
    }
    auto node = requireNode(params);
    incSelectNode(node);
    return nodeToJson(node, false, false);
}

private JSONValue handleFocusCamera(JSONValue params) {
    auto node = requireNode(params);
    incFocusCamera(node);
    return okTrue();
}

private JSONValue handleRenameNode(JSONValue params) {
    auto node = requireNode(params);
    auto name = requireStr(params, "name");
    auto old = node.name;
    node.name = name;
    incActionPush(new NodeValueChangeAction!(Node, string)("name", node, old, name, &node.name));
    JSONValue[string] aa;
    aa["uuid"] = JSONValue(cast(long)node.uuid);
    aa["name"] = JSONValue(node.name);
    return JSONValue(aa);
}

private JSONValue handleSetNodeEnabled(JSONValue params) {
    auto node = requireNode(params);
    enforce(hasKey(params, "enabled"), "enabled is required");
    bool enabled = jsonBool(params["enabled"]);
    auto action = new NodeActiveAction();
    action.self = node;
    action.newState = enabled;
    node.enabled = enabled;
    incActionPush(action);
    JSONValue[string] aa;
    aa["uuid"] = JSONValue(cast(long)node.uuid);
    aa["enabled"] = JSONValue(node.enabled);
    return JSONValue(aa);
}

private JSONValue handleSetNodeTransform(JSONValue params) {
    auto node = requireNode(params);
    incActionPushGroup();

    if (hasKey(params, "translation")) {
        auto arr = params["translation"].array;
        enforce(arr.length == 3, "translation must be [x, y, z]");
        auto old = node.localTransform.translation;
        node.localTransform.translation = vec3(jsonNum(arr[0]), jsonNum(arr[1]), jsonNum(arr[2]));
        incActionPush(new NodeValueChangeAction!(Node, vec3)(
            "translation", node, old, node.localTransform.translation, &node.localTransform.translation
        ));
    }
    if (hasKey(params, "rotation")) {
        auto arr = params["rotation"].array;
        enforce(arr.length == 3, "rotation must be [x, y, z]");
        auto old = node.localTransform.rotation;
        node.localTransform.rotation = vec3(jsonNum(arr[0]), jsonNum(arr[1]), jsonNum(arr[2]));
        incActionPush(new NodeValueChangeAction!(Node, vec3)(
            "rotation", node, old, node.localTransform.rotation, &node.localTransform.rotation
        ));
    }
    if (hasKey(params, "scale")) {
        auto arr = params["scale"].array;
        enforce(arr.length == 2, "scale must be [x, y]");
        auto old = node.localTransform.scale;
        node.localTransform.scale = vec2(jsonNum(arr[0]), jsonNum(arr[1]));
        incActionPush(new NodeValueChangeAction!(Node, vec2)(
            "scale", node, old, node.localTransform.scale, &node.localTransform.scale
        ));
    }
    if (hasKey(params, "zsort")) {
        node.zSort = jsonNum(params["zsort"]);
    }

    incActionPopGroup();
    node.transformChanged();
    return nodeToJson(node, false, true);
}

private JSONValue handleCreateNode(JSONValue params) {
    auto type = requireStr(params, "type");
    Node parent = incActivePuppet().root;
    if (hasKey(params, "parent_uuid")) parent = requireNode(params, "parent_uuid");

    Node child;
    switch (type) {
        case "Node": child = new Node(cast(Node)null); break;
        case "Composite": child = new Composite(cast(Node)null); break;
        case "MeshGroup": child = new MeshGroup(cast(Node)null); break;
        case "SimplePhysics": child = new SimplePhysics(cast(Node)null); break;
        case "Camera": child = new ExCamera(cast(Node)null); break;
        default: throw new Exception("Unsupported node type: " ~ type ~ ". Use import_images to create Parts.");
    }

    string name = hasKey(params, "name") ? params["name"].str : null;
    incAddChildWithHistory(child, parent, name);
    return nodeToJson(child, false, true);
}

private JSONValue handleDuplicateNode(JSONValue params) {
    auto src = requireNode(params);
    auto copy = recursiveDuplicate(src);
    enforce(copy !is null, "Cannot duplicate this node type");
    auto destParent = src.parent ? src.parent : incActivePuppet().root;
    incActionPush(new NodeMoveAction([copy], destParent));
    incActivePuppet().rescanNodes();
    return nodeToJson(copy, false, true);
}

private JSONValue handleDeleteNode(JSONValue params) {
    auto node = requireNode(params);
    enforce(node !is incActivePuppet().root, "Cannot delete the root node");
    if (incNodeInSelection(node)) incSelectNode(null);
    incDeleteChildWithHistory(node);
    JSONValue[string] aa;
    aa["deleted"] = JSONValue(true);
    return JSONValue(aa);
}

private JSONValue handleReparentNode(JSONValue params) {
    auto node = requireNode(params);
    auto parent = requireNode(params, "parent_uuid");
    size_t index = hasKey(params, "index") ? cast(size_t)jsonNum(params["index"]) : 0;
    incMoveChildWithHistory(node, parent, index);
    return nodeToJson(node, false, true);
}

private JSONValue handleListParameters() {
    JSONValue[] items;
    foreach (param; incActivePuppet().parameters) items ~= paramToJson(param);
    JSONValue[string] aa;
    aa["parameters"] = JSONValue(items);
    return JSONValue(aa);
}

private JSONValue handleSetParameter(JSONValue params) {
    auto param = requireParam(params);
    enforce(hasKey(params, "x"), "x is required");
    float x = jsonNum(params["x"]);
    float y = param.isVec2 && hasKey(params, "y") ? jsonNum(params["y"]) : param.value.y;
    if (!param.isVec2) y = 0;
    param.value = vec2(x, y);
    return paramToJson(param);
}

private JSONValue handleArmParameter(JSONValue params) {
    auto param = requireParam(params);
    size_t idx = 0;
    bool found;
    foreach (i, p; incActivePuppet().parameters) {
        if (p is param) {
            idx = i;
            found = true;
            break;
        }
    }
    enforce(found, "Can only arm a top-level parameter (not a group child)");
    incArmParameter(idx, param);
    return paramToJson(param);
}

private JSONValue handleDisarmParameter() {
    incDisarmParameter();
    return okTrue();
}

private JSONValue handleAddParameter(JSONValue params) {
    auto name = requireStr(params, "name");
    bool isVec2 = hasKey(params, "is_vec2") ? jsonBool(params["is_vec2"]) : false;
    auto param = new ExParameter(name, isVec2);
    incActivePuppet().parameters ~= param;
    incActionPush(new ParameterAddAction(param, &incActivePuppet().parameters));
    return paramToJson(param);
}

private JSONValue handleRemoveParameter(JSONValue params) {
    auto param = requireParam(params);
    incActivePuppet().removeParameter(param);
    incActionPush(new ParameterRemoveAction(param, &incActivePuppet().parameters));
    JSONValue[string] aa;
    aa["deleted"] = JSONValue(true);
    return JSONValue(aa);
}

private JSONValue handleUndo() {
    enforce(incActionCanUndo(), "Nothing to undo");
    incActionUndo();
    JSONValue[string] aa;
    aa["can_undo"] = JSONValue(incActionCanUndo());
    aa["can_redo"] = JSONValue(incActionCanRedo());
    return JSONValue(aa);
}

private JSONValue handleRedo() {
    enforce(incActionCanRedo(), "Nothing to redo");
    incActionRedo();
    JSONValue[string] aa;
    aa["can_undo"] = JSONValue(incActionCanUndo());
    aa["can_redo"] = JSONValue(incActionCanRedo());
    return JSONValue(aa);
}

private JSONValue handleImportPsd(JSONValue params) {
    auto path = requireStr(params, "path");
    enforce(exists(path), "File not found: " ~ path);
    bool keep = hasKey(params, "keep_structure") ? jsonBool(params["keep_structure"]) : false;
    incImportPSD(path, IncPSDImportSettings(keep));
    return okTrue();
}

private JSONValue handleImportKra(JSONValue params) {
    auto path = requireStr(params, "path");
    enforce(exists(path), "File not found: " ~ path);
    bool keep = hasKey(params, "keep_structure") ? jsonBool(params["keep_structure"]) : false;
    incImportKRA(path, IncKRAImportSettings(keep));
    return okTrue();
}

private JSONValue handleImportInp(JSONValue params) {
    auto path = requireStr(params, "path");
    enforce(exists(path), "File not found: " ~ path);
    incImportINP(path);
    return okTrue();
}

private JSONValue handleImportFolder(JSONValue params) {
    auto path = requireStr(params, "path");
    enforce(exists(path) && isDir(path), "Folder not found: " ~ path);
    incImportFolder(path);
    return okTrue();
}

private JSONValue handleImportImages(JSONValue params) {
    enforce(hasKey(params, "paths"), "paths is required");
    if (hasKey(params, "parent_uuid")) {
        incSelectNode(requireNode(params, "parent_uuid"));
    }
    string[] paths;
    foreach (item; params["paths"].array) {
        enforce(exists(item.str), "File not found: " ~ item.str);
        paths ~= item.str;
    }
    incCreatePartsFromFiles(paths);
    return okTrue();
}

private JSONValue animationStateJson() {
    JSONValue[string] aa;
    aa["names"] = JSONValue(incAnimationKeysGet().mapJsonStrings());
    auto cur = incAnimationGet();
    if (cur !is null && cur.isValid) {
        aa["current"] = JSONValue(cur.name);
        aa["frame"] = JSONValue(cur.frame);
        aa["frames"] = JSONValue(cur.frames);
        aa["playing"] = JSONValue(cur.playing);
        aa["paused"] = JSONValue(cur.paused);
        aa["looping"] = JSONValue(cur.looping);
    } else {
        aa["current"] = JSONValue();
    }
    return JSONValue(aa);
}

private JSONValue[] mapJsonStrings(string[] items) {
    JSONValue[] out_;
    foreach (item; items) out_ ~= JSONValue(item);
    return out_;
}

private JSONValue handleListAnimations() {
    return animationStateJson();
}

private JSONValue handleSetAnimation(JSONValue params) {
    auto name = requireStr(params, "name");
    incAnimationChange(name);
    enforce(incAnimationGet() !is null, "Animation not found: " ~ name);
    return animationStateJson();
}

private JSONValue handlePlayAnimation(JSONValue params) {
    if (hasKey(params, "name")) {
        incAnimationChange(params["name"].str);
    }
    auto cur = incAnimationGet();
    enforce(cur !is null && cur.isValid, "No animation selected");
    bool loop = hasKey(params, "loop") ? jsonBool(params["loop"]) : false;
    cur.play(loop);
    return animationStateJson();
}

private JSONValue handlePauseAnimation() {
    auto cur = incAnimationGet();
    enforce(cur !is null && cur.isValid, "No animation selected");
    cur.pause();
    return animationStateJson();
}

private JSONValue handleStopAnimation(JSONValue params) {
    bool immediate = hasKey(params, "immediate") ? jsonBool(params["immediate"], true) : true;
    incAnimationPlayerGet().stopAll(immediate);
    return animationStateJson();
}

private JSONValue handleSeekAnimation(JSONValue params) {
    enforce(hasKey(params, "frame"), "frame is required");
    auto cur = incAnimationGet();
    enforce(cur !is null && cur.isValid, "No animation selected");
    cur.seek(cast(int)jsonNum(params["frame"]));
    cur.render();
    return animationStateJson();
}

private JSONValue handleAddKeyframe(JSONValue params) {
    enforce(incAnimationGet() !is null, "No animation selected");
    auto param = requireParam(params);
    int axis = hasKey(params, "axis") ? cast(int)jsonNum(params["axis"]) : 0;
    float value;
    if (hasKey(params, "value")) value = jsonNum(params["value"]);
    else value = axis == 1 ? param.value.y : param.value.x;
    incAnimationKeyframeAdd(param, axis, value);
    return animationStateJson();
}

private JSONValue handleRemoveKeyframe(JSONValue params) {
    enforce(incAnimationGet() !is null, "No animation selected");
    auto param = requireParam(params);
    int axis = hasKey(params, "axis") ? cast(int)jsonNum(params["axis"]) : 0;
    auto removed = incAnimationKeyframeRemove(param, axis);
    JSONValue[string] aa;
    aa["removed"] = JSONValue(removed);
    return JSONValue(aa);
}

private ubyte[] downscalePixels(ubyte[] src, int sw, int sh, int dw, int dh, int channels) {
    auto dst = new ubyte[dw * dh * channels];
    foreach (y; 0 .. dh) {
        int sy = (y * sh) / dh;
        foreach (x; 0 .. dw) {
            int sx = (x * sw) / dw;
            auto si = cast(size_t)(sy * sw + sx) * channels;
            auto di = cast(size_t)(y * dw + x) * channels;
            dst[di .. di + channels] = src[si .. si + channels];
        }
    }
    return dst;
}

private JSONValue handleCaptureViewport(JSONValue params) {
    if (incShouldMirrorViewport) {
        auto camera = inGetCamera();
        camera.scale.x *= -1;
        incViewportDraw();
        camera.scale.x *= -1;
    } else {
        incViewportDraw();
    }

    int width, height;
    inGetViewport(width, height);
    enforce(width > 0 && height > 0, "Viewport has not been rendered yet");

    auto data = new ubyte[inViewportDataLength()];
    inDumpViewport(data);
    int channels = (height > 0 && width > 0) ? cast(int)(data.length / (width * height)) : 4;
    enforce(channels >= 3 && channels <= 4, "Unexpected viewport pixel format");

    bool full = hasKey(params, "full") ? jsonBool(params["full"]) : false;
    int outW = width;
    int outH = height;
    ubyte[] pixels = data;
    if (!full) {
        enum maxSide = 1024;
        int longSide = width > height ? width : height;
        if (longSide > maxSide) {
            double scale = cast(double)maxSide / cast(double)longSide;
            outW = cast(int)(width * scale);
            outH = cast(int)(height * scale);
            if (outW < 1) outW = 1;
            if (outH < 1) outH = 1;
            pixels = downscalePixels(data, width, height, outW, outH, channels);
        }
    }

    string tmp = buildPath(tempDir(), "inochi-mcp-viewport.png");
    incExportImage(tmp, pixels, outW, outH, channels);
    auto png = cast(ubyte[])read(tmp);
    string b64 = Base64.encode(png).idup;

    string saved;
    if (hasKey(params, "path")) {
        saved = params["path"].str;
        auto dir = dirName(saved);
        if (dir.length && !exists(dir)) mkdirRecurse(dir);
        copy(tmp, saved);
    }

    JSONValue[string] aa;
    aa["width"] = JSONValue(outW);
    aa["height"] = JSONValue(outH);
    aa["source_width"] = JSONValue(width);
    aa["source_height"] = JSONValue(height);
    aa["png_base64"] = JSONValue(b64);
    if (saved.length) aa["path"] = JSONValue(saved);
    return JSONValue(aa);
}
