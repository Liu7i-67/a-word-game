extends Node
## 全局流程编排（Autoload: GameManager）。
## 只做状态编排与流程控制，不自建存档读写（持久化唯一入口是 SaveManager）。

signal state_changed(new_state: State)

enum State { BOOT, TITLE, PLAYING }

var state: State = State.BOOT


func enter_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	state_changed.emit(new_state)
