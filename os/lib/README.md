# os/lib

跨平台 OS 初始化共享逻辑。

- [`packages_list.sh`](packages_list.sh)：解析 `packages.list`
  （`name version source kind tags`），供 `os/macos` 与 `os/linux` setup 脚本复用。
  支持按 `kind`（cli/tui/gui）与用途 `tags` 筛选。
- [`dnf_mirrors.sh`](dnf_mirrors.sh)：保留官方 DNF 源，并在有已知公网镜像时写入 Aliyun companion。
  当前可映射 Docker CE（`download.docker.com/linux/centos` → `mirrors.aliyun.com/docker-ce`）。
  Aliyun 没有 GitHub CLI / NodeSource 的 RPM 镜像，这两处只保留官方源。
  [`repos/epel-8-aliyun.repo`](repos/epel-8-aliyun.repo) 是钉死 el8 的 Aliyun EPEL，供 Alinux 3 使用。
