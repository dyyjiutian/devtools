# os/lib

跨平台 OS 初始化共享逻辑。

- [`packages_list.sh`](packages_list.sh)：解析 `packages.list`
  （`name version source kind tags`），供 `os/macos` 与 `os/linux` setup 脚本复用。
  支持按 `kind`（cli/tui/gui）与用途 `tags` 筛选。
