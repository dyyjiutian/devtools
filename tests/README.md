# 测试

存放跨模块 Shell 回归测试。测试使用临时目录和 fake 命令，不执行真实安装。

- repository_structure_test.sh：路径引用和功能模块 README 覆盖检查。
- git_setup_test.sh：GitHub CLI 安装逻辑回归测试。
- linux_setup_scripts_test.sh：Linux 缓存、仓库和重试逻辑回归测试。

~~~bash
bash tests/repository_structure_test.sh
bash tests/git_setup_test.sh
bash tests/linux_setup_scripts_test.sh
~~~
