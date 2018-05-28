#!/usr/bin/env bash

# Copyright (C) 2018 Linus Ruth
#
# This is free software, licensed under the Apache License, Version 2.0.

OPENWRT_VERSION="17.01.4"

setup_complete() {
  printf "\nSetup complete!\n\n"
}

fail() {
  printf "\nError: ${1}\n\n"
  exit 1
}

partial_match_in_list() {
  printf "${1}" | grep -q "${2//[[:space:]]/\\\|}"
}

exact_match_in_list() {
  printf "${1}" | grep -qw "${2//[[:space:]]/\\\|}"
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
    printf "true\n"
  else
    printf "false\n"
    fail "Unable to locate '${1}' in command path."
  fi
}

determine_host_os() {
  printf "Determining host operating system... "
  local ACCEPTED_VALUES="CYGWIN Darwin Linux MINGW"

  HOST_OS="$(uname -s)"
  printf "${HOST_OS}\n"

  if ! partial_match_in_list "${HOST_OS}" "${ACCEPTED_VALUES}"; then
    fail "Host operating system '${HOST_OS}' is not supported.\n" \
      "Supported operating systems are: ${ACCEPTED_VALUES}"
  fi
}

determine_host_architecture() {
  printf "Determining host architecture... "
  local ACCEPTED_VALUES="i386 i486 i586 i686 x86_64"

  HOST_ARCHITECTURE="$(uname -m)"
  printf "${HOST_ARCHITECTURE}\n"

  if ! exact_match_in_list "${HOST_ARCHITECTURE}" "${ACCEPTED_VALUES}"; then
    fail "Host architecture '${HOST_ARCHITECTURE}' is not supported.\n" \
      "Supported architectures are: ${ACCEPTED_VALUES}"
  fi
}

determine_host_virtualization_extensions() {
  printf "Determining if host CPU has virtualization extensions... "
  local ACCEPTED_VALUES="true false"

  if test "${HOST_OS}" = "Linux"; then
    HOST_EXTENSIONS="$(lscpu | grep -qw "svm\|vmx" && printf "true" || printf "false")"
  elif test "${HOST_OS}" = "Darwin"; then
    HOST_EXTENSIONS="$(sysctl -a | grep -qw "VMX" && printf "true" || printf "false")"
  elif (printf "${HOST_OS}" | grep -q "CYGWIN\|MINGW"); then
    HOST_EXTENSIONS="$(powershell -c "(GWMI Win32_Processor).VirtualizationFirmwareEnabled")"
    HOST_EXTENSIONS="$(printf "${HOST_EXTENSIONS}" | tr "[:upper:]" "[:lower:]")"
  fi
  printf "${HOST_EXTENSIONS}\n"

  if ! exact_match_in_list "${HOST_EXTENSIONS}" "${ACCEPTED_VALUES}"; then
    fail "Unable to determine if host CPU has virtualization extensions."
  fi
}

determine_openwrt_architecture() {
  printf "Determining OpenWrt architecture... "
  local ACCEPTED_VALUES="x86-64 x86-generic"

  if test "${HOST_EXTENSIONS}" = "true"; then
    OPENWRT_ARCHITECTURE="x86-64"
  else
    OPENWRT_ARCHITECTURE="x86-generic"
  fi
  printf "${OPENWRT_ARCHITECTURE}\n"

  if ! exact_match_in_list "${OPENWRT_ARCHITECTURE}" "${ACCEPTED_VALUES}"; then
    fail "Unable to determine OpenWRT architecture."
  fi
}

generate_firmware_url() {
  printf "Generating firmware image URL... "
  BASE_URL="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets"
  FIRMWARE_PACKAGE="lede-${OPENWRT_VERSION}-${OPENWRT_ARCHITECTURE}-combined-ext4.img.gz"
  FIRMWARE_URL="${BASE_URL}/${OPENWRT_ARCHITECTURE//-/\/}/${FIRMWARE_PACKAGE}"
  printf "done\n"
}

determine_download_utility() {
  printf "Determining download utility... "
  local ACCEPTED_VALUES="curl wget"

  DOWNLOAD_UTILITY="$(which_command "${ACCEPTED_VALUES}")"
  printf "${DOWNLOAD_UTILITY}\n"

  if ! exact_match_in_list "${DOWNLOAD_UTILITY}" "${ACCEPTED_VALUES}"; then
    fail "Unable to locate compatible download utility.\n" \
      "Supported download utilitities are: ${ACCEPTED_VALUES}"
  fi
}

download_firmware_image() {
  printf "Downloading firmware image... "
  if test "${DOWNLOAD_UTILITY}" = "curl"; then
    curl -s -O "${FIRMWARE_URL}"
  elif test "${DOWNLOAD_UTILITY}" = "wget"; then
    wget -q "${FIRMWARE_URL}"
  fi

  (test -n "${?}" && printf "done\n") || (printf "error\n" && exit 1)
}

determine_extraction_utility() {
  printf "Determining extraction utility... "
  local ACCEPTED_VALUES="gunzip gzip"

  EXTRACTION_UTILITY="$(which_command "${ACCEPTED_VALUES}")"
  printf "${EXTRACTION_UTILITY}\n"

  if ! exact_match_in_list "${EXTRACTION_UTILITY}" "${ACCEPTED_VALUES}"; then
    fail "Unable to locate compatible extraction utility.\n" \
      "Supported extraction utilities are: ${ACCEPTED_VALUES}"
  fi
}

extract_firmware_image() {
  printf "Extracting firmware image... "
  if test "${EXTRACTION_UTILITY}" = "gunzip"; then
    gunzip "${FIRMWARE_PACKAGE}"
  elif test "${EXTRACTION_UTILITY}" = "gzip"; then
    gzip -d "${FIRMWARE_PACKAGE}"
  fi

  (test -n "${?}" && printf "done\n") || (printf "error\n" && exit 1) 
}

convert_firmware_image() {
  printf "Converting firmware image to VirtualBox Disk Image (VDI)... "
  FIRMWARE_IMAGE="${FIRMWARE_PACKAGE//\.gz/}"
  FIRMWARE_VDI="${FIRMWARE_IMAGE//\.img/\.vdi}"
  VBoxManage convertfromraw --format VDI ${FIRMWARE_IMAGE} ${FIRMWARE_VDI} 1>/dev/null 2>&1

  (test -n "${?}" && printf "done\n") || (printf "error\n" && exit 1)
}

determine_vm_os_type() {
  printf "Determining virtual machine OS type... "
  local ACCEPTED_VALUES="Linux26 Linux26_64"

  if test "${OPENWRT_ARCHITECTURE}" = "x86-generic"; then
    VM_OS_TYPE="Linux26"
  elif test ${OPENWRT_ARCHITECTURE} = "x86-64"; then
    VM_OS_TYPE="Linux26_64"
  fi
  printf "${VM_OS_TYPE}\n"

  if ! exact_match_in_list "${VM_OS_TYPE}" "${ACCEPTED_VALUES}"; then
    fail "Unable to determine virtual machine OS type."
  fi
}

create_vm() {
  printf "Creating virtual machine... "
  VM_NAME="OpenWrt ${OPENWRT_VERSION}"
  VBoxManage createvm \
    --name "${VM_NAME}" \
    --ostype "${VM_OS_TYPE}" \
    --register 1>/dev/null 2>&1

  (test -n "${?}" && printf "done\n") || (printf "error\n" && exit 1)
}

determine_vm_longmode() {
  printf "Determining virtual machine 'longmode' setting... "
  local ACCEPTED_VALUES="on off"

  if test "${OPENWRT_ARCHITECTURE}" = "x86-64"; then
    VM_LONGMODE="on"
  else
    VM_LONGMODE="off"
  fi
  printf "${VM_LONGMODE}\n"

  if ! exact_match_in_list "${VM_LONGMODE}" "${ACCEPTED_VALUES}"; then
    fail "Unable to determine virtual machine 'longmode' setting."
  fi
}

configure_vm_properties() {
  printf "Configuring virtual machine properties... "

  VBoxManage modifyvm "${VM_NAME}" \
    --memory "128" \
    --ioapic "on" \
    --longmode "${VM_LONGMODE}" \
    --pae "on" \
    --rtcuseutc "on" 1>/dev/null 2>&1

  (test -n "${?}" && printf "done\n") || (printf "error\n" && exit 1)
}

create_vm_storage_controller() {
  printf "Creating virtual machine storage controller... "
  STORAGECTL_NAME="SATA"
  VBoxManage storagectl "${VM_NAME}" \
    --name "${STORAGECTL_NAME}" \
    --add "sata" \
    --controller "IntelAhci" \
    --portcount "1" 1>/dev/null 2>&1

  (test -n "${?}" && printf "done\n") || (printf "error\n" && exit 1)
}

attach_vm_hard_drive() {
  printf "Attaching virtual machine hard drive... "
  VBoxManage storageattach "${VM_NAME}" \
    --storagectl "${STORAGECTL_NAME}" \
    --port "0" \
    --device "0" \
    --type "hdd" \
    --medium "${FIRMWARE_VDI}" 1>/dev/null 2>&1

  (test -n "${?}" && printf "done\n") || (printf "error\n" && exit 1)
}

list_vbox_host_networks() {
  VBoxManage list hostonlyifs | grep -o "vboxnet[0-9]*$" | uniq | sort | tr "\n" " "
}

create_vbox_host_network() {
  printf "Creating VirtualBox host-only network interface... "
  HOST_NETWORKS_BEFORE="$(list_vbox_host_networks)"
  VBoxManage hostonlyif create 1>/dev/null 2>&1

  (test -n "${?}" && printf "done\n") || (printf "error\n" && exit 1)

  HOST_NETWORKS_AFTER="$(list_vbox_host_networks)"
  HOST_NETWORKS_COMBINED=(${HOST_NETWORKS_BEFORE} ${HOST_NETWORKS_AFTER})
  HOST_NETWORK_NAME="$(printf "${HOST_NETWORKS_COMBINED[*]}" | tr " " "\n" | sort | uniq -u)"
}

main() {
  determine_host_os
  determine_host_architecture
  determine_host_virtualization_extensions
  determine_openwrt_architecture
  generate_firmware_url
  determine_download_utility
  download_firmware_image
  determine_extraction_utility
  extract_firmware_image
  verify_command_in_path "VBoxManage"
  convert_firmware_image
  determine_vm_os_type
  create_vm
  determine_vm_longmode
  configure_vm_properties
  create_vm_storage_controller
  attach_vm_hard_drive
  create_vbox_host_network
  setup_complete
}

main

