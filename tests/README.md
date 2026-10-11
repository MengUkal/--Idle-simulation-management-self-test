# tests/ 测试运行约定（两种风格，别混用）

| 风格 | 结构 | 运行方式 | 现有套件 |
| --- | --- | --- | --- |
| **场景式**（新默认） | `X.gd` extends Node + 同名 `.tscn` 包装 | `godot --headless --path . res://tests/X.tscn` | board_plus_test / guard_test / offline_test / character_test / paragon_test / settings_test / rebirth_e2e |
| **脚本式**（老风格） | `X.gd` extends SceneTree（`_init` 驱动） | `godot --headless --path . --script res://tests/X.gd` | match3_test / skills_test / sim_test / probe_specials |

**注意**：对场景式测试用 `--script` 会报
`Can't load script ... doesn't inherit from SceneTree or MainLoop`——那不是 bug，是用错了调用方式。

截屏脚本（cap_*.gd）均为场景式，且需**窗口模式**（去掉 --headless）才有画面。
