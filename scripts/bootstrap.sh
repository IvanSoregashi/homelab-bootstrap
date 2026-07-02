#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/platform.sh"
source "${SCRIPT_DIR}/../lib/bw.sh"

require_root

echo "=== Installing Bitwarden CLI ==="
install_bw

echo "=== Configuring Vault Server ==="
bw_configure_server

echo "=== Authenticating ==="
bw_login

echo "=== Retrieving Bootstrap Secrets ==="
ITEM_JSON=$(bw_get_item "Utsuwa-Bootstrap")

CORE_BUCKET=$(echo "$ITEM_JSON" | jq -r '.fields[] | select(.name=="core-bucket") | .value')
CORE_ID=$(echo "$ITEM_JSON" | jq -r '.fields[] | select(.name=="core-id") | .value')
CORE_KEY=$(echo "$ITEM_JSON" | jq -r '.fields[] | select(.name=="core-key") | .value')
CORE_PW=$(echo "$ITEM_JSON" | jq -r '.fields[] | select(.name=="core-pw") | .value')

DATA_BUCKET=$(echo "$ITEM_JSON" | jq -r '.fields[] | select(.name=="data-bucket") | .value')
DATA_ID=$(echo "$ITEM_JSON" | jq -r '.fields[] | select(.name=="data-id") | .value')
DATA_KEY=$(echo "$ITEM_JSON" | jq -r '.fields[] | select(.name=="data-key") | .value')
DATA_PW=$(echo "$ITEM_JSON" | jq -r '.fields[] | select(.name=="data-pw") | .value')

TAILSCALE_KEY=$(echo "$ITEM_JSON" | jq -r '.fields[] | select(.name=="tailscale-key") | .value // empty')
SSH_PRIVATE_KEY=$(echo "$ITEM_JSON" | jq -r '.fields[] | select(.name=="sendo-ssh-key") | .value // empty')

echo "=== Writing Restic Environment & Password Files ==="
mkdir -p /srv/encrypted/apps/restic/

echo "$CORE_PW" > /srv/encrypted/apps/restic/core-pw
echo "$DATA_PW" > /srv/encrypted/apps/restic/data-pw

cat << EOF > /srv/encrypted/apps/restic/core-env.sh
export B2_ACCOUNT_ID="$CORE_ID"
export B2_ACCOUNT_KEY="$CORE_KEY"
export RESTIC_REPOSITORY="$CORE_BUCKET:/"
export RESTIC_PASSWORD_FILE="/srv/encrypted/apps/restic/core-pw"
EOF

cat << EOF > /srv/encrypted/apps/restic/data-env.sh
export B2_ACCOUNT_ID="$DATA_ID"
export B2_ACCOUNT_KEY="$DATA_KEY"
export RESTIC_REPOSITORY="$DATA_BUCKET:/"
export RESTIC_PASSWORD_FILE="/srv/encrypted/apps/restic/data-pw"
EOF

chmod 400 /srv/encrypted/apps/restic/core-pw
chmod 400 /srv/encrypted/apps/restic/data-pw
chmod 400 /srv/encrypted/apps/restic/core-env.sh
chmod 400 /srv/encrypted/apps/restic/data-env.sh

echo "=== Provisioning SSH Key (Optional) ==="
if [ -n "$SSH_PRIVATE_KEY" ]; then
    echo "SSH Private Key found. Configuring ~/.ssh/id_ed25519..."
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    # Normalize PEM: Bitwarden custom fields flatten newlines to spaces.
    # Split header/footer onto their own lines, then replace remaining
    # spaces (within the base64 body) with newlines.
    echo "$SSH_PRIVATE_KEY" | \
        sed -E 's/(-----BEGIN[^-]+-----) /\1\n/g; s/ (-----END[^-]+-----)/\n\1/g' | \
        awk '!/^-----/ { gsub(/ /, "\n") } 1' > ~/.ssh/id_ed25519
    chmod 600 ~/.ssh/id_ed25519
else
    echo "No SSH Private Key found in Bitwarden. Skipping SSH key setup."
fi

echo "=== Provisioning Tailscale Key (Optional) ==="
if [ -n "$TAILSCALE_KEY" ]; then
    echo "Tailscale Auth Key found. Saving to /srv/encrypted/apps/tailscale-key..."
    echo "$TAILSCALE_KEY" > /srv/encrypted/apps/tailscale-key
    chmod 400 /srv/encrypted/apps/tailscale-key
else
    echo "No Tailscale Auth Key found in Bitwarden. Skipping."
fi

echo "=== Secure Cleanup ==="
bw_logout

unset ITEM_JSON CORE_ID CORE_KEY CORE_PW DATA_ID DATA_KEY DATA_PW TAILSCALE_KEY SSH_PRIVATE_KEY

echo "=== Success: Utsuwa is fully bootstrapped! ==="
