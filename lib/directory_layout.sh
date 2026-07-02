SECURE_MOUNT="/srv/encrypted"
DATA_MOUNT="/srv/data"

SECURE_DIRS=(
    "${SECURE_MOUNT}/vault"
    "${SECURE_MOUNT}/archive"
    "${SECURE_MOUNT}/webdav"
    "${SECURE_MOUNT}/db-dumps"
    "${SECURE_MOUNT}/apps/restic"
    "${SECURE_MOUNT}/apps/syncthing"
    "${SECURE_MOUNT}/apps/calibre-config"
    "${SECURE_MOUNT}/apps/immich/db"
)

DATA_DIRS=(
    "${DATA_MOUNT}/gallery/immich"
    "${DATA_MOUNT}/books"
    "${DATA_MOUNT}/downloads"
    "${DATA_MOUNT}/backups"
)
