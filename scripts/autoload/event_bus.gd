extends Node
## 跨场景事件总线（Autoload: EventBus）。
## 只声明 past-tense 类型化信号，不存放任何可变状态；
## 局部数据走场景内连接，勿上总线。

## 场景与移动
signal scene_entered(scene_id: StringName)

## 战斗
signal battle_won(enemy_id: StringName)
signal battle_lost(enemy_id: StringName)
signal enemy_defeated(enemy_id: StringName)
signal player_died(enemy_id: StringName)
signal weapon_broken(item_name: String)

## 成长与经济
signal leveled_up(new_level: int)
signal item_obtained(item_id: StringName, amount: int)
signal welfare_claimed(amount: int)

## 地宫（扩展契约 §4.7）
signal dungeon_cleared(reward_copper: int, reward_gold: int)
