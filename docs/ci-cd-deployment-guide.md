# AzerothCore CI/CD 部署方案

> 制定日期：2026-06-06
> 适用仓库：azerothcore-wotlk 主仓库及全部 modules

---

## 一、现状与痛点

| 痛点 | 根因 | 解决方向 |
|---|---|---|
| 手动拷贝 EXE，风险高 | 无自动化打包流程 | CI 自动构建 Docker 镜像 |
| Windows EXE 不能跑在 Mac Mini | 平台绑定 | 使用 Linux Docker 镜像，跨平台运行 |
| 模块分散在不同仓库 | 构建时需要汇总 | CI 中自动拉取所有模块仓库 |
| 缺少测试环境 | 只有一套生产 | Docker Compose 快速启动独立测试环境 |

---

## 二、核心设计决策

### 2.1 为什么用 Docker 而不是直接编译 EXE？

| 对比项 | Visual Studio EXE | Docker 镜像 |
|---|---|---|
| Mac Mini (测试机) | ❌ 不能运行 | ✅ Docker Desktop 运行 Linux 容器 |
| Windows 生产机 | ✅ 可以运行 | ✅ Docker Desktop 运行 Linux 容器 |
| Linux 生产机 | ❌ 不能运行 | ✅ 原生运行 |
| 部署方式 | 手动拷贝文件 | `docker-compose pull && up -d` |
| 回滚 | 手动备份替换 | `docker-compose up` 指定旧版本标签 |
| 模块编译 | 本地逐个处理 | CI 中一次性全量编译 |

**结论**：Docker 镜像是唯一能在 Mac Mini、Windows、Linux 三端统一运行的方案。

### 2.2 数据库策略：使用外部 MySQL

**重要说明**：
- 测试环境（Mac Mini）已配置好 MySQL，已有历史运行数据
- 生产环境未来将部署腾讯云 MySQL，同样已有历史数据
- **因此不需要初始化创建数据库**，只需要配置容器连接到现有数据库

---

## 三、整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                      GitHub (代码仓库)                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ 主仓库        │  │ 模块仓库 ×12  │  │ CI 工作流     │      │
│  │ azerothcore  │  │ mod-xxx      │  │ .github/     │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└──────────────────────────┬──────────────────────────────────┘
                           │ Push 触发
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                  GitHub Actions (CI 构建)                    │
│  1. 检出主仓库 + 所有模块                                     │
│  2. Docker Build (Linux 多阶段构建)                           │
│  3. 推送到腾讯云 TCR                                         │
│     └─ 标签: azerothcore:develop / azerothcore:master        │
└──────────────────────────┬──────────────────────────────────┘
                           │
           ┌───────────────┴───────────────┐
           ▼                               ▼
┌─────────────────────┐         ┌─────────────────────┐
│   Mac Mini (测试)    │         │  生产服务器 (Linux)   │
│  Docker Desktop     │         │  Docker + Compose    │
│  docker-compose up  │         │  docker-compose up   │
└──────────┬──────────┘         └──────────┬──────────┘
           │                               │
           └───────────────┬───────────────┘
                           ▼
           ┌───────────────────────────────┐
           │       外部 MySQL 数据库         │
           │   测试: Mac Mini 本地 MySQL    │
           │   生产: 腾讯云 MySQL           │
           │   (已有历史数据，无需初始化)     │
           └───────────────────────────────┘
```

---

## 四、模块处理策略

### 方案 A：CI 中自动拉取（推荐，当前阶段）

在 CI 工作流中，构建前自动拉取所有模块：

```yaml
- name: Clone modules
  run: |
    git clone --depth=1 --branch master https://github.com/domonic18/mod-ale.git modules/mod-ale
    git clone --depth=1 --branch master https://github.com/domonic18/mod-anticheat.git modules/mod-anticheat
    # ... 其他模块
```

**优点**：主仓库保持干净，不依赖 Git Submodule  
**缺点**：CI 中需要维护模块列表

### 方案 B：Git Submodule（未来可迁移）

在主仓库中添加所有模块为 submodule：

```bash
git submodule add https://github.com/domonic18/mod-ale.git modules/mod-ale
```

**优点**：版本锁定，主仓库明确知道用了哪个版本的模块  
**缺点**：操作复杂，每次模块更新需要同步主仓库

**建议**：先用方案 A，等模块稳定后考虑迁移到方案 B。

---

## 五、镜像标签策略

| 镜像标签 | 触发条件 | 用途 |
|---|---|---|
| `develop` | push 到 develop 分支 | 测试环境 (Mac Mini) |
| `master` | push 到 master 分支 | 生产环境 |
| `sha-xxxxxxx` | 每次构建 | 历史版本，便于回滚 |

---

## 六、GitHub Actions CI 工作流

文件路径：`.github/workflows/build-docker.yml`

```yaml
name: Build AzerothCore Server Image

on:
  push:
    branches: [master, develop]
  workflow_dispatch:

env:
  REGISTRY: ccr.ccs.tencentyun.com
  IMAGE_NAME: azerothcore-server

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout main repo
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Clone all modules
        run: |
          mkdir -p modules
          declare -A MODULES=(
            ["mod-ale"]="https://github.com/domonic18/mod-ale.git"
            ["mod-anticheat"]="https://github.com/domonic18/mod-anticheat.git"
            ["mod-challenge-modes"]="https://github.com/domonic18/mod-challenge-modes.git"
            ["mod-costumes"]="https://github.com/domonic18/mod-costumes.git"
            ["mod-keep-out"]="https://github.com/domonic18/mod-keep-out.git"
            ["mod-multi-client-check"]="https://github.com/domonic18/mod-multi-client-check.git"
            ["mod-progression-system"]="https://github.com/domonic18/mod-progression-system.git"
            ["mod-server-auto-shutdown"]="https://github.com/domonic18/mod-server-auto-shutdown.git"
            ["mod-transmog"]="https://github.com/domonic18/mod-transmog.git"
            ["mod-war-effort"]="https://github.com/domonic18/mod-war-effort.git"
            ["mod-world-chat"]="https://github.com/domonic18/mod-world-chat.git"
            ["mod-zone-difficulty"]="https://github.com/domonic18/mod-zone-difficulty.git"
            ["mod-chat-transmitter"]="https://github.com/domonic18/mod-chat-transmitter.git"
          )
          for name in "${!MODULES[@]}"; do
            branch="master"
            git clone --depth=1 --branch "$branch" "${MODULES[$name]}" "modules/$name"
          done

      - name: Login to Tencent Cloud TCR
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ secrets.TCR_USERNAME }}
          password: ${{ secrets.TCR_PASSWORD }}

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          file: ./apps/docker/Dockerfile
          push: true
          tags: |
            ${{ env.REGISTRY }}/${{ secrets.TCR_NAMESPACE }}/${{ env.IMAGE_NAME }}:${{ github.ref_name }}
            ${{ env.REGISTRY }}/${{ secrets.TCR_NAMESPACE }}/${{ env.IMAGE_NAME }}:sha-${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

---

## 七、部署配置

### 7.1 docker-compose.yml

```yaml
version: '3.8'

services:
  ac-worldserver:
    image: ccr.ccs.tencentyun.com/your-namespace/azerothcore-server:${TAG:-master}
    container_name: ac-worldserver
    restart: unless-stopped
    volumes:
      - ./data:/azerothcore/data
      - ./configs:/azerothcore/env/dist/etc
      - ./logs:/azerothcore/env/dist/logs
    ports:
      - "8085:8085"
    environment:
      - AC_DATA_DIR=/azerothcore/data
      - AC_DB_HOST=${DB_HOST}
      - AC_DB_PORT=${DB_PORT:-3306}
      - AC_DB_USER=${DB_USER}
      - AC_DB_PASSWORD=${DB_PASSWORD}

  ac-authserver:
    image: ccr.ccs.tencentyun.com/your-namespace/azerothcore-server:${TAG:-master}
    container_name: ac-authserver
    restart: unless-stopped
    command: ./authserver
    volumes:
      - ./configs:/azerothcore/env/dist/etc
      - ./logs:/azerothcore/env/dist/logs
    ports:
      - "3724:3724"
    environment:
      - AC_DB_HOST=${DB_HOST}
      - AC_DB_PORT=${DB_PORT:-3306}
      - AC_DB_USER=${DB_USER}
      - AC_DB_PASSWORD=${DB_PASSWORD}
```

### 7.2 环境变量文件

**`.env.example`**（复制为 `.env` 后使用）
```bash
# 腾讯云容器镜像服务配置
REGISTRY=ccr.ccs.tencentyun.com
NAMESPACE=your-namespace

# 镜像标签：develop(测试) / master(生产)
TAG=master

# 外部 MySQL 配置
DB_HOST=your-mysql-host
DB_PORT=3306
DB_USER=acore
DB_PASSWORD=your-password
```

### 7.3 动态配置脚本（docker-entrypoint.sh）

容器启动时将环境变量写入 AzerothCore 配置文件：

```bash
#!/bin/bash
CONFIG_DIR="/azerothcore/env/dist/etc"

# 替换数据库连接信息
sed -i "s|LoginDatabaseInfo.*=.*|LoginDatabaseInfo = \"${AC_DB_HOST};${AC_DB_PORT};${AC_DB_USER};${AC_DB_PASSWORD};acore_auth\"|g" ${CONFIG_DIR}/worldserver.conf
sed -i "s|WorldDatabaseInfo.*=.*|WorldDatabaseInfo = \"${AC_DB_HOST};${AC_DB_PORT};${AC_DB_USER};${AC_DB_PASSWORD};acore_world\"|g" ${CONFIG_DIR}/worldserver.conf
sed -i "s|CharacterDatabaseInfo.*=.*|CharacterDatabaseInfo = \"${AC_DB_HOST};${AC_DB_PORT};${AC_DB_USER};${AC_DB_PASSWORD};acore_characters\"|g" ${CONFIG_DIR}/worldserver.conf

exec ./worldserver
```

---

## 八、部署命令

| 场景 | 命令 |
|---|---|
| 启动服务 | `docker-compose --env-file .env up -d` |
| 查看日志 | `docker-compose logs -f ac-worldserver` |
| 版本回滚 | 修改 `.env` 中的 `TAG=sha-xxx`，重新执行 `up -d` |
| 停止服务 | `docker-compose down` |

---

## 九、GitHub Secrets 配置

在 GitHub 仓库设置中配置以下 Secrets：

| Secret | 说明 |
|---|---|
| `TCR_USERNAME` | 腾讯云 TCR 用户名 |
| `TCR_PASSWORD` | 腾讯云 TCR 密码 |

---

## 十、实施路线图

| 阶段 | 任务 | 预计时间 |
|---|---|---|
| **Phase 1** | 在主仓库添加 Dockerfile、docker-compose.yml、CI 工作流 | 1 天 |
| **Phase 2** | 配置腾讯云 TCR 和 GitHub Secrets | 2 小时 |
| **Phase 3** | 验证 CI 能成功构建带模块的镜像 | 2-3 天（调试） |
| **Phase 4** | Mac Mini 使用 docker-compose 部署测试 | 1 天 |
| **Phase 5** | 生产环境切换为 Docker 部署 | 1 天 |

---

## 十一、参考链接

- [AzerothCore Docker 官方文档](https://www.azerothcore.org/wiki/install-with-docker)
- [AzerothCore 官方 Docker Compose](https://www.azerothcore.org/acore-docker/)
- [GitHub Actions docker/build-push-action](https://github.com/docker/build-push-action)
- [腾讯云容器镜像服务 TCR](https://cloud.tencent.com/product/tcr)
