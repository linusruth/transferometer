#!/usr/bin/env bash

# Copyright (C) 2018 Linus Ruth
#
# This is free software, licensed under the Apache License, Version 2.0.

OPENWRT_VERSION='17.01.4'
OPENWRT_MIRROR='downloads.openwrt.org'

fail() {
  printf "\nError: ${1}\n\n"
  exit 1
}

partial_match_in_list() {
  printf "${1}" | grep -q "${2//[[:space:]]/\\|}"
}

exact_match_in_list() {
  printf "${1}" | grep -qw "${2//[[:space:]]/\\|}"
}

command_exists() {
  test -n "$(command -v ${1})"
}

which_command() {
  for COMMAND in ${1}; do
    if command_exists "${COMMAND}"; then
      printf "${COMMAND}"
      break
    fi
  done
}

verify_command_in_path() {
  printf "Verifying that '${1}' is in command path... "

  if command_exists "${1}"; then
    printf 'true\n'
  else
    printf 'false\n'
    fail "Unable to locate '${1}' in command path."
  fi
}

determine_host_os() {
  printf 'Determining host operating system... '
  local ACCEPTED_VALUES='CYGWIN Darwin Linux MINGW'

  HOST_OS="$(uname -s)"
  printf "${HOST_OS}\n"

  if ! partial_match_in_list "${HOST_OS}" "${ACCEPTED_VALUES}"; then
    fail "Host operating system '${HOST_OS}' is not supported.\n" \
      "Supported operating systems are: ${ACCEPTED_VALUES}"
  fi
}

determine_host_architecture() {
  printf 'Determining host architecture... '
  local ACCEPTED_VALUES='i386 i486 i586 i686 x86_64'

  HOST_ARCHITECTURE="$(uname -m)"
  printf "${HOST_ARCHITECTURE}\n"

  if ! exact_match_in_list "${HOST_ARCHITECTURE}" "${ACCEPTED_VALUES}"; then
    fail "Host architecture '${HOST_ARCHITECTURE}' is not supported.\n" \
      "Supported architectures are: ${ACCEPTED_VALUES}"
  fi
}

determine_host_virtualization_extensions() {
  printf 'Determining if host CPU has virtualization extensions... '
  local ACCEPTED_VALUES='true false'

  if test "${HOST_OS}" = 'Linux'; then
    HOST_EXTENSIONS="$(lscpu | grep -qw 'svm\|vmx' && printf 'true' || printf 'false')"
  elif test "${HOST_OS}" = 'Darwin'; then
    HOST_EXTENSIONS="$(sysctl -a | grep -qw 'VMX' && printf 'true' || printf 'false')"
  elif (printf "${HOST_OS}" | grep -q 'CYGWIN\|MINGW'); then
    HOST_EXTENSIONS="$(powershell -c '(GWMI Win32_Processor).VirtualizationFirmwareEnabled')"
    HOST_EXTENSIONS="$(printf "${HOST_EXTENSIONS}" | tr '[:upper:]' '[:lower:]')"
  fi
  printf "${HOST_EXTENSIONS}\n"

  if ! exact_match_in_list "${HOST_EXTENSIONS}" "${ACCEPTED_VALUES}"; then
    fail 'Unable to determine if host CPU has virtualization extensions.'
  fi
}

determine_vm_long_mode() {
  printf 'Determining virtual machine long mode (64-bit) setting... '
  local ACCEPTED_VALUES='on off'

  if test "${HOST_EXTENSIONS}" = 'true'; then
    VM_LONG_MODE='on'
  else
    VM_LONG_MODE='off'
  fi
  printf "${VM_LONGMODE}\n"

  if ! exact_match_in_list "${VM_LONG_MODE}" "${ACCEPTED_VALUES}"; then
    fail 'Unable to determine virtual machine longmode setting.'
  fi
}

determine_vm_os_type() {
  printf 'Determining virtual machine OS type... '
  local ACCEPTED_VALUES='Linux26_64 Linux26'

  if test "${VM_LONG_MODE}" = 'on'; then
    VM_OS_TYPE='Linux26_64'
  else
    VM_OS_TYPE='Linux26'
  fi
  printf "${VM_OS_TYPE}\n"

  if ! exact_match_in_list "${VM_OS_TYPE}" "${ACCEPTED_VALUES}"; then
    fail 'Unable to determine virtual machine OS type.'
  fi
}

create_vm() {
  printf 'Creating virtual machine... '
  VM_NAME="OpenWrt ${OPENWRT_VERSION}"
  VBoxManage createvm \
    --name "${VM_NAME}" \
    --ostype "${VM_OS_TYPE}" \
    --register 1>/dev/null 2>&1

  (test -n "${?}" && printf 'done\n') || (printf 'error\n' && exit 1)
}

list_vbox_host_networks() {
  VBoxManage list hostonlyifs
}

create_vbox_host_network() {
  printf 'Creating VirtualBox host-only network interface... '
  local NETWORKS_BEFORE="$(list_vbox_host_networks)"
  VBoxManage hostonlyif create 1>/dev/null 2>&1

  (test -n "${?}" && printf 'done\n') || (printf 'error\n' && exit 1)

  local NETWORKS_AFTER="$(list_vbox_host_networks)"
  local NEW_NETWORK="$(diff <(echo "${NETWORKS_BEFORE}") <(echo "${NETWORKS_AFTER}"))"
  HOST_NETWORK_NAME="$(printf "${NEW_NETWORK}" | grep -ow 'Name.*' | grep -ow 'vboxnet.*\|VirtualBox.*$')"
  HOST_NETWORK_IP="$(printf "${NEW_NETWORK}" | grep -ow 'IPAddress.*' | grep -ow '[1-9].*')"
  HOST_NETWORK_MASK="$(printf "${NEW_NETWORK}" | grep -ow 'NetworkMask.*' | grep -ow '255.*')"
}

last_octet() {
  printf "${1}" | grep -o '[0-9]*$'
}

create_vbox_host_network_dhcp_server() {
  printf 'Creating VirtualBox host-only network interface DHCP server... '

  local HOST_NETWORK_IP_LAST_OCTET="$(last_octet "${HOST_NETWORK_IP}")"
  local DHCP_NETWORK_LOWER_IP_LAST_OCTET="$((HOST_NETWORK_IP_LAST_OCTET + 1))"
  local DHCP_NETWORK_UPPER_IP_LAST_OCTET="${DHCP_NETWORK_LOWER_IP_LAST_OCTET}"
  local DHCP_NETWORK_PREFIX="$(printf "${HOST_NETWORK_IP}" | grep -o '.*\.')"
  local DHCP_NETWORK_LOWER_IP="${DHCP_NETWORK_PREFIX}${DHCP_NETWORK_LOWER_IP_LAST_OCTET}"
  local DHCP_NETWORK_UPPER_IP="${DHCP_NETWORK_PREFIX}${DHCP_NETWORK_UPPER_IP_LAST_OCTET}"
  VM_IP="${DHCP_NETWORK_LOWER_IP}"

  VBoxManage dhcpserver add \
    --ifname "${HOST_NETWORK_NAME}" \
    --ip "${HOST_NETWORK_IP}" \
    --netmask "${HOST_NETWORK_MASK}" \
    --lowerip "${DHCP_NETWORK_LOWER_IP}" \
    --upperip "${DHCP_NETWORK_UPPER_IP}" \
    --enable 1>/dev/null 2>&1

  (test -n "${?}" && printf 'done\n') || (printf 'error\n' && exit 1)
}

configure_vm_properties() {
  printf 'Configuring virtual machine properties... '

  VBoxManage modifyvm "${VM_NAME}" \
    --hostonlyadapter1 "${HOST_NETWORK_NAME}" \
    --ioapic 'on' \
    --longmode "${VM_LONG_MODE}" \
    --memory '128' \
    --nic1 'hostonly' \
    --nic2 'nat' \
    --nicpromisc1 'deny' \
    --pae 'on' \
    --rtcuseutc 'on' 1>/dev/null 2>&1

  (test -n "${?}" && printf 'done\n') || (printf 'error\n' && exit 1)
}

create_vm_storage_controller() {
  printf 'Creating virtual machine storage controller... '
  STORAGECTL_NAME="SATA"
  VBoxManage storagectl "${VM_NAME}" \
    --name "${STORAGECTL_NAME}" \
    --add 'sata' \
    --controller 'IntelAhci' \
    --portcount '1' 1>/dev/null 2>&1

  (test -n "${?}" && printf 'done\n') || (printf 'error\n' && exit 1)
}

determine_vbox_default_machine_folder() {
  printf 'Determining VirtualBox default machine folder... '
  VBOX_DEFAULT_MACHINE_FOLDER="$(VBoxManage list systemproperties | \
    grep -ow '^Default machine folder:.*$' | \
    cut -d ':' -f 2- | \
    grep -ow '[[:alnum:][:punct:]].*$' | \
    tr '\\' '/')"
  VBOX_DEFAULT_MACHINE_FOLDER="$(printf "${VBOX_DEFAULT_MACHINE_FOLDER}/" | \
    tr -s '/')"
  printf "${VBOX_DEFAULT_MACHINE_FOLDER}\n"

  if ! test -d "${VBOX_DEFAULT_MACHINE_FOLDER}"; then
    fail 'Unable to determine VirtualBox default machine folder.'
  fi
}

determine_vm_folder() {
  printf 'Determining virtual machine folder... '
  VM_FOLDER="$(printf "${VBOX_DEFAULT_MACHINE_FOLDER}/${VM_NAME}/" | \
    tr -s '/')"
  printf "${VM_FOLDER}\n"

  if ! test -d "${VM_FOLDER}"; then
    fail 'Unable to determine virtual machine folder.'
  fi
}

determine_openwrt_architecture() {
  printf 'Determining OpenWrt architecture... '
  local ACCEPTED_VALUES='x86-64 x86-generic'

  if test "${VM_OS_TYPE}" = 'Linux26_64'; then
    OPENWRT_ARCHITECTURE='x86-64'
  else
    OPENWRT_ARCHITECTURE='x86-generic'
  fi
  printf "${OPENWRT_ARCHITECTURE}\n"

  if ! exact_match_in_list "${OPENWRT_ARCHITECTURE}" "${ACCEPTED_VALUES}"; then
    fail 'Unable to determine OpenWRT architecture.'
  fi
}

determine_download_utility() {
  printf 'Determining download utility... '
  local ACCEPTED_VALUES="curl wget"

  DOWNLOAD_UTILITY="$(which_command "${ACCEPTED_VALUES}")"
  printf "${DOWNLOAD_UTILITY}\n"

  if ! exact_match_in_list "${DOWNLOAD_UTILITY}" "${ACCEPTED_VALUES}"; then
    fail 'Unable to locate compatible download utility.\n' \
      "Supported download utilitities are: ${ACCEPTED_VALUES}"
  fi
}

download_firmware_image() {
  printf 'Downloading firmware image... '
  FIRMWARE_PACKAGE="lede-${OPENWRT_VERSION}-${OPENWRT_ARCHITECTURE}-combined-ext4.img.gz"
  FIRMWARE_PACKAGE_PATH="$(printf "${VM_FOLDER}/${FIRMWARE_PACKAGE}" | tr -s '/')"
  local BASE_URL="https://${OPENWRT_MIRROR}/releases/${OPENWRT_VERSION}/targets"
  local FIRMWARE_URL="${BASE_URL}/${OPENWRT_ARCHITECTURE//-/\/}/${FIRMWARE_PACKAGE}"

  if test "${DOWNLOAD_UTILITY}" = 'curl'; then
    curl -L -s -o "${FIRMWARE_PACKAGE_PATH}" "${FIRMWARE_URL}"
  elif test "${DOWNLOAD_UTILITY}" = 'wget'; then
    wget -q -O "${FIRMWARE_PACKAGE_PATH}" "${FIRMWARE_URL}"
  fi

  (test -n "${?}" && printf 'done\n') || (printf 'error\n' && exit 1)
}

determine_extraction_utility() {
  printf 'Determining extraction utility... '
  local ACCEPTED_VALUES='gunzip gzip'

  EXTRACTION_UTILITY="$(which_command "${ACCEPTED_VALUES}")"
  printf "${EXTRACTION_UTILITY}\n"

  if ! exact_match_in_list "${EXTRACTION_UTILITY}" "${ACCEPTED_VALUES}"; then
    fail 'Unable to locate compatible extraction utility.\n' \
      "Supported extraction utilities are: ${ACCEPTED_VALUES}"
  fi
}

extract_firmware_image() {
  printf 'Extracting firmware image... '
  if test "${EXTRACTION_UTILITY}" = 'gunzip'; then
    gunzip "${FIRMWARE_PACKAGE_PATH}"
  elif test "${EXTRACTION_UTILITY}" = 'gzip'; then
    gzip -d "${FIRMWARE_PACKAGE_PATH}"
  fi

  (test -n "${?}" && printf 'done\n') || (printf 'error\n' && exit 1) 
}

convert_firmware_image_to_vdi() {
  printf 'Converting firmware image to VirtualBox Disk Image (VDI)... '
  FIRMWARE_IMAGE="${FIRMWARE_PACKAGE_PATH//.gz/}"
  FIRMWARE_VDI="${FIRMWARE_IMAGE//.img/.vdi}"
  VBoxManage convertfromraw --format VDI "${FIRMWARE_IMAGE}" "${FIRMWARE_VDI}" 1>/dev/null 2>&1

  (test -n "${?}" && printf 'done\n') || (printf 'error\n' && exit 1)
}

delete_firmware_image() {
  printf 'Deleting firmware image... '
  rm -f "${FIRMWARE_IMAGE}"

  (test -n "${?}" && printf 'done\n') || (printf 'error\n' && exit 1)
}

attach_vm_hard_drive() {
  printf 'Attaching virtual machine hard drive... '
  VBoxManage storageattach "${VM_NAME}" \
    --storagectl "${STORAGECTL_NAME}" \
    --port '0' \
    --device '0' \
    --type 'hdd' \
    --medium "${FIRMWARE_VDI}" 1>/dev/null 2>&1

  (test -n "${?}" && printf 'done\n') || (printf 'error\n' && exit 1)
}

start_vm() {
  printf 'Starting virtual machine... '
  VBoxManage startvm "${VM_NAME}" --type headless 1>/dev/null 2>&1

  (test -n "${?}" && printf 'done\n') || (printf 'error\n' && exit 1)
}

setup_complete() {
  printf '\nSetup complete!\n\n'
  printf 'Please open the VM console and run the following commands:\n\n'
  printf 'uci set network.lan.proto=dhcp\n'
  printf 'uci commit network\n'
  printf '/etc/init.d/network restart\n\n'
  printf 'After that, you may connect locally to the VM via SSH:\n\n'
  printf "ssh root@${VM_IP}\n\n"
}

main() {
  determine_host_os
  determine_host_architecture
  determine_host_virtualization_extensions
  determine_vm_long_mode
  determine_vm_os_type
  verify_command_in_path 'VBoxManage'
  create_vm
  create_vbox_host_network
  create_vbox_host_network_dhcp_server
  configure_vm_properties
  create_vm_storage_controller
  determine_vbox_default_machine_folder
  determine_vm_folder
  determine_openwrt_architecture
  determine_download_utility
  download_firmware_image
  determine_extraction_utility
  extract_firmware_image
  convert_firmware_image_to_vdi
  delete_firmware_image
  attach_vm_hard_drive
  start_vm
  setup_complete
}

main

