# GitHub Actions 设置指南

## 1. 修改配置

在 `.github/workflows/build-atrust-amd64.yml` 文件中，将以下内容替换为您的实际信息：

```yaml
env:
  REGISTRY: docker.io  # 或者您的私有仓库地址
  IMAGE_NAME: your-dockerhub-username/docker-easyconnect-atrust  # 替换为您的用户名和镜像名
```

## 2. 设置 GitHub Secrets

在您的 GitHub 仓库中设置以下 Secrets：

### 进入仓库设置
1. 打开您的 GitHub 仓库
2. 点击 `Settings` 选项卡
3. 在左侧菜单中点击 `Secrets and variables` > `Actions`

### 添加必要的 Secrets
点击 `New repository secret` 添加以下 secrets：

#### Docker Hub 认证
- **Name**: `DOCKERHUB_USERNAME`
- **Value**: 您的 Docker Hub 用户名

- **Name**: `DOCKERHUB_TOKEN`
- **Value**: 您的 Docker Hub 访问令牌

### 获取 Docker Hub 访问令牌
1. 登录 [Docker Hub](https://hub.docker.com/)
2. 点击右上角头像 > `Account Settings`
3. 选择 `Security` 选项卡
4. 点击 `New Access Token`
5. 输入令牌名称（如：`github-actions`）
6. 选择权限：`Read, Write, Delete`
7. 点击 `Generate` 并复制生成的令牌

## 3. 工作流触发条件

当前配置的触发条件：
- 推送到 `main` 或 `master` 分支
- 修改 Dockerfile 或相关文件
- 手动触发（workflow_dispatch）
- Pull Request

## 4. 构建参数

当前配置：
- **平台**: linux/amd64
- **VPN 类型**: aTrust
- **架构**: AMD64
- **包含 VNC**: 是
- **多阶段构建**: 是（自动构建依赖组件）

构建过程：
1. **Build Stage**: 自动构建 fake-hwaddr、fake-getlogin、tinyproxy、noVNC 等组件
2. **Main Stage**: 安装 aTrust 并配置 VNC 优化功能

## 5. aTrust 版本配置

工作流会自动读取 `build-args/atrust-amd64.txt` 文件中的构建参数。
如果文件不存在，将使用默认的 aTrust 下载地址。

当前默认版本：aTrust 2.4.10.50

## 6. 生成的镜像标签

工作流会自动生成以下标签：
- `latest` (仅在默认分支)
- `atrust-amd64` (仅在默认分支)
- `atrust-vnc-amd64` (仅在默认分支)
- `分支名-SHA` (所有分支)

## 7. 使用示例

构建完成后，您可以这样使用镜像：

```bash
# 基本使用
docker run --rm --device /dev/net/tun --cap-add NET_ADMIN -ti \
  -e PASSWORD=your_password \
  -p 127.0.0.1:5901:5901 \
  -p 127.0.0.1:1080:1080 \
  -p 127.0.0.1:8888:8888 \
  -p 127.0.0.1:54631:54631 \
  --sysctl net.ipv4.conf.default.route_localnet=1 \
  your-dockerhub-username/docker-easyconnect-atrust:atrust-amd64

# 低配置服务器使用
docker run --rm --device /dev/net/tun --cap-add NET_ADMIN -ti \
  --memory=512m --cpus=1.0 \
  -e PASSWORD=your_password \
  -e VNC_AUTO_LOWRES=1 \
  -e VNC_NETWORK_MODE=minimal \
  -p 127.0.0.1:5901:5901 \
  -p 127.0.0.1:1080:1080 \
  -p 127.0.0.1:8888:8888 \
  -p 127.0.0.1:54631:54631 \
  --sysctl net.ipv4.conf.default.route_localnet=1 \
  your-dockerhub-username/docker-easyconnect-atrust:atrust-amd64
```

## 8. 监控构建

- 构建状态可在 `Actions` 选项卡中查看
- 每次构建都会生成详细的构建摘要
- 包含安全扫描结果（使用 Trivy）
- 自动缓存以加速后续构建

## 9. 故障排除

如果构建失败，请检查：
1. Secrets 是否正确设置
2. Docker Hub 令牌是否有效
3. 镜像名称是否正确
4. 网络连接是否正常

## 10. 自定义构建

您可以通过 `workflow_dispatch` 手动触发构建：
1. 进入 `Actions` 选项卡
2. 选择 `Build aTrust AMD64 VNC Image` 工作流
3. 点击 `Run workflow`
4. 可选择是否推送到仓库
