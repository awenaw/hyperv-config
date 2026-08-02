# TODO

这个清单记录 Debian Hyper-V 镜像工厂的后续改进。完成一项后，将 `[ ]` 改为 `[x]`，并在提交信息中引用对应标题。

## P0：安全与可靠性

- [ ] 为 `mother/debian-13-base.vhdx` 建立至少一份离线备份。
- [ ] 增加母盘存在性、只读属性、VHDX 类型和差分父链检查。
- [ ] 增加创建后的自动验收：两块磁盘、交换机、动态内存、安全启动和自动检查点状态。
- [ ] 增加与当前 `children/debianN` 目录结构兼容的安全删除向导。
- [ ] 删除前显示 VM、磁盘、父盘关系并要求输入 VM 完整名称确认。
- [ ] 评估首次 cloud-init 在最大 `512MB` 内存下是否稳定；必要时把推荐上限调整为 `1GB` 或 `2GB`。

## P1：母盘版本化与镜像烘焙

- [ ] 制定不可变母盘命名规范，例如 `debian-13-base-v1.vhdx`。
- [ ] 编写母盘维护流程：创建临时维护 VM、安装公共软件、清理身份、关机和封装。
- [ ] 封装前执行 `cloud-init clean --logs --machine-id`。
- [ ] 封装前删除 SSH 主机密钥、APT 缓存、临时文件和 shell 历史。
- [ ] 建立 `base`、`ops`、`dev` 三种母盘配置。
- [ ] `ops` 母盘评估预装：`hyperv-daemons`、`htop`、`curl`、`jq`、`lsof`、`dnsutils`。
- [ ] `dev` 母盘评估预装：`git`、`build-essential`、`make`、`pkg-config`。
- [ ] 新母盘只服务新 VM；旧母盘在仍有子盘依赖时禁止移动、覆盖或删除。

## P2：自动测试与日志

- [ ] 为 PowerShell 参数解析、编号建议、内存关系和 SSH 公钥校验增加 Pester 测试。
- [ ] 增加 dry-run 模式，只显示计划，不创建 VM 或磁盘。
- [ ] 使用 `Start-Transcript` 保存每次向导运行日志，并避免记录完整公钥。
- [ ] 自动等待 cloud-init 完成并报告最终状态。
- [ ] 自动显示 Hyper-V KVP 获取的 IPv4 地址和建议 SSH 命令。
- [ ] 增加失败注入测试，验证 CIDATA、差分盘和 VM 创建失败时的回滚边界。
- [ ] 在 GitHub Actions 或其他 CI 中进行 PowerShell 语法检查和 PSScriptAnalyzer 扫描。

## P3：使用体验

- [ ] 增加中文/英文提示语言选择，同时保持 PowerShell 5.1 编码兼容。
- [ ] 支持保存不含秘密的默认配置，例如 CPU、内存和首选交换机。
- [ ] 增加固定 IP 的可选 `network-config` 模板；默认继续使用 DHCP + MAC 标识。
- [ ] 增加母盘与子盘依赖关系报告命令。
- [ ] 增加批量创建模式，同时保持每台 VM 独立确认或提供总清单确认。
- [ ] 增加 `CHANGELOG.md`、语义化版本号和 Git 标签。

## 已完成

- [x] 编写母盘预装、清理、版本化和依赖保护建议文档。
- [x] 使用 Debian 官方云镜像建立只读 VHDX 母盘。
- [x] 使用差分 VHDX 为每台 VM 保存独立系统变化。
- [x] 使用 CIDATA NoCloud 配置用户、SSH、公钥和网络。
- [x] 解决克隆 VM 的 `machine-id` 和 DHCP 客户端标识问题。
- [x] 确认 Wi-Fi 外部交换机不适合当前多 VM 桥接场景，改用有线外部交换机。
- [x] 建立单文件交互向导、最终核对清单、拒绝覆盖和失败回滚。
- [x] 保留模块化三步流程用于学习和排错。
- [x] 建立 Git 仓库并排除个人公钥、VHDX、RAW 和 QCOW2 等产物。
