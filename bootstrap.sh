#!/bin/bash
set -e

# We will use a dummy local Vaultwarden address for testing
LOCAL_VAULTWARDEN="https://vw.utsuwa.local"
PUBLIC_BITWARDEN="https://identity.bitwarden.com"

echo "=== PHASE 1: Installing System Dependencies ==="
sudo apt-get update && sudo apt-get install -y jq unzip curl

echo "=== PHASE 2: Installing Standalone Bitwarden CLI ==="
curl -sSL -o bw.zip "https://vault.bitwarden.com/download/?app=cli&platform=linux"
unzip -o bw.zip
sudo mv bw /usr/local/bin/
rm bw.zip
chmod +x /usr/local/bin/bw

echo "=== PHASE 3: Configuring Vault Server ==="
# Check if the local Vaultwarden instance is reachable (2-second timeout)
echo "Checking if local Vaultwarden ($LOCAL_VAULTWARDEN) is online..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "$LOCAL_VAULTWARDEN" || echo "000")

if [ "$HTTP_STATUS" -ne "000" ]; then
    echo "Local Vaultwarden is ONLINE (HTTP $HTTP_STATUS). Using local server..."
    bw config server "$LOCAL_VAULTWARDEN"
else
    echo "Local Vaultwarden is OFFLINE or unreachable. Falling back to public Bitwarden Cloud..."
    bw config server "$PUBLIC_BITWARDEN"
fi

echo "=== PHASE 4: Authenticating ==="
bw login
export BW_SESSION=$(bw unlock --raw)

echo "=== PHASE 5: Retrieving Bootstrap Secrets ==="
ITEM_JSON=$(bw get item "Utsuwa-Bootstrap")

# Extract Core & Data credentials [1.1.3]
CORE_ID=$(echo "$ITEM_JSON" | jq -r '.fields[] | select(.name=="core-id") | .value')
CORE_KEY=$(echo "$ITEM_JSON" | jq -r '.fields[] | select(.name=="core-key") | .value')
CORE_PW=$(echo "$ITEM_JSON" | jq -r '.fields[] | select(.name=="core-pw") | .value')

DATA_ID=$(echo "$ITEM_JSON" | jq -r '.fields[] | select(.name=="data-id") | .value')
DATA_KEY=$(echo "$ITEM_JSON" | jq -r '.fields[] | select(.name=="data-key") | .value')
DATA_PW=$(echo "$ITEM_JSON" | jq -r '.fields[] | select(.name=="data-pw") | .value')

# Extract Tailscale & SSH Keys (handled gracefully if empty) [1.1.3]
TAILSCALE_KEY=$(echo "$ITEM_JSON" | jq -r '.fields[] | select(.name=="tailscale-key") | .value // empty')
SSH_PRIVATE_KEY=$(echo "$ITEM_JSON" | jq -r '.fields[] | select(.name=="sendo-ssh-key") | .value // empty')

echo "=== PHASE 6: Writing Restic Environment & Password Files ==="
# Ensure our secure restic directory exists
mkdir -p /srv/encrypted/app/restic/

# Write your passwords to their local files [1.2.9]
echo "$CORE_PW" > /srv/encrypted/app/restic/core-pw
echo "$DATA_PW" > /srv/encrypted/app/restic/data-pw

# --- THE FIX: Saving the B2 IDs & Keys for your automated scripts ---
# We write them to local, executable shell configurations.
# Your automated daily backup scripts will simply "source" these files to log in! [1.2.9]
cat << EOF > /srv/encrypted/app/restic/restic-core-env.sh
export B2_ACCOUNT_ID="$CORE_ID"
export B2_ACCOUNT_KEY="$CORE_KEY"
export RESTIC_REPOSITORY="b2:utsuwa-backup-core:/"
export RESTIC_PASSWORD_FILE="/srv/encrypted/app/restic/core-pw"
EOF

cat << EOF > /srv/encrypted/app/restic/restic-data-env.sh
export B2_ACCOUNT_ID="$DATA_ID"
export B2_ACCOUNT_KEY="$DATA_KEY"
export RESTIC_REPOSITORY="b2:utsuwa-backup-data:/"
export RESTIC_PASSWORD_FILE="/srv/encrypted/app/restic/data-pw"
EOF

# Enforce strict POSIX permissions (chmod 400) on all keys and password files [1.2.9]
chmod 400 /srv/encrypted/app/restic/core-pw
chmod 400 /srv/encrypted/app/restic/data-pw
chmod 400 /srv/encrypted/app/restic/restic-core-env.sh
chmod 400 /srv/encrypted/app/restic/restic-data-env.sh


echo "=== PHASE 7: Provisioning SSH Key (Optional) ==="
if [ -n "$SSH_PRIVATE_KEY" ]; then
    echo "SSH Private Key found. Configuring ~/.ssh/id_rsa..."
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    echo "$SSH_PRIVATE_KEY" > ~/.ssh/id_rsa
    chmod 600 ~/.ssh/id_rsa
else
    echo "No SSH Private Key found in Bitwarden. Skipping SSH key setup."
fi


echo "=== PHASE 8: Provisioning Tailscale (Optional) ==="
if [ -n "$TAILSCALE_KEY" ]; then
    echo "Tailscale Auth Key found. Connecting to Tailnet..."
    # (Assuming Tailscale is already installed on the host OS by your main script)
    sudo tailscale up --authkey="$TAILSCALE_KEY"
else
    echo "No Tailscale Auth Key found in Bitwarden. Skipping automated Tailscale login."
fi


echo "=== PHASE 9: Secure Cleanup ==="
# Log out of Bitwarden to wipe local session caches on disk [1.2.1]
bw logout

# Unset all sensitive variables from Utsuwa's RAM
unset BW_SESSION ITEM_JSON CORE_ID CORE_KEY CORE_PW DATA_ID DATA_KEY DATA_PW TAILSCALE_KEY SSH_PRIVATE_KEY

echo "=== Success: Utsuwa is fully bootstrapped! ==="
