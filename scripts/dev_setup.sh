#!/usr/bin/env bash

# Copyright (C) 2018 Linus Ruth
#
# This is free software, licensed under the Apache License, Version 2.0.

OPENWRT_VERSION="17.01.4"

determine_host_os() {
  printf "Determining host operating system... "
  HOST_OS="$(uname -s)"
  printf "${HOST_OS}\n"
}

determine_host_architecture() {
  determine_host_os

  printf "Determining host architecture... "
  HOST_ARCHITECTURE="$(uname -m)"
  printf "${HOST_ARCHITECTURE}\n"
}

determine_host_virtualization_extensions() {
  determine_host_architecture

  printf "Determining if host CPU has virtualization extensions... "
  if test "${HOST_OS}" = "Linux"; then
    HOST_EXTENSIONS="$(lscpu | grep -qw "svm\|vmx" && printf "true" || printf "false")"
  elif test "${HOST_OS}" = "Darwin"; then
    HOST_EXTENSIONS="$(sysctl -a | grep -qw "VMX" && printf "true" || printf "false")"
  elif (printf "${HOST_OS}" | grep -q "CYGWIN\|MINGW"); then
    HOST_EXTENSIONS="$(powershell -c "(GWMI Win32_Processor).VirtualizationFirmwareEnabled")"
    HOST_EXTENSIONS="$(printf "${HOST_EXTENSIONS}" | tr "[:upper:]" "[:lower:]")"
  fi

  if test -n "${HOST_EXTENSIONS}"; then
    printf "${HOST_EXTENSIONS}\n"
  else
    printf "error\n"
    printf "Script does not support host operating system.\n"
    printf "Supported operating systems are: Cygwin Darwin Linux MinGW\n"
    exit 1
  fi
}

determine_openwrt_architecture() {
  determine_host_virtualization_extensions

  printf "Determining OpenWrt architecture... "
  if test "${HOST_ARCHITECTURE}" = "x86_64"; then
    if test "${HOST_EXTENSIONS}" = "true"; then
      OPENWRT_ARCHITECTURE="x86-64"
    else
      OPENWRT_ARCHITECTURE="x86-generic"
    fi
  elif (printf "${HOST_ARCHITECTURE}" | grep -q "^i[[:digit:]]86$"); then
    OPENWRT_ARCHITECTURE="x86-generic"
  fi

  if test -n "${OPENWRT_ARCHITECTURE}"; then
    printf "${OPENWRT_ARCHITECTURE}\n"
  else
    printf "error\n"
    printf "OpenWrt does not support host architecture.\n"
    printf "Supported architectures are: i386 i486 i586 i686 x86_64\n"
    exit 1
  fi
}

generate_firmware_url() {
  determine_openwrt_architecture

  printf "Generating firmware image URL... "
  BASE_URL="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets"
  FIRMWARE_PACKAGE="lede-${OPENWRT_VERSION}-${OPENWRT_ARCHITECTURE}-combined-ext4.img.gz"
  FIRMWARE_URL="${BASE_URL}/${OPENWRT_ARCHITECTURE//-/\/}/${FIRMWARE_PACKAGE}"
  printf "done\n"
}

command_exists() {
  (test -n "$(command -v ${1})" && return 0) || return 1
}

which_command() {
  for COMMAND in ${1}; do
    if command_exists "${COMMAND}"; then
      printf "${COMMAND}"
      break
    fi
  done
}

determine_download_utility() {
  printf "Determining download utility... "
  SUPPORTED_COMMANDS="curl wget"
  DOWNLOAD_UTILITY="$(which_command "${SUPPORTED_COMMANDS}")"

  if test -n "${DOWNLOAD_UTILITY}"; then
    printf "${DOWNLOAD_UTILITY}\n"
  else
    printf "error\n"
    printf "Unable to locate compatible download utility.\n"
    printf "Supported download utilitities are: ${SUPPORTED_COMMANDS}\n"
    exit 1
  fi
}

download_firmware_image() {
  generate_firmware_url
  determine_download_utility

  printf "Downloading firmware image... "
  if test "${DOWNLOAD_UTILITY}" = "curl"; then
    curl -s -O "${FIRMWARE_URL}"
  elif test "${DOWNLOAD_UTILITY}" = "wget"; then
    wget "${FIRMWARE_URL}"
  fi

  (test -n "${?}" && printf "done\n") || (printf "error\n" && exit 1)
}

determine_extraction_utility() {
  printf "Determining extraction utility... "
  SUPPORTED_COMMANDS="gunzip gzip"
  EXTRACTION_UTILITY="$(which_command "${SUPPORTED_COMMANDS}")"

  if test -n "${EXTRACTION_UTILITY}"; then
    printf "${EXTRACTION_UTILITY}\n"
  else
    printf "error\n"
    printf "Unable to locate compatible extraction utility.\n"
    printf "Supported extraction utilities are: ${SUPPORTED_COMMANDS}\n"
    exit 1
  fi
}

extract_firmware_image() {
  download_firmware_image
  determine_extraction_utility

  printf "Extracting firmware image... "
  if test "${EXTRACTION_UTILITY}" = "gunzip"; then
    gunzip "${FIRMWARE_PACKAGE}"
  elif test "${EXTRACTION_UTILITY}" = "gzip"; then
    gzip -d "${FIRMWARE_PACKAGE}"
  fi

  (test -n "${?}" && printf "done\n") || (printf "error\n" && exit 1) 
}

convert_firmware_image() {
  extract_firmware_image

  printf "Converting firmware image to VirtualBox Disk Image (VDI)... "
  FIRMWARE_IMAGE="${FIRMWARE_PACKAGE//\.gz/}"
  FIRMWARE_VDI="${FIRMWARE_IMAGE//\.img/\.vdi}"
  VBoxManage convertfromraw --format VDI ${FIRMWARE_IMAGE} ${FIRMWARE_VDI} 1>/dev/null 2>&1

  (test -n "${?}" && printf "done\n") || (printf "error\n" && exit 1)
}

determine_os_type() {
  convert_firmware_image

  printf "Determining virtual machine OS type... "
  if test "${OPENWRT_ARCHITECTURE}" = "x86-64"; then
    OS_TYPE="Linux26"
  elif test ${OPENWRT_ARCHITECTURE} = "x86-generic"; then
    OS_TYPE="Linux26_64"
  fi

  if test -n "${OS_TYPE}"; then
  printf "${OS_TYPE}\n"
  else
    printf "error\n"
    printf "VirtualBox does not support guest OS type.\n"
    printf "Supported OS types are Linux26 and Linux26_64.\n"
    exit 1
  fi
}

create_vm() {
  determine_os_type

  printf "Creating virtual machine... "
  VM_NAME="OpenWrt ${OPENWRT_VERSION}"
  VBoxManage createvm \
    --name "${VM_NAME}" \
    --ostype "${OS_TYPE}" \
    --register 1>/dev/null 2>&1

  (test -n "${?}" && printf "done\n") || (printf "error\n" && exit 1)
}

configure_vm_properties() {
  create_vm

  printf "Configuring virtual machine properties... "
  if test "${OPENWRT_ARCHITECTURE}" = "x86-64"; then
    LONGMODE="on"
  else
    LONGMODE="off"
  fi

  VBoxManage modifyvm "${VM_NAME}" \
    --memory "128" \
    --ioapic "on" \
    --longmode "${LONGMODE}" \
    --pae "off" \
    --rtcuseutc "on" 1>/dev/null 2>&1

  (test -n "${?}" && printf "done\n") || (printf "error\n" && exit 1)
}

create_vm_storage_controller() {
  configure_vm_properties

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
  create_vm_storage_controller

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
  attach_vm_hard_drive

  printf "Creating VirtualBox host-only network interface... "
  HOST_NETWORKS_BEFORE="$(list_vbox_host_networks)"
  VBoxManage hostonlyif create 1>/dev/null 2>&1

  (test -n "${?}" && printf "done\n") || (printf "error\n" && exit 1)

  HOST_NETWORKS_AFTER="$(list_vbox_host_networks)"
  HOST_NETWORKS_COMBINED=(${HOST_NETWORKS_BEFORE} ${HOST_NETWORKS_AFTER})
  HOST_NETWORK_NAME="$(printf "${HOST_NETWORKS_COMBINED[*]}" | tr " " "\n" | sort | uniq -u)"
}

create_vbox_host_network

