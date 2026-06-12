#!/usr/bin/env bash
set -euo pipefail

# AzerothCore 数据库独立更新脚本
# 用于数据库与 Docker 分离部署的场景，不依赖容器内程序自动更新
#
# 用法:
#   ./db-update.sh              # 增量更新：应用缺失的 updates SQL
#   ./db-update.sh --dry-run    # 预览模式：只显示将要执行的更新

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACORE_ROOT="${ACORE_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"

DRY_RUN=false

# 解析参数
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
    esac
done

# 加载 .env 文件
if [ -f "$ENV_FILE" ]; then
    # shellcheck source=/dev/null
    set -a
    source "$ENV_FILE"
    set +a
    echo "> Loaded config from $ENV_FILE"
else
    echo "> Warning: .env file not found at $ENV_FILE, using environment variables"
fi

# 数据库连接配置
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-acore}"
DB_PASS="${DB_PASS:-}"

# 数据库名
DB_AUTH="${DB_AUTH:-acore_auth}"
DB_CHARACTERS="${DB_CHARACTERS:-acore_characters}"
DB_WORLD="${DB_WORLD:-acore_world}"

# ============================================================
# MySQL 客户端检测：优先本地 mysql，否则用 docker
# ============================================================

if command -v mysql &>/dev/null; then
    MYSQL_CMD="mysql -h $DB_HOST -P $DB_PORT -u $DB_USER"
    if [ -n "$DB_PASS" ]; then
        MYSQL_CMD="$MYSQL_CMD -p'$DB_PASS'"
    fi
    MYSQL_CLIENT="local"
else
    echo "> Local mysql client not found, using docker mysql:8.0"
    MYSQL_CMD="docker run --rm -i mysql:8.0 mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p'$DB_PASS'"
    MYSQL_CLIENT="docker"
fi

echo ""
echo "============================================"
echo "  AzerothCore Database Update Tool"
echo "============================================"
echo "  Host:       $DB_HOST:$DB_PORT"
echo "  User:       $DB_USER"
echo "  Auth DB:    $DB_AUTH"
echo "  Char DB:    $DB_CHARACTERS"
echo "  World DB:   $DB_WORLD"
echo "  ACore:      $ACORE_ROOT"
echo "  MySQL Client: $MYSQL_CLIENT"
if $DRY_RUN; then
    echo "  Mode:       DRY RUN (preview only)"
else
    echo "  Mode:       INCREMENTAL UPDATE"
fi
echo "============================================"
echo ""

# 测试数据库连接
echo "> Testing database connection..."
if ! eval "$MYSQL_CMD -e 'SELECT 1'" > /dev/null 2>&1; then
    echo "ERROR: Cannot connect to MySQL at $DB_HOST:$DB_PORT"
    echo "Please check your .env file or environment variables:"
    echo "  DB_HOST, DB_PORT, DB_USER, DB_PASS"
    exit 1
fi
echo "> Database connection OK"
echo ""

# ============================================================
# 核心数据库更新
# ============================================================

apply_update_files() {
    local db_name=$1
    local db_dir=$2
    local updates_dir="$ACORE_ROOT/data/sql/updates/$db_dir"

    if [ ! -d "$updates_dir" ]; then
        echo "  WARNING: Updates directory not found: $updates_dir"
        return
    fi

    # 获取已应用的更新列表，写入临时文件以提高可靠性
    local applied_tmp
    applied_tmp=$(mktemp)
    eval "$MYSQL_CMD $db_name -N -e \"SELECT name FROM updates ORDER BY name;\"" > "$applied_tmp" 2>/dev/null || true

    local files=()
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < <(find "$updates_dir" -maxdepth 1 -name "*.sql" -print0 | sort -z)

    if [ ${#files[@]} -eq 0 ]; then
        echo "  No update files in $updates_dir"
        rm -f "$applied_tmp"
        return
    fi

    local applied_count=0
    local skipped_count=0

    for sql_file in "${files[@]}"; do
        local filename
        filename=$(basename "$sql_file")

        if echo "$filename" | grep -qFxf "$applied_tmp"; then
            skipped_count=$((skipped_count + 1))
            continue
        fi

        applied_count=$((applied_count + 1))
        echo "    [APPLY] $filename"
        if ! $DRY_RUN; then
            eval "$MYSQL_CMD $db_name < \"$sql_file\"" || {
                echo "    ERROR: Failed to apply $filename"
                exit 1
            }
            # Record the update in the tracking table
            eval "$MYSQL_CMD $db_name -e \"INSERT IGNORE INTO \\\`updates\\\` (\\\`name\\\`, \\\`hash\\\`, \\\`state\\\`, \\\`speed\\\`) VALUES ('$filename', '', 'RELEASED', 0);\"" || {
                echo "    WARNING: Failed to record $filename in updates table"
            }
        fi
    done

    rm -f "$applied_tmp"
    echo "  Applied: $applied_count, Skipped: $skipped_count"
}

update_database() {
    local label=$1
    local db_name=$2
    local db_dir=$3

    echo ">>> Updating $label database ($db_name) ..."

    # 检查数据库是否存在
    local db_exists
    db_exists=$(eval "$MYSQL_CMD -N -e \"SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '$db_name';\"" 2>/dev/null || true)

    if [ -z "$db_exists" ]; then
        echo "  ERROR: Database '$db_name' does not exist."
        echo "  Please initialize the database first (import base SQL files manually)."
        return
    fi

    echo "  Checking for new updates..."
    apply_update_files "$db_name" "$db_dir"
    echo ""
}

# ============================================================
# 主流程
# ============================================================

update_database "Auth" "$DB_AUTH" "db_auth"
update_database "Characters" "$DB_CHARACTERS" "db_characters"
update_database "World" "$DB_WORLD" "db_world"

echo "============================================"
if $DRY_RUN; then
    echo "  DRY RUN complete. No changes applied."
else
    echo "  Database update complete."
fi
echo "============================================"
