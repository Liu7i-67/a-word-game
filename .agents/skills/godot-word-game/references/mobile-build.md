何时读本文件：做 Android 竖屏触屏适配（触摸输入、安全区/notch、省电、Mobile 渲染器）或打包 Android 包（签名、headless 导出、版本号）时阅读本项目专属规则。

# 移动端与 Android 打包（godot-word-game）

## 1. 触屏与竖屏

### NEVER (input & display)
- **NEVER use mouse events for touch interaction** — Relying on `InputEventMouseButton` on mobile is unreliable. Always use `InputEventScreenTouch` and `InputEventScreenDrag` for high-fidelity multi-touch support.
- **NEVER ignore display safe areas (notches/cutouts)** — UI placed behind a camera notch is unusable. Query `DisplayServer.get_display_safe_area()` and offset critical UI accordingly.
- **NEVER assume fixed orientation** — Locking a landscape game without handling the `size_changed` signal leads to broken layouts on foldable devices or tablet orientation shifts.
- **NEVER assume Android permissions are automatically granted** — You MUST explicitly call `OS.request_permission()` and verify with `OS.get_granted_permissions()`.
- **NEVER call handheld vibration without permission** — On Android, vibration calls are ignored unless the `VIBRATE` permission is enabled in the export preset.

### 触摸输入（最短可用示例）
```gdscript
func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed:
            on_touch_start(event.position)
        else:
            on_touch_end(event.position)
    elif event is InputEventScreenDrag:
        on_touch_drag(event.position, event.relative)
```

### 安全区 / notch 适配
```gdscript
func apply_safe_area() -> void:
    var safe_area := DisplayServer.get_display_safe_area()
    $UI.offset_top = safe_area.position.y
    $UI.offset_left = safe_area.position.x
```

### Android 返回键
- Android Back: disable `quit_on_go_back`, handle `NOTIFICATION_WM_GO_BACK_REQUEST` in a global manager — pop the UI stack first, quit only when the stack is empty.

### 震动反馈
- Haptics: `Input.vibrate_handheld(30, 0.2)` 轻震 / `Input.vibrate_handheld(400, 1.0)` 重震；export preset 必须开启 `VIBRATE` 权限。

## 2. 移动端渲染与性能

### NEVER (battery & rendering)
- **NEVER maintain high framerate when backgrounded** — Keeping an app at 60 FPS in the background drains battery. Use `NOTIFICATION_APPLICATION_PAUSED` to drop `Engine.max_fps` to 1.
- **NEVER use the Forward+ renderer for mobile** — Most mobile GPUs are not optimized for Forward+. Use the dedicated **Mobile** or **Compatibility** renderers for optimal fill-rate.
- **NEVER leave 'ETC2/ASTC' texture compression disabled** — Uncompressed desktop textures will crash mobile devices due to VRAM exhaustion.
- **NEVER block the main thread for I/O** — Large file saves on mobile can trigger ANR (Application Not Responding) errors. Use background threads.

### 项目设置（竖屏 720×1280 + Mobile 渲染器）
```ini
[rendering]
renderer/rendering_method="mobile"
textures/vram_compression/import_etc2_astc=true

[display]
window/handheld/orientation="portrait"
```

### 纹理压缩与加载卡顿
- VRAM compression audit: Mobile → ETC2 / ASTC；pixel art → compression off（逐资源检查，勿整包关闭）。
- Shader hitch: 在加载界面预编译 shader（Forward+/Mobile 下实例化并 `hide()` 特效节点即可触发编译），避免游玩中掉帧尖峰。

## 3. Android 导出与命令行打包

### NEVER (export & release)
- **NEVER export to production without a smoke test** — Editor play ≠ Web/Mobile/Console constraints.
- **NEVER ship Debug templates as release** — Use `--export-release`.
- **NEVER include raw authoring junk** — Filter `.md` / `.psd` / docs out of presets.
- **NEVER commit keystores or passwords** — Env vars only.
- **NEVER leave debug cheats in release** — Gate with `OS.has_feature("release")`.
- **NEVER use ad-hoc writable `res://` paths in builds** — Saves/logs go to `user://`.

### Android 打包清单
- Android SDK + OpenJDK 17；export templates 版本必须与项目 Godot 版本一致（本项目 4.7.1）。
- Keystore 与密码只通过环境变量注入（CI/本机均如此），绝不提交进仓库。

### Headless 命令行导出
```powershell
godot --headless --export-release "Android" builds/game.apk
godot --headless --export-debug "Android" builds/game_debug.apk
```
- CI/脚本中 pin Godot 4.7 编辑器 + 4.7 export templates，勿用旧版容器镜像。

### 版本号管理
- Sync git tag → `application/config/version`（project.godot）；不要只在 UI 里硬编码版本标签。

### 运行时 feature flags
```gdscript
if OS.has_feature("android"):
    pass
if OS.has_feature("mobile"):
    pass
if OS.has_feature("release"):
    pass  # strip debug consoles
```

<!-- 来源映射
- 触屏与竖屏: godot-platform-mobile（SKILL.md 的 Input & Display / Permissions NEVER 清单 + references/mobile-touch-and-expert.md 的 Touch input、Safe Areas、Android-Back-Button Handler、Vibration-Intensity Haptic Profiles）
- 移动端渲染与性能: godot-platform-mobile（SKILL.md 的 Battery & Performance NEVER 清单、Project settings (mobile)、decision tree 的 renderer 行 + references/mobile-touch-and-expert.md 的 Mobile-Shader-Precompiler；VRAM 表来自 godot-export-builds 的 references/export-setup-guide.md）
- Android 导出与命令行打包: godot-export-builds（SKILL.md 的 NEVER Do 清单与 CI Contract + references/export-setup-guide.md 的 Install templates、Command-line export、Android checklist、Version string sync、Feature flags at runtime）
-->
