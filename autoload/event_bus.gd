extends Node
## 全局信号总线：UI 与逻辑解耦，跨模块通知一律走这里，模块之间不直接互相引用。

signal money_changed(total: float)          # 吉尔总数变化（每帧）
signal income_changed(per_sec: float)       # 挂机收入变化
signal level_changed(new_level: int)        # 等级提升
signal money_not_enough(needed: float)      # 献金失败（钱不够）
signal floor_changed(new_floor: int)        # 所在层变化
signal floor_unlocked(req_level: int)       # 新层解锁（等级达标那一刻）
signal save_completed()                     # 一次存档写盘完成
signal essence_changed(total: int)          # 元素精华变化
signal line_changed(kind: String, level: int)  # 训练线升级（atk/bounty/income）
