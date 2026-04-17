## [2026-04-17 21:22] | Task: 修正权限引导 panel 跟随逻辑

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5.4`
* **Runtime**: `Codex CLI / Swift 6.2.4 / macOS`

### 📥 User Query
> 打开授权页面后，点 `Allow` 时辅助窗口的跟随有问题；它会一直跟在 `System Settings` 的 `Accessibility` 窗口里 `+ / -` 下面，需要修复。

### 🛠 Changes Overview
**Scope:** `apps/OpenComputerUse`, `docs/`

**Key Actions:**
- **[改掉控件级锚点]**: 删除基于 `Accessibility` 页 `Add` / `Remove` 按钮区域的定位逻辑，不再用局部控件驱动辅助 panel 的位置。
- **[改成窗口级跟随]**: 辅助 panel 现在改为跟随 `System Settings` 主窗口右侧内容区的底边，并继续按可见屏幕范围做 clamp。
- **[同步文档]**: 更新架构说明和权限 onboarding execution plan，移除“锚到 `Add` / `Remove`”的过时描述。

### 🧠 Design Intent (Why)
这次修复的重点不是简单把 panel 换个坐标，而是把定位源从“页面里最脆弱的局部控件”切回“稳定的窗口级几何信息”。这样即使 `Accessibility` 页列表滚动、布局细节变化，拖拽辅助 panel 也会继续贴着 `System Settings` 主窗口走，而不是显得像被 `+ / -` 区域绑住。

### 📁 Files Modified
- `apps/OpenComputerUse/Sources/OpenComputerUse/PermissionOnboardingApp.swift`
- `docs/exec-plans/active/20260417-permission-onboarding-app.md`
