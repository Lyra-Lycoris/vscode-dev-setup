# Windows 一键开发环境安装

适用于 Windows 10 2004 及以上、Windows 11，Intel/AMD 64 位系统。

## 使用

1. 将整个文件夹解压到本地，保留 `install.cmd` 和 `setup.ps1` 在同一目录。
2. 双击 `install.cmd`，如弹出 Windows 管理员授权窗口，点击“是”。建议使用日常登录账户启动，不要切换成其他管理员账户。
3. 等待安装结束。看到 `SUCCESS` 表示三个语言的示例均已运行成功，随后会打开 VS Code。
4. 如果 VS Code 提示是否信任示例文件夹，确认这是此脚本生成的本地文件后选择信任。在对应的 `main.cpp`、`main.py` 或 `Main.java` 中按 F5；多项目工作区如要求选择调试配置，选择对应语言即可。Java 扩展第一次初始化可能需要等待。

## 自动完成的内容

- 安装 VS Code、Python 3.13、Eclipse Temurin Java 21 JDK。
- 安装/更新 MSYS2，并安装 UCRT64 GCC、GDB、CMake 和 Ninja。
- 安装 C/C++、CMake、Python、Pylance、Python Debugger 和 Java 扩展包。
- 配置当前用户 PATH 和 JAVA_HOME。
- 在用户目录 `DevExamples/hello-时间戳/` 创建 C++、Python、Java 示例与 VS Code 工作区配置。
- 为 Python 示例创建独立 `.venv` 环境（含 pip）。
- 编译运行 C++、Java 示例，并运行 Python 示例；失败时显示错误及日志位置。

项目配置仅应用于生成的示例。新建项目时可以复制对应的 `.vscode` 文件夹，并按实际源文件位置修改构建/调试路径。C++ 默认示例只编译 `main.cpp`，多个源文件的工程需修改构建任务或使用 CMake。

## 注意事项与排错

- 需要持续联网，下载量和耗时取决于已有软件及网络速度；可能出现系统管理员授权提示，因此不是完全无人值守。
- 运行即会自动接受所安装软件及 WinGet 软件源的许可协议。
- 缺少 WinGet 时，尝试通过微软的 `Microsoft.WinGet.Client` 模块安装。若受系统策略限制，请从 Microsoft Store 安装/更新“应用安装程序”后重试。
- 默认保留已安装的目标 WinGet 软件包，不主动升级它们；MSYS2 则执行完整系统更新，请先关闭其他 MSYS2 终端及使用其中工具的程序。
- 安装中断后可以再次双击。每次创建新的示例目录，不覆盖之前的示例。
- 脚本更新当前用户的环境变量。已有终端和 VS Code 进程需关闭后重开；已有机器级 PATH 中的其他 Python/Java 可能仍优先，新示例通过明确指定路径使用本次安装的版本。
- Python 依赖可在示例目录运行 `.\.venv\Scripts\python.exe -m pip install 包名`；无需修改 PowerShell 全局执行策略。
- 不要从 ZIP 内直接运行。企业电脑的应用安装策略、代理、软件下载域名限制可能导致安装失败，详情见 `logs` 文件夹。
- 本脚本不会自动重启电脑；若安装器要求重启，重启后再次运行。
- 脚本本身已做本地语法和隔离配置检查；未在此电脑实际执行整套软件安装，联网安装及 VS Code 调试仍需在运行时验证。

## 依据

- WinGet：https://learn.microsoft.com/en-us/windows/package-manager/winget/
- VS Code C++ / MSYS2：https://code.visualstudio.com/docs/cpp/config-mingw
- MSYS2 软件包管理：https://www.msys2.org/docs/package-management/
