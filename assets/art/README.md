# 美术资产索引（assets/art/）

> 全部产物由仓库内管线生成，**不要手改 PNG**——改生成脚本重跑即可全套一致更新。
> 生成后必须跑一次 `godot --headless --path <项目> --import` 注册 `.import`，否则运行时加载不到。

## 目录结构与产物

| 目录 | 内容 | 生成方式 |
| --- | --- | --- |
| `tiles/` | 棋子 25 张：`tile_{0-5}_{fire\|water\|wind\|earth\|light\|dark}_{plain\|lh\|lv\|bomb}.png` + `tile_bird.png` | `python tools/artgen.py`（`--size` 可改尺寸） |
| `ui/` | `ui_gil.png`（吉尔）、`ui_essence.png`（精华）、`target_huo/feng/sheng.png`（三标的） | 同上（artgen 一并产出） |
| `ui/preview.png`、`ui/_targets.png` | 人工预览拼图，不进游戏 | 同上 |
| `monsters/` | 14 只怪物头像 `monsters/<slug>.png`（128×128 透明底）+ `_roster.png` 质检拼图 | `python tools/gen_asset.py --monster <中文名>`（需 ComfyUI 运行中） |
| `bg/` | `world_tree.png`（768×512 树绘）、`bg_floor1/2.png`（640×360×3 = 1920×1080 背景） | `python tools/gen_asset.py --scene "<英文描述>" --out <名> --w .. --h .. --scale ..` |

## 命名规范

- 元素索引与 `data/balance.gd` 对齐：`0火 1水 2風 3土 4光 5闇`。
- 怪物 slug 以 `tools/gen_asset.py` 的 `MONSTERS` 表为准，与 `battle.gd` 的 `MONSTER_SLUG` 一一对应。
- 新增素材一律走管线脚本 + 在脚本内的登记表加一行；`_` 开头的 PNG 是预览/QA 拼图。

## 场景接入现状

| 场景 | 背景接入 | 图标接入 | 备注 |
| --- | --- | --- | --- |
| title | ✅ world_tree 全屏（+呼吸动效） | — | `scenes/title/`，启动场景 |
| main | ✅ 按 floor_index 切换 | ✅ 吉尔/精华 | MoneyRow/EssenceRow |
| battle | ✅ 按 floor_index 切换 | ✅ 棋子 25 张 | 棋子按钮用 StyleBoxEmpty 豁免全局主题 |
| market | ✅ 固定 bg_floor1（支行设定在一层） | ✅ 三标的图标 | **market.gd 是代码构建 UI**——改市场视觉要改代码，只改 tscn 会被运行时重建覆盖 |

## 风格基线

- 图标：扁平圆角块 + 深色描边 + 白色符号；配色对齐 `balance.gd` 的 `ELEMENT_COLORS`。
- 怪物/场景：日式奇幻像素风（DreamShaper 8 + PixelArtRedmond LoRA → 降采样/量化），提示词模板见 `gen_asset.py`。
- UI 主题：`theme/fantasy.tres`（深紫底金边），全局生效于 `project.godot [gui]`；重建工具 `tests/_make_theme.gd`。
