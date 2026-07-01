#!/bin/bash

display_suitable_disks() {
	local -n disk_arr=$1
	echo -e "${BOLD}Suitable / Ready-to-use Disks Found:${NC}"
	subheader
	printf "  %-4s  %-12s  %-10s  %-30s\n" "ID" "Device Name" "Size" "Model / Hardware Details"
	subheader

	local idx=1
	for item in "${disk_arr[@]}"; do
		IFS=';' read -r name size model <<< "$item"
		printf "  %-4d  %-12s  %-10s  %-30s\n" "$idx" "/dev/$name" "$size" "$model"
		idx=$((idx + 1))
	done
	subheader
	echo ""
}

display_fs_diagnostics() {
	local -n suitable_ref=$1
	suitable_ref=()

	echo -e "${BOLD}[SCAN DIAGNOSTICS] Evaluating system storage devices...${NC}"
	subheader

	local raw_disks
	mapfile -t raw_disks < <(lsblk -pdno NAME,SIZE,TYPE 2>/dev/null | grep -w 'disk' || true)

	for row in "${raw_disks[@]}"; do
		[ -z "$row" ] && continue
		local dev_path size type
		read -r dev_path size type <<< "$row"
		local dev_name
		dev_name=$(basename "$dev_path")

		local model
		model=$(lsblk -dno MODEL "$dev_path" 2>/dev/null | xargs || echo "Unknown Model")

		local reasons=()
		analyze_disk_suitability "$dev_name" reasons

		echo -e "Evaluating ${CYAN}/dev/${dev_name}${NC} [${size}] - ${model}:"

		if [ ${#reasons[@]} -eq 0 ]; then
			echo -e "  --> Status: ${GREEN}${BOLD}✔ SUITABLE${NC} (Unused & ready for provisioning)"
			suitable_ref+=("${dev_name};${size};${model}")
		else
			echo -e "  --> Status: ${RED}${BOLD}✘ NOT SUITABLE${NC}"
			echo -e "  --> Reason(s):"
			for r in "${reasons[@]}"; do
				echo -e "      * ${r}"
			done
		fi
		echo ""
	done
	subheader
	echo ""
}
