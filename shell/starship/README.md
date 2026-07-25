# Starship 配置

跨 shell 共用的 Starship prompt 配置。

## 文件

| 文件 | 说明 |
|------|------|
| `starship.toml` | 主配置 |
| `starship-tokyo.toml` | macOS / 通用 Tokyo Night 风格配置 |
| `starship-tokyo-linux.toml` | Linux Tokyo Night 风格配置 |

`terminal/bash/setup.sh` 和 `terminal/zsh/setup.sh` 会按系统自动复制对应 Tokyo 配置到 `~/.config/starship.toml`。

手动部署：

```bash
mkdir -p ~/.config
cp terminal/starship/starship.toml ~/.config/starship.toml
```

