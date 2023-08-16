#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright 2023 Martin L Roth - gaumless@gmail.com
# shellcheck disable=SC2024

set +x

TEST_DIR="board_tests_$(date -u | sed 's/[ :]/_/g')"
#make temp directory
mkdir "$TEST_DIR"
cd "$TEST_DIR" || exit 1
TEST_DIR=${PWD}

BIOS_IS_COREBOOT=""
BIOS_IS_UEFI=""
CPU_IS_INTEL=""
CPU_IS_AMD=""
FIRMWARE_BIN="fw_rom.bin"

# Text STYLE variables
GREEN='\033[38;5;2m'
NO_COLOR='\033[0m'

_echo_color() {
	local color="$1"
	local text="$2"
	printf "${color}%s${NO_COLOR}\n" "${text}"
}

install_tools() {
  echo "Installing tools needed for testing."
  echo "Enter password to continue or Ctl-c to exit"
  sudo echo
  _echo_color "${GREEN}" "Installing tools..."

  # Install tools and libraries needed for tests
    sudo apt update >>install.log 2>>install.err.log
    printf "."
    sudo apt install -y sysbench >>install.log 2>>install.err.log
    printf "."
    sudo apt install -y git subversion libpci-dev libusb-dev autoconf automake flex bison dkms libtool m4 libglib2.0-dev libpcre3-dev libbsd-dev gawk >>install.log 2>>install.err.log
    printf "."
    sudo apt install -y acpica-tools >>install.log 2>>install.err.log
    printf "."
    sudo apt install -y lm-sensors >>install.log 2>>install.err.log
    printf "."
    sudo apt install -y libusb-1.0-0-dev >>install.log 2>>install.err.log
    printf "."
    sudo apt install -y tpm2-tools >>install.log 2>>install.err.log
    printf "."
    sudo apt install -y gpiod >>install.log 2>>install.err.log
    printf "."
    sudo apt install -y python3 python3-pip python3-ipython >>install.log 2>>install.err.log
    printf "."

{
    local iotools_src_dir="./tmp/iotools"
    git_fetch "iotools" "${iotools_src_dir}" "https://github.com/martinlroth/iotools.git"

    if pushd "${iotools_src_dir}" >/dev/null; then
      echo "Building iotools"
      make -j|| exit 1
      sudo make install
      popd >/dev/null || return
    fi
    rm -rf "${iotools_src_dir}"
  } >>install.log 2>>install.err.log
    printf ".\n"
}

git_fetch() {
  local toolname=$1
  local src_dir=$2
  local repo_url=$3

  if [ ! -d "${src_dir}" ]; then
    echo "Cloning ${toolname} repo"
    git clone "${repo_url}" "${src_dir}" >/dev/null 2>&1
  else
    if pushd "${src_dir}" >/dev/null; then
      git fetch origin >/dev/null 2>&1 && git checkout origin/HEAD >/dev/null 2>&1
      popd >/dev/null || return
    fi
  fi
}

run_fwts() {
  local fwts_src_dir=/tmp/fwts_src
  {
   _echo_color "${GREEN}" "Setting up to run FWTS tests..."
    git_fetch "fwts" "${fwts_src_dir}" "git://kernel.ubuntu.com/hwe/fwts.git"

    if pushd "${fwts_src_dir}" >/dev/null; then
      echo "Building FWTS..."
      autoreconf -ivf
      ./configure --prefix=/usr
      make -j || echo "Falling back to pre-built version of FWTS"
      popd >/dev/null || return
    fi

    mkdir fwts
    if [ -f "${fwts_src_dir}/src/fwts" ]; then
      FWTS="${fwts_src_dir}/src/fwts"
    else
      sudo apt install -y fwts
      FWTS=fwts
    fi
  } >>install.log 2>>install.err.log

  _echo_color "${GREEN}" "Running FWTS tests..."
  "${FWTS}" -v version.txt >fwts/version.txt
  sudo "${FWTS}" --utils --force-clean --results-output fwts/results-u.log
  sudo "${FWTS}" --batch --force-clean --results-output fwts/results-b.log
}

dump_acpi() (
  # Dump ACPI tables
  if mkdir -p acpi && pushd acpi >/dev/null; then
    _echo_color "${GREEN}"  "Gathering ACPI information..."
    sudo acpidump >acpidump.log 2>acpidump.err.log
    sudo acpixtract -a >>acpidump.log 2>>acpidump.err.log
    iasl -d ./*.dat  >>acpidump.log 2>>acpidump.err.log
    popd >/dev/null || return
  fi
)

gather_logs() {
  # Save dmesg
  _echo_color "${GREEN}"  "Gathering dmesg information..."
  sudo dmesg -x 2>dmesg.err.log | grep -v "SerialNumber:" >dmesg.log
}

save_proc_info() {
  # Gather system information from /proc & /sys
  _echo_color "${GREEN}"  "Gathering information from /proc & /sys..."
  cat /proc/meminfo >meminfo.log
  sudo cat /proc/mtrr >mtrr.log 2>mtrr.err.log
  cat /proc/interrupts >interrupts.log
  cat /proc/iomem >iomem.log
  cat /proc/ioports >ioports.log
  for x in /sys/class/sound/card0/hw*; do
    printf "%s %s (%s)\n" "$(cat "$x/vendor_name")" "$(cat "$x/chip_name")" "$(cat "$x/vendor_id")" >"pin_$(basename "$x".log)" 2>"pin_$(basename "$x".err.log)"
    cat "$x/init_pin_configs" >>"pin_$(basename "$x".log)" 2>>"pin_$(basename "$x".err.log)"
    echo >>"pin_$(basename "$x".log)"
  done
  for card in /proc/asound/card*; do
    for x in "${card}"/codec#*; do
      cat "$x" >"$(basename "$card")_$(basename "$x").log" 2>"$(basename "$card")_$(basename "$x").err.log"
    done
  done
  cat /sys/class/input/input*/uevent | sed 's/PRODUCT=/\nPRODUCT=/' >input_types.log 2>input_types.err.log
}

run_sysbench() {
  # Run sysbench to get some rough benchmark information to compare against
  _echo_color "${GREEN}"  "Running benchmark tests.  This can take a while..."
  echo "  Benchmarking cpu.  2 tests."
  sysbench cpu --cpu-max-prime=10000 run >sysbench_cpu_1_core.txt
  sysbench cpu --cpu-max-prime=10000 --num-threads="$(nproc)" run >"sysbench_cpu_$(nproc)_cores.txt"
  echo "  Benchmarking Memory writes with 1 core.  2 tests"
  sysbench memory --memory-total-size=20G --memory-oper=write --memory-access-mode=seq run >sysbench_memory_write_seq_1_core.txt
  sysbench memory --memory-total-size=20G --memory-oper=write --memory-access-mode=rnd run >sysbench_memory_write_rnd_1_core.txt
  echo "  Benchmarking Memory reads with 1 core.  2 tests"
  sysbench memory --memory-total-size=20G --memory-oper=read --memory-access-mode=seq run >sysbench_memory_read_seq_1_core.txt
  sysbench memory --memory-total-size=20G --memory-oper=read --memory-access-mode=rnd run >sysbench_memory_read_rnd_1_core.txt
  echo "  Benchmarking Memory writes with $(nproc) cores. 2 tests"
  sysbench memory --memory-total-size=20G --memory-oper=write --memory-access-mode=seq --num-threads="$(nproc)" run >"sysbench_memory_write_seq_$(nproc)_core.txt"
  sysbench memory --memory-total-size=20G --memory-oper=write --memory-access-mode=rnd --num-threads="$(nproc)" run >"sysbench_memory_write_rnd_$(nproc)_core.txt"
  echo "  Benchmarking Memory reads with $(nproc) cores. 2 tests"
  sysbench memory --memory-total-size=20G --memory-oper=read --memory-access-mode=seq --num-threads="$(nproc)" run >"sysbench_memory_read_seq_$(nproc)_core.txt"
  sysbench memory --memory-total-size=20G --memory-oper=read --memory-access-mode=rnd --num-threads="$(nproc)" run >"sysbench_memory_read_rnd_$(nproc)_core.txt"
}

coreboot_tests() {
  local coreboot_src_dir="/tmp/coreboot"
  # Download and run tests from the coreboot repo

  git_fetch coreboot "${coreboot_src_dir}" "https://review.coreboot.org/coreboot.git"

  if [ -n "${BIOS_IS_COREBOOT}" ]; then
    _echo_color "${GREEN}"  "Gathering CBMEM information..."
    make -C ${coreboot_src_dir}/util/cbmem >>install.log 2>>install.err.log
    sudo ${coreboot_src_dir}/util/cbmem/cbmem --console >cbmem-console.log 2>cbmem-console.err.log
    sudo ${coreboot_src_dir}/util/cbmem/cbmem --timestamps >cbmem-timestamps.log 2>cbmem-timestamps.err.log
    sudo ${coreboot_src_dir}/util/cbmem/cbmem --hexdump >cbmem-hexdump.log 2>cbmem-hexdump.err.log
  fi

  #_echo_color "${GREEN}"  "Gathering information with ECTOOL..."
  #make -C ${coreboot_src_dir}/util/ectool >>install.log 2>>install.err.log
  #sudo ${coreboot_src_dir}/util/ectool/ectool -i >ectool_dump.log 2>ectool_dump.err.log

  if [ -n "$CPU_IS_INTEL" ]; then
    _echo_color "${GREEN}"  "Gathering information with inteltool..."
    make -C ${coreboot_src_dir}/util/inteltool
    sudo modprobe msr
    sudo "${coreboot_src_dir}/util/inteltool/inteltool" -g >inteltool_gpios.log 2>inteltool_gpios.err.log
    sudo "${coreboot_src_dir}/util/inteltool/inteltool" -M >inteltool_MSRs.log 2>inteltool_MSRs.err.log
    sudo "${coreboot_src_dir}/util/inteltool/inteltool" -p >inteltool_PM.log 2>inteltool_PM.err.log
    sudo "${coreboot_src_dir}/util/inteltool/inteltool" -m >inteltool_mc.log 2>inteltool_mc.err.log
  fi

  _echo_color "${GREEN}"  "Gathering information with superiotool..."
  make -C "${coreboot_src_dir}/util/superiotool" >>install.log 2>>install.err.log
  sudo "${coreboot_src_dir}/util/superiotool/superiotool" -deV >superiotool.log 2>superiotool.err.log
}

run_dmidecode() {
  # dmidecode - Gather SMBIOS information
  _echo_color "${GREEN}" "Gathering dmidecode information..."
  sudo dmidecode | grep -v "Serial Number:\|ID:\|Asset Tag:" >dmidecode.log 2>dmidecode.err.log

  BIOS_IS_COREBOOT="$(sudo dmidecode -s bios-vendor | grep coreboot)"
  BIOS_IS_UEFI="$(sudo dmidecode -t bios | grep "UEFI is supported")"
  CPU_IS_INTEL="$(sudo dmidecode -s processor-manufacturer | grep -i intel)"
  CPU_IS_AMD="$(sudo dmidecode -s processor-manufacturer | grep -i "Advanced Micro Devices")"
}

run_lspci() {
  #lspci
  _echo_color "${GREEN}" "Gathering lspci information..."
  sudo lspci -mmxxxx >lspci_mmxxxx.log 2>lspci_mmxxxx.err.log
  sudo lspci -vvvxxxxnnqq >lspci_vvvxxxnnqq.log 2>lspci_vvvxxxnnqq.err.log
  sudo lspci -t >lspci_t.log 2>lspci_t.err.log
  sudo lspci -M -H 1 >lspci_M.log 2>/dev/null
}

run_lsusb() {
  _echo_color "${GREEN}" "Gathering lsusb information..."
  lsusb -V lsusb_version.txt >lsusb_version.log 2>lsusb_version.err.log
  sudo lsusb -t >lsusb_t.log 2>lsusb_t.err.log
  sudo lsusb -v >lsusb_v.log 2>lsusb_v.err.log
}

run_lscpu() {
  sudo lscpu >lscpu.log 2>lscpu.err.log
}

run_biosdecode() {
  _echo_color "${GREEN}" "Gathering biosdecode information..."
  sudo biosdecode --pir full >biosdecode.log 2>biosdecode.err.log
}

run_lshw() {
  _echo_color "${GREEN}" "Gathering lshw information..."
  sudo lshw -numeric -sanitize >lshw.log 2>lshw.err.log
}

run_lmsensors() {
  _echo_color "${GREEN}" "Gathering lm-sensors information..."
  sudo sensors-detect --auto >sensors-detect.log 2>sensors-detect.err.log
  sudo sensors -u >sensors.log 2>sensors.err.log
}

run_psptool() {
  if [[ -z ${CPU_IS_AMD} ]]; then
    return
  fi
  if ! sudo pip install psptool; then
    return
  fi
  _echo_color "${GREEN}" "Gathering psptool information..."
  sudo psptool "${TEST_DIR}/${FIRMWARE_BIN}" >psptool.log 2>psptool.err.log
  if mkdir psp_files && pushd psp_files >/dev/null; then
    psptool -X -o "${PWD}" "${TEST_DIR}/${FIRMWARE_BIN}" >psptool.log 2>psptool.err.log
    popd >/dev/null || return
  fi
}

# Print the AMD mmio registers in byte-wide reads
show_mmio_bytewide() {
  local first_reg=$1
  local length_in_bytes=$2

  local reg
  local i

if ! sudo iotools mmio_read8 "${first_reg}" >/dev/null 2>&1; then
  echo "Error: Could not read MMIO address ${first_reg}"
return
fi

  for (( i=0; i<length_in_bytes; i++ )); do
        reg="$(printf "0x%08x%08x\n" "$(iotools shr "${first_reg}" 32 )" "$(( first_reg + i ))" )"
        if [[ "$((i % 16))" -eq 0 ]]; then
          printf "\n%s: " "${reg}"
        fi
        printf "%s " "$(sudo iotools mmio_read8 "${reg}")"
  done
}

# Top level to dump the registers.  Will call sub-functions as needed.
showreg() {
  local title=$1
  local access_type=$2
  local first_reg=$3
  local length_in_bytes=$4
  local read_length=$5

  echo "## ${title}"

  if [[ ${read_length} -eq 4 ]]; then
    echo
    case "${access_type}" in
    "MMIO") sudo iotools mmio_dump "${first_reg}" "${length_in_bytes}" ;;
    "MEM") sudo iotools mem_dump "${first_reg}" "${length_in_bytes}" ;;
    *)
      echo "Error: Invalid access type of ${access_type} for ${title}"
      exit 1
      ;;
    esac
   else
    show_mmio_bytewide "${first_reg}" "${length_in_bytes}"
    echo
  fi

  echo
}

show_amd_mmio() {
  if [[ -z ${CPU_IS_AMD} ]]; then
    return
  fi
  _echo_color "${GREEN}" "Gathering AMD MMIO information..."
  {
    #showreg "SMBus PCI space" "MMIO"   "0xFED80000" 256 4
    showreg "SMI Config"      "MMIO"   "0xFED80200" 256 4
    showreg "PM Regs"         "MMIO"   "0xFED80300" 256 4
    showreg "PM2 Regs"        "MMIO"   "0xFED80400" 256 1
    showreg "BIOS RAM"        "MMIO"   "0xFED80500" 256 1
    showreg "CMOS RAM"        "MMIO"   "0xFED80600" 256 1
    showreg "CMOS"            "MMIO"   "0xFED80700" 256 1
    showreg "ACPI Regs"       "MMIO"   "0xFED80800" 256 4
    showreg "ASF Regs"        "MMIO"   "0xFED80900" 256 4
    showreg "SMBus Regs"      "MMIO"   "0xFED80A00" 256 4
    showreg "WDT Regs"        "MMIO"   "0xFED80B00" 256 4
    showreg "HPET Regs"       "MMIO"   "0xFED80C00" 256 4
    showreg "IOMUX Regs"      "MMIO"   "0xFED80D00" 256 1
    showreg "Misc Regs"       "MMIO"   "0xFED80E00" 256 4
    showreg "Serial Debug"    "MMIO"   "0xFED81000" 256 4
    showreg "Remote GPIO"     "MMIO"   "0xFED81200" 256 4
    showreg "DP VGA"          "MMIO"   "0xFED81400" 256 4
    showreg "GPIO Bank 0"     "MMIO"   "0xFED81500" 256 4
    showreg "GPIO Bank 1"     "MMIO"   "0xFED81600" 256 4
    showreg "GPIO Bank 2"     "MMIO"   "0xFED81700" 256 4
    showreg "GPIO Bank 3"     "MMIO"   "0xFED81800" 256 4
    showreg "XHCI PM Regs"    "MMIO"   "0xFED81C00" 256 4
    showreg "Wake Device"     "MMIO"   "0xFED81D00" 256 4
    showreg "AOAC Regs"       "MMIO"   "0xFED81E00" 256 4
  } >amd_mmio.log 2>amd_mmio.err.log
}

run_utk() {
  if [[ -z ${BIOS_IS_UEFI} ]]; then
    return
  fi

  _echo_color "${GREEN}" "Gathering UTK information"

  go get github.com/linuxboot/fiano/cmds/utk
  "${HOME}/go/bin/utk" "${TEST_DIR}/${FIRMWARE_BIN}" table >uefi_contents.log 2>uefi_contents.err.log
  "${HOME}/go/bin/utk" "${TEST_DIR}/${FIRMWARE_BIN}" layout-table-full >>uefi_contents.log 2>>uefi_contents.err.log
  if mkdir uefi_contents; then
    "${HOME}/go/bin/utk" "${TEST_DIR}/${FIRMWARE_BIN}" extract "${TEST_DIR}/uefi_contents" 2>uefi_extract.err.log
  fi
}

main() {
  install_tools

  run_dmidecode
  show_amd_mmio

  run_lscpu
  run_lspci
  run_lsusb
  run_biosdecode
  dump_acpi
  gather_logs
  run_lshw
  run_lmsensors
  save_proc_info
  run_fwts
  run_sysbench
  coreboot_tests

  if [[ -f ${FIRMWARE_BIN} ]]; then
    run_psptool
    run_utk
  fi

  # clean up by deleting any zero length files
  find "${TEST_DIR}" -size 0 -type f -delete

  echo "File output is found in ${TEST_DIR}"
}

main
