#!/usr/bin/env bash
set -euo pipefail

# Local build/push script for Tencent Cloud Container Registry (TCR).
# Mirrors the logic in .github/workflows/build-docker.yml, but runs on a
# developer machine. Useful when GitHub Actions runners are too slow.
#
# Configuration is read from .env in the repo root (gitignored). Copy
# .env.example to .env and fill in your real credentials.
#
# Required environment variables:
#   TCR_USERNAME   - TCR login username
#   TCR_PASSWORD   - TCR login password
#   TCR_NAMESPACE  - TCR namespace (e.g. my-team)
#
# Optional environment variables:
#   BRANCH         - git branch to use for the image tag (default: current branch)
#   PLATFORM       - docker build platform (default: linux/amd64)
#   REGISTRY       - registry endpoint (default: ccr.ccs.tencentyun.com)
#   IMAGE_NAME     - image name (default: azerothcore-server)
#   SKIP_MODULES   - set to "1" to skip cloning modules and use existing modules/ directory
#   NO_PUSH        - set to "1" to build only, do not push

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [ -f "$REPO_ROOT/.env" ]; then
    # shellcheck source=/dev/null
    set -a
    source "$REPO_ROOT/.env"
    set +a
    echo "Loaded configuration from $REPO_ROOT/.env"
fi

REGISTRY="${REGISTRY:-ccr.ccs.tencentyun.com}"
IMAGE_NAME="${IMAGE_NAME:-azerothcore-server}"
BRANCH="${BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
SHORT_SHA="$(git rev-parse --short HEAD)"
PLATFORM="${PLATFORM:-linux/amd64}"

if [ -z "${TCR_USERNAME:-}" ] || [ -z "${TCR_PASSWORD:-}" ] || [ -z "${TCR_NAMESPACE:-}" ]; then
    echo "Error: TCR_USERNAME, TCR_PASSWORD and TCR_NAMESPACE must be set." >&2
    echo "Copy .env.example to .env and fill in your credentials." >&2
    exit 1
fi

TAG="${REGISTRY}/${TCR_NAMESPACE}/${IMAGE_NAME}:${BRANCH}-${SHORT_SHA}"

echo "Branch:      $BRANCH"
echo "Short SHA:   $SHORT_SHA"
echo "Platform:    $PLATFORM"
echo "Image tag:   $TAG"

# Clone modules unless skipped
if [ "${SKIP_MODULES:-}" != "1" ]; then
    echo "Cloning modules..."
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
        ["mod-world-chat"]="https://github.com/domonic18/mod-world-chat.git"
        ["mod-zone-difficulty"]="https://github.com/domonic18/mod-zone-difficulty.git"
        ["mod-feishu-chat"]="https://github.com/domonic18/mod-feishu-chat.git"
    )
    for name in "${!MODULES[@]}"; do
        target="modules/$name"
        if [ -d "$target" ]; then
            echo "  Removing existing $target"
            rm -rf "$target"
        fi
        echo "  Cloning $name"
        git clone --depth=1 --branch develop "${MODULES[$name]}" "$target"
    done
else
    echo "SKIP_MODULES=1: using existing modules/ directory"
fi

# Login to TCR
echo "Logging in to $REGISTRY..."
echo "$TCR_PASSWORD" | docker login --username "$TCR_USERNAME" --password-stdin "$REGISTRY"

# Ensure buildx builder is available
BUILDER="tcr-local-builder"
if ! docker buildx inspect "$BUILDER" >/dev/null 2>&1; then
    echo "Creating docker buildx builder: $BUILDER"
    docker buildx create --name "$BUILDER" --use
else
    docker buildx use "$BUILDER"
fi

# Build and (optionally) push
PUSH_ARGS=()
if [ "${NO_PUSH:-}" != "1" ]; then
    PUSH_ARGS=(--push)
else
    echo "NO_PUSH=1: building only"
fi

echo "Building image..."
docker buildx build \
    --platform "$PLATFORM" \
    --file ./apps/docker/Dockerfile \
    --target server \
    --tag "$TAG" \
    "${PUSH_ARGS[@]}" \
    .

echo ""
echo "Done. Image: $TAG"
