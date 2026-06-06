#!/bin/bash
set -e

CONFIG_DIR="/azerothcore/env/dist/etc"

# Replace database connection info using environment variables
if [ -n "$AC_DB_HOST" ]; then
    echo "Configuring database connection..."

    # worldserver.conf
    if [ -f "${CONFIG_DIR}/worldserver.conf" ]; then
        sed -i "s|LoginDatabaseInfo.*=.*|LoginDatabaseInfo = \"${AC_DB_HOST};${AC_DB_PORT:-3306};${AC_DB_USER};${AC_DB_PASSWORD};acore_auth\"|g" "${CONFIG_DIR}/worldserver.conf"
        sed -i "s|WorldDatabaseInfo.*=.*|WorldDatabaseInfo = \"${AC_DB_HOST};${AC_DB_PORT:-3306};${AC_DB_USER};${AC_DB_PASSWORD};acore_world\"|g" "${CONFIG_DIR}/worldserver.conf"
        sed -i "s|CharacterDatabaseInfo.*=.*|CharacterDatabaseInfo = \"${AC_DB_HOST};${AC_DB_PORT:-3306};${AC_DB_USER};${AC_DB_PASSWORD};acore_characters\"|g" "${CONFIG_DIR}/worldserver.conf"
    fi

    # authserver.conf
    if [ -f "${CONFIG_DIR}/authserver.conf" ]; then
        sed -i "s|LoginDatabaseInfo.*=.*|LoginDatabaseInfo = \"${AC_DB_HOST};${AC_DB_PORT:-3306};${AC_DB_USER};${AC_DB_PASSWORD};acore_auth\"|g" "${CONFIG_DIR}/authserver.conf"
    fi
fi

# Execute the command passed to the container
exec "$@"