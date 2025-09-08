# Docker Hub 仓库设置指南

## 问题解决

您遇到的错误 `push access denied, repository does not exist` 表示 Docker Hub 上还没有创建这个仓库。

## 解决方案

### 方法 1: 在 Docker Hub 网站上创建仓库

1. 访问 [Docker Hub](https://hub.docker.com/)
2. 登录您的账户 `gys619`
3. 点击 "Create Repository"
4. 填写仓库信息：
   - **Repository Name**: `docker-easyconnect-atrust`
   - **Description**: `aTrust VPN client with VNC optimization for Docker`
   - **Visibility**: Public (推荐) 或 Private
5. 点击 "Create"

### 方法 2: 通过 Docker CLI 自动创建

当您第一次推送镜像时，Docker Hub 会自动创建仓库：

```bash
# 本地构建并推送（这会自动创建仓库）
docker build -t gys619/docker-easyconnect-atrust:test .
docker push gys619/docker-easyconnect-atrust:test
```

### 方法 3: 修改 GitHub Actions 配置

如果您想使用不同的仓库名称，可以修改 `.github/workflows/build-atrust-amd64.yml`：

```yaml
env:
  REGISTRY: docker.io
  IMAGE_NAME: gys619/atrust-vnc  # 更简短的名称
  PLATFORM: linux/amd64
```

## 验证设置

创建仓库后，您可以验证 GitHub Actions 是否能正常工作：

1. 确保 GitHub Secrets 已设置：
   - `DOCKERHUB_USERNAME`: `gys619`
   - `DOCKERHUB_TOKEN`: 您的 Docker Hub 访问令牌

2. 推送代码到 GitHub 触发构建

3. 在 Actions 页面查看构建状态

## 获取 Docker Hub 访问令牌

如果您还没有访问令牌：

1. 登录 [Docker Hub](https://hub.docker.com/)
2. 点击右上角头像 → "Account Settings"
3. 选择 "Security" 选项卡
4. 点击 "New Access Token"
5. 填写令牌名称（如：`github-actions`）
6. 选择权限：`Read, Write, Delete`
7. 点击 "Generate"
8. 复制生成的令牌（只显示一次）

## 当前配置摘要

- **Docker Hub 用户名**: `gys619`
- **仓库名称**: `docker-easyconnect-atrust`
- **完整镜像名**: `gys619/docker-easyconnect-atrust`
- **主要标签**: `atrust-amd64`, `latest`

## 下一步

1. 创建 Docker Hub 仓库
2. 设置 GitHub Secrets
3. 推送代码触发构建
4. 等待构建完成
5. 使用生成的镜像

构建成功后，您就可以使用：

```bash
docker pull gys619/docker-easyconnect-atrust:atrust-amd64
```
