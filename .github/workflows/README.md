# GitHub Actions Workflows

本目录包含了用于构建 Docker 镜像的 GitHub Actions 工作流程。

## 🚀 推荐使用：灵活构建工作流

### `build-flexible.yml` - 统一的灵活构建工作流

这是推荐使用的工作流，支持完全自定义的构建配置。

#### 功能特性

- ✅ **产品选择**：支持 EasyConnect 和 aTrust
- ✅ **版本选择**：支持多个版本 + latest
- ✅ **架构选择**：支持 amd64、arm64、i386、mips64le 或全部架构
- ✅ **智能构建**：自动查找对应的构建参数文件
- ✅ **并行构建**：多架构并行构建提高效率
- ✅ **安全扫描**：集成 Trivy 安全扫描
- ✅ **灵活配置**：可选择是否推送到注册表和运行测试

#### 使用方法

1. **手动触发构建**
   - 进入 GitHub Actions 页面
   - 选择 "Flexible Build - EasyConnect & aTrust" 工作流
   - 点击 "Run workflow"
   - 配置以下参数：

   | 参数 | 描述 | 选项 | 默认值 |
   |------|------|------|--------|
   | Product | 要构建的产品 | aTrust, EasyConnect | aTrust |
   | Version | 版本 | latest, 2.4.10.50, 2.3.10_sp4, 2.3.10_sp3, 2.3.10.65, 2.2.16, 7.6.7, 7.6.3 | latest |
   | Version Type | 版本类型 (VNC 支持级别) | vnc, vncless, cli | vnc |
   | Architecture | 架构 | amd64, arm64, i386, mips64le, all | amd64 |
   | Push to registry | 是否推送到 Docker 注册表 | true, false | true |
   | Run tests | 是否运行测试 | true, false | true |

   **版本类型说明**：
   - **vnc**: 带 VNC 服务端的完整版本 (默认)
   - **vncless**: 不带 VNC 服务端的版本 (镜像更小)
   - **cli**: 纯命令行版本 (最小镜像)

   **注意**：版本列表包含了 aTrust 和 EasyConnect 的所有支持版本，选择时请确保版本与产品类型匹配。

2. **自动触发**
   - 推送到 main/master 分支时自动触发
   - 修改相关文件时自动触发
   - Pull Request 时自动触发（不推送镜像）

#### 构建示例

**默认构建（aTrust 最新版本 VNC AMD64）：**
```yaml
Product: aTrust          # 默认选择
Version: latest          # 默认选择，自动解析为 2.4.10.50
Version Type: vnc        # 默认选择，带 VNC 服务端
Architecture: amd64      # 默认选择
```

**构建 aTrust 最新版本的所有架构（VNC 版本）：**
```yaml
Product: aTrust
Version: latest
Version Type: vnc
Architecture: all
```

**构建 EasyConnect 7.6.7 无 VNC 版本：**
```yaml
Product: EasyConnect
Version: 7.6.7
Version Type: vncless
Architecture: amd64
```

**构建 EasyConnect 7.6.7 CLI 版本：**
```yaml
Product: EasyConnect
Version: 7.6.7
Version Type: cli
Architecture: amd64
```

**构建 aTrust 2.4.10.50 ARM64 版本（仅构建不推送）：**
```yaml
Product: aTrust
Version: 2.4.10.50
Version Type: vnc
Architecture: arm64
Push to registry: false
```

#### 生成的镜像标签

镜像将使用以下标签格式：

**aTrust 镜像** (仓库: `gys619/docker-easyconnect-atrust`):
- `latest` ⭐ (仅限 VNC + AMD64 + latest 版本)
- `atrust-{version}-{architecture}` (例如: `atrust-2.4.10.50-amd64`)
- `{version}-{architecture}` (例如: `2.4.10.50-amd64`)
- `latest-{architecture}` (例如: `latest-amd64`)

**EasyConnect VNC 镜像** (仓库: `gys619/docker-easyconnect`):
- `latest` ⭐ (仅限 VNC + AMD64 + latest 版本)
- `easyconnect-{version}-{architecture}` (例如: `easyconnect-7.6.7-amd64`)
- `{version}-{architecture}` (例如: `7.6.7-amd64`)
- `latest-{architecture}` (例如: `latest-amd64`)

**EasyConnect VNCless 镜像** (仓库: `gys619/docker-easyconnect-vncless`):
- `easyconnect-vncless-{version}-{architecture}` (例如: `easyconnect-vncless-7.6.7-amd64`)
- `{version}-{architecture}` (例如: `7.6.7-amd64`)
- `latest-{architecture}` (例如: `latest-amd64`)

**EasyConnect CLI 镜像** (仓库: `gys619/docker-easyconnect-cli`):
- `easyconnect-cli-{version}-{architecture}` (例如: `easyconnect-cli-7.6.7-amd64`)
- `{version}-{architecture}` (例如: `7.6.7-amd64`)
- `latest-{architecture}` (例如: `latest-amd64`)

**⭐ `latest` 标签规则**：
- 仅在以下条件同时满足时生成 `latest` 标签：
  - 版本类型为 `vnc` (带 VNC 服务端)
  - 架构为 `amd64`
  - 版本选择为 `latest`
  - 推送到 main 分支
- 这确保了 `latest` 标签始终指向最常用的默认配置

#### 构建参数文件

工作流会自动查找对应的构建参数文件：

**EasyConnect:**
- `build-args/{version}-{arch}.txt`
- `build-args/easyconnect-{arch}.txt` (fallback)

**aTrust:**
- `build-args/atrust-{version}-{arch}.txt`
- `build-args/atrust-{arch}.txt` (fallback)

如果找不到对应的构建参数文件，将使用默认的下载链接。

## 📋 其他工作流

### `build-atrust-amd64.yml` - 传统 aTrust AMD64 构建 (已弃用)

⚠️ **已弃用**：建议使用 `build-flexible.yml` 替代。

此工作流仅保留用于向后兼容，新的构建请使用灵活构建工作流。

### `build-and-push-docker-image.yml` - 传统构建工作流

使用自定义 Action 的传统构建方式。

### `check-easyconnect-versions.yml` - 版本检查

用于检查 EasyConnect 新版本的工作流。

## 🔧 开发指南

### 添加新版本支持

1. 在 `build-args/` 目录下创建对应的构建参数文件
2. 在 `build-flexible.yml` 的 `version` 选项中添加新版本
3. 测试构建是否正常

### 添加新架构支持

1. 确保 Dockerfile 支持新架构
2. 创建对应的构建参数文件
3. 在 `setup-matrix` 步骤中添加架构检查逻辑

### 自定义构建参数

构建参数文件格式：
```
--build-arg VPN_URL=https://example.com/package.deb --build-arg VPN_TYPE=ATRUST
```

每行一个参数，支持多个 `--build-arg` 参数。

## 🔧 版本选择说明

版本选择现在是下拉菜单，包含所有支持的版本：

**aTrust 版本**：
- `latest` → 自动解析为 `2.4.10.50`
- `2.4.10.50` (最新)
- `2.3.10_sp4`
- `2.3.10_sp3`
- `2.3.10.65`
- `2.2.16`

**EasyConnect 版本**：
- `latest` → 自动解析为 `7.6.7`
- `7.6.7` (最新)
- `7.6.3`

**使用建议**：
- 选择 `latest` 会自动根据产品类型选择对应的最新版本
- 也可以直接选择具体版本号进行精确构建
- 版本列表包含了两个产品的所有版本，选择时请确保版本与产品类型匹配

**`latest` 标签特殊说明**：
- 当选择 `latest` 版本 + `vnc` 类型 + `amd64` 架构时，会额外生成不带架构后缀的 `latest` 标签
- 这使得用户可以直接使用 `docker pull gys619/docker-easyconnect-atrust:latest` 获取最常用的默认配置
- 其他配置组合仍会生成 `latest-{architecture}` 格式的标签

## 📞 支持

如果在使用过程中遇到问题，请：

1. 检查构建日志中的错误信息
2. 确认构建参数文件是否存在且格式正确
3. 验证选择的版本和架构组合是否受支持
4. 提交 Issue 并附上详细的错误信息

---

**推荐使用 `build-flexible.yml` 进行所有新的构建任务！** 🎯
