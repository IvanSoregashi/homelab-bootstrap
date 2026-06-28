#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/platform.sh"

# --- Argument Validation ---
if [ "$#" -ne 2 ]; then
    error "Missing required paths."
    echo "Usage: $0 <path_to_secure_volume> <path_to_data_volume>"
    echo "Example: $0 /vault/secure /bulk"
    exit 1
fi

if [ ! -d "$1" ] || [ ! -d "$2" ]; then
    error "One or both of the provided directory paths do not exist on the filesystem."
    echo "Please ensure the storage pools are mounted."
    exit 1
fi

SECURE_PATH=$(realpath "$1")
DATA_PATH=$(realpath "$2")
SYS_USER=$(detect_user)

header "                 DIRECTORY & APP SETUP"
echo -e "Secure Path: ${GREEN}$SECURE_PATH${NC}"
echo -e "Data Path:   ${GREEN}$DATA_PATH${NC}"
echo -e "System User: ${GREEN}$SYS_USER${NC}"

APPS_DIR="${SCRIPT_DIR}/../apps"

# --- Mount Safety Verification ---
echo "--> Verifying drive mount safety..."
check_mount_safety "$SECURE_PATH" "Secure"
check_mount_safety "$DATA_PATH" "Data"

# --- Setup Standardized /srv Bind Mounts ---
echo -e "\n--> Preparing standardized /srv bind mounts..."
mkdir -p /srv/encrypted /srv/data

add_fstab_bind "$SECURE_PATH" "/srv/encrypted"
add_fstab_bind "$DATA_PATH" "/srv/data"

# --- Mount the new paths ---
echo "--> Mounting standardized /srv layers..."

if ! mountpoint -q /srv/encrypted; then
    mount /srv/encrypted || echo -e "${YELLOW}Warning: /srv/encrypted could not mount (is the pool locked?)${NC}"
else
    echo "  /srv/encrypted is already mounted."
fi

if ! mountpoint -q /srv/data; then
    mount /srv/data || echo -e "${YELLOW}Warning: /srv/data could not mount.${NC}"
else
    echo "  /srv/data is already mounted."
fi

# --- Application Setup ---
run_app_setup() {
    local script_path="$1"
    local script_name
    script_name=$(basename "$script_path" .sh)

    echo -e "\n${CYAN}------------------------------------------------------------${NC}"
    echo -e "Executing: ${BOLD}${script_name^^}${NC}"
    echo -e "${CYAN}------------------------------------------------------------${NC}"
    bash "$script_path" "$SECURE_PATH" "$DATA_PATH" "$SYS_USER"
}

run_all_apps() {
    local -n scripts_ref=$1
    echo -e "\n--> Initializing ALL applications..."
    for script in "${scripts_ref[@]}"; do
        run_app_setup "$script"
    done
}

if [ -d "$APPS_DIR" ]; then
    mapfile -t app_scripts < <(find "$APPS_DIR" -type f -name "*.sh" | sort)

    if [ ${#app_scripts[@]} -eq 0 ]; then
        echo -e "${YELLOW}No application setup scripts found under ${APPS_DIR}.${NC}"
    elif [ "${AUTO_APPS:-false}" = "true" ]; then
        run_all_apps app_scripts
    else
        echo -e "\n${BOLD}Application Selection:${NC}"
        declare -a pretty_names
        for i in "${!app_scripts[@]}"; do
            script="${app_scripts[i]}"
            script_name=$(basename "$script" .sh)
            pretty_name=$(echo "$script_name" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++)sub(/./,toupper(substr($i,1,1)),$i)}1')
            pretty_names[i]="$pretty_name"
            echo -e "  $((i + 1))) $pretty_name"
        done
        echo -e "  ${BOLD}A) ALL Applications${NC}"
        echo -e "  ${BOLD}S) SKIP (Base storage layers only)${NC}"
        echo ""

        while true; do
            read -r -p "Select apps [1-${#app_scripts[@]}], 'A' for all, or 'S' to skip: " user_input

            if [ -z "${user_input// /}" ] || [[ "$user_input" =~ ^[Ss]$ ]]; then
                echo -e "\nSkipping application provisioning."
                break
            fi

            if [[ "$user_input" =~ ^[Aa]$ ]]; then
                run_all_apps app_scripts
                break
            fi

            cleaned_input="${user_input//,/ }"
            selected_indices=()
            invalid_input=false

            for choice in $cleaned_input; do
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#app_scripts[@]}" ]; then
                    selected_indices+=("$((choice - 1))")
                else
                    echo -e "${RED}Invalid selection: $choice${NC}"
                    invalid_input=true
                fi
            done

            if [ "$invalid_input" = true ]; then
                echo -e "Please try again.\n"
                continue
            fi

            declare -A seen
            dedup_indices=()
            for idx in "${selected_indices[@]}"; do
                if [ -z "${seen[$idx]+_}" ]; then
                    seen[$idx]=1
                    dedup_indices+=("$idx")
                fi
            done

            sorted_indices=($(for idx in "${dedup_indices[@]}"; do echo "$idx"; done | sort -n))

            echo -e "\nYou selected:"
            for idx in "${sorted_indices[@]}"; do
                echo -e "  - ${pretty_names[idx]}"
            done
            echo ""

            read -r -p "Proceed? (y/n) [y]: " confirm_install
            confirm_install=${confirm_install:-y}
            if [[ "$confirm_install" =~ ^[Yy]$ ]]; then
                echo -e "\n--> Initializing chosen applications..."
                for idx in "${sorted_indices[@]}"; do
                    run_app_setup "${app_scripts[idx]}"
                done
                break
            else
                echo -e "Selection discarded.\n"
            fi
        done
    fi
else
    echo -e "${YELLOW}Application directory does not exist at ${APPS_DIR}.${NC}"
fi

# Base permissions
echo -e "\n--> Aligning system volume permissions..."
chown "${SYS_USER}:${SYS_USER}" "$SECURE_PATH" || true
chown "${SYS_USER}:${SYS_USER}" "$DATA_PATH" || true

echo -e "\n======================================================================"
echo -e "${GREEN}✔ Initialization Complete!${NC}"
echo -e "  /srv/encrypted  -> $SECURE_PATH"
echo -e "  /srv/data       -> $DATA_PATH"
echo -e "======================================================================\n"
