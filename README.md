# Inochi Creator MCP

起動中の [Inochi Creator](https://github.com/Inochi2D/inochi-creator) を、Cursor などから MCP 経由でライブ操作します。

Inochi Creator には公式のプラグイン／IPC がないため、**v0_8 をソース改変して再ビルド**する必要があります。itch.io / Steam の公式バイナリでは動きません。

## 構成

```
Cursor  --stdio MCP-->  このリポジトリの Node サーバー
                              |
                              | HTTP POST http://127.0.0.1:17320/rpc
                              v
                    パッチ済み Inochi Creator（UI スレッドで inc* API を実行）
```

待ち受けは `127.0.0.1` のみです。任意で `INOCHI_MCP_TOKEN` を Creator と MCP の両方に設定すると、Bearer / `X-Inochi-Token` 照合が入ります。

## 必要環境

- Node.js 18 以降
- Inochi Creator `v0_8` のソースと、公式 README どおりのビルド環境
  - Windows: Visual Studio 2022（C++）、CMake、LDC または DMD

## 1. ブリッジを Creator に入れる

```powershell
git clone --branch v0_8 --recursive https://github.com/Inochi2D/inochi-creator.git
# 依存関係は公式 README に従って準備する

.\scripts\apply-bridge.ps1 -CreatorRoot "C:\path\to\inochi-creator"
```

スクリプトは次を行います。

- `creator-bridge/mcp/*.d` を `source/creator/mcp/` へコピー
- `source/app.d` に `incMcpInit()` / `incMcpPoll()` を挿入（再実行しても二重には入りません）

その後、Inochi Creator 側でいつもどおり `dub` ビルドして起動します。

```powershell
curl http://127.0.0.1:17320/health
```

`{"ok":true,...}` が返ればブリッジは生きています。

ポートを変える場合は、Creator 起動前に `INOCHI_MCP_PORT`（デフォルト `17320`）を設定し、MCP 側にも同じ値を渡してください。

## 2. MCP サーバーをビルドする

```powershell
cd C:\Users\masam\Documents\inochi-creator-mcp
npm install
npm run build
```

開発中は `npm run dev`（`tsx src/index.ts`）でも起動できます。

## 3. Cursor に接続する

Cursor の MCP 設定例:

```json
{
  "mcpServers": {
    "inochi-creator": {
      "command": "node",
      "args": ["C:/Users/masam/Documents/inochi-creator-mcp/dist/index.js"],
      "env": {
        "INOCHI_MCP_PORT": "17320"
      }
    }
  }
}
```

ログは stdout を汚さないよう stderr に出します。Creator が起動していないと、各ツールは「パッチ済み Inochi Creator を起動してください」と返します。

## ツール

接続できないときは、パッチ済み Creator が `127.0.0.1:17320` で待っているか確認してください。

### 状態・プロジェクト

- `creator_ping` / `creator_get_status`
- `creator_set_edit_mode`（`model` / `vertex` / `anim` / `test`）
- `creator_new_project` / `creator_open_project` / `creator_save_project`
- `creator_export_inp`（エクスポート UI は開かず、デフォルト設定で `.inp` を書く）

### ノード・パラメータ

- `creator_list_nodes` / `creator_get_node` / `creator_select_node` / `creator_focus_camera`
- `creator_rename_node` / `creator_set_node_enabled` / `creator_set_node_transform`
- `creator_create_node`（`Node` / `Composite` / `MeshGroup` / `SimplePhysics` / `Camera`）
- `creator_duplicate_node` / `creator_delete_node` / `creator_reparent_node`
- `creator_list_parameters` / `creator_set_parameter` / `creator_arm_parameter` / `creator_disarm_parameter`
- `creator_add_parameter` / `creator_remove_parameter`
- `creator_undo` / `creator_redo`

Part はテクスチャが必要なので、`creator_import_images` で PNG/TGA/JPEG から作ります。

### 取り込み

`creator_import_psd` / `creator_import_kra` / `creator_import_inp` / `creator_import_folder` は内部で新規プロジェクトを作るため、**今開いているプロジェクトを置き換えます**。

`creator_import_images` だけは現在のプロジェクトを維持し、選択中（または指定した親）の下に Part を足します。

### アニメ・撮影

- `creator_list_animations` / `creator_set_animation`
- `creator_play_animation` / `creator_pause_animation` / `creator_stop_animation` / `creator_seek_animation`
- `creator_add_keyframe` / `creator_remove_keyframe`
- `creator_capture_viewport` — ビューポート PNG。既定では長辺 1024 に縮小。`full: true` で原寸。MCP の画像として返します。

対象外: メッシュ頂点編集、パラメータ binding の詳細、トラッキング、動画書き出し。

## 手動でブリッジを入れる場合

`apply-bridge.ps1` を使わないときは、次を `source/app.d` に足します。

1. `import creator.mcp;`
2. 初期化のあと（`incInitAtlassing();` の近く）に `incMcpInit();`
3. `incUpdate()` と `incUpdateNoEv()` の `inUpdate();` の直後に `incMcpPoll();`

コマンド実行は必ず UI スレッド（`incMcpPoll`）側です。ソケット受信は別スレッドです。

## プロトコル

```http
POST /rpc HTTP/1.1
Host: 127.0.0.1:17320
Content-Type: application/json

{"method":"list_nodes","params":{"detail":false}}
```

```json
{"ok":true,"result":{...}}
```

失敗時は `{"ok":false,"error":"..."}` です。
