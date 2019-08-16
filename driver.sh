#!/usr/bin/env bash

set -eu

setup_variables() {
  while [[ ${#} -ge 1 ]]; do
    case ${1} in
      "AR="*|"ARCH="*|"CC="*|"LD="*|"NM"=*|"OBJDUMP"=*|"REPO="*) export "${1?}" ;;
      "-c"|"--clean") cleanup=true ;;
      "-j"|"--jobs") shift; jobs=$1 ;;
      "-j"*) jobs=${1/-j} ;;
      "--lto") disable_lto=false ;;
      "-h"|"--help")
        cat usage.txt
        exit 0 ;;
    esac

    shift
  done

  # Turn on debug mode after parameters in case -h was specified
  set -x

  # torvalds/linux is the default repo if nothing is specified
  case ${REPO:=linux} in
    "common-"*)
      branch=android-${REPO##*-}
      tree=common
      url=https://android.googlesource.com/kernel/${tree} ;;
    "linux")
      owner=torvalds
      tree=linux ;;
    "linux-next")
      owner=next
      tree=linux-next ;;
    "4.4"|"4.9"|"4.14"|"4.19")
      owner=stable
      branch=linux-${REPO}.y
      tree=linux ;;
  esac
  [[ -z "${url:-}" ]] && url=git://git.kernel.org/pub/scm/linux/kernel/git/${owner}/${tree}.git

  # arm64 is the current default if nothing is specified
  SUBARCH=${ARCH:=arm64}
  case ${SUBARCH} in
    "arm32_v5")
      config=multi_v5_defconfig
      image_name=zImage
      qemu="qemu-system-arm"
      qemu_cmdline=( -machine palmetto-bmc
                     -no-reboot
                     -dtb "${tree}/arch/arm/boot/dts/aspeed-bmc-opp-palmetto.dtb"
                     -initrd "images/arm/rootfs.cpio" )
      export ARCH=arm
      export CROSS_COMPILE=arm-linux-gnueabi- ;;

    "arm32_v6")
      config=aspeed_g5_defconfig
      image_name=zImage
      qemu="qemu-system-arm"
      qemu_cmdline=( -machine romulus-bmc
                     -no-reboot
                     -dtb "${tree}/arch/arm/boot/dts/aspeed-bmc-opp-romulus.dtb"
                     -initrd "images/arm/rootfs.cpio" )
      export ARCH=arm
      export CROSS_COMPILE=arm-linux-gnueabi- ;;

    "arm32_v7")
      config=multi_v7_defconfig
      image_name=zImage
      qemu="qemu-system-arm"
      qemu_cmdline=( -machine virt
                     -no-reboot
                     -drive "file=images/arm/rootfs.ext4,format=raw,id=rootfs,if=none"
                     -device "virtio-blk-device,drive=rootfs"
                     -append "console=ttyAMA0 root=/dev/vda" )
      export ARCH=arm
      export CROSS_COMPILE=arm-linux-gnueabi- ;;

    "arm64")
      case ${REPO} in
        common-*) config=cuttlefish_defconfig ;;
        *) config=defconfig ;;
      esac
      image_name=Image.gz
      qemu="qemu-system-aarch64"
      qemu_cmdline=( -cpu cortex-a57
                     -drive "file=images/arm64/rootfs.ext4,format=raw,id=rootfs,if=none"
                     -device "virtio-blk-device,drive=rootfs"
                     -append "console=ttyAMA0 earlycon root=/dev/vda" )
      aavmf=/usr/share/AAVMF
      if [[ ${tree} != common && -f ${aavmf}/AAVMF_CODE.fd && -f ${aavmf}/AAVMF_VARS.fd ]]; then
        cp ${aavmf}/AAVMF_VARS.fd images/arm64
        qemu_cmdline+=( -drive "if=pflash,format=raw,readonly,file=${aavmf}/AAVMF_CODE.fd"
                        -drive "if=pflash,format=raw,file=images/arm64/AAVMF_VARS.fd" )
      fi
      export CROSS_COMPILE=aarch64-linux-gnu- ;;

    "mipsel")
      config=malta_defconfig
      image_name=vmlinux
      qemu="qemu-system-mipsel"
      qemu_cmdline=( -machine malta
                     -cpu 24Kf
                     -append "root=/dev/sda"
                     -drive "file=images/mipsel/rootfs.ext4,format=raw,if=ide" )
      export ARCH=mips
      export CROSS_COMPILE=mipsel-linux-gnu- ;;

    "ppc32")
      config=ppc44x_defconfig
      image_name=zImage
      qemu="qemu-system-ppc"
      qemu_ram=128m
      qemu_cmdline=( -machine bamboo
                     -append "console=ttyS0"
                     -no-reboot
                     -initrd "images/ppc32/rootfs.cpio" )
      export ARCH=powerpc
      export CROSS_COMPILE=powerpc-linux-gnu- ;;

    "ppc64")
      config=pseries_defconfig
      qemu="qemu-system-ppc64"
      image_name=vmlinux
      qemu_ram=1G
      qemu_cmdline=( -machine pseries
                     -vga none
                     -initrd "images/ppc64/rootfs.cpio" )
      export ARCH=powerpc
      export CROSS_COMPILE=powerpc64-linux-gnu- ;;

    "ppc64le")
      config=powernv_defconfig
      image_name=zImage.epapr
      qemu="qemu-system-ppc64"
      qemu_ram=2G
      qemu_cmdline=( -machine powernv
                     -device "ipmi-bmc-sim,id=bmc0"
                     -device "isa-ipmi-bt,bmc=bmc0,irq=10"
                     -L images/ppc64le/ -bios skiboot.lid
                     -initrd images/ppc64le/rootfs.cpio )
      export ARCH=powerpc
      export CROSS_COMPILE=powerpc64le-linux-gnu- ;;

    "x86_64")
      case ${REPO} in
        common-*)
          config=x86_64_cuttlefish_defconfig
          qemu_cmdline=( -append "console=ttyS0"
                         -initrd "images/x86_64/rootfs.cpio" ) ;;
        *)
          config=defconfig
          qemu_cmdline=( -drive "file=images/x86_64/rootfs.ext4,format=raw,if=virtio"
                         -append "console=ttyS0 root=/dev/vda" ) ;;
      esac
      ovmf=/usr/share/OVMF
      if [[ ${tree} != common && -f ${ovmf}/OVMF_CODE.fd && -f ${ovmf}/OVMF_VARS.fd ]]; then
        cp ${ovmf}/OVMF_VARS.fd images/x86_64
        qemu_cmdline+=( -drive "if=pflash,format=raw,readonly,file=${ovmf}/OVMF_CODE.fd"
                        -drive "if=pflash,format=raw,file=images/x86_64/OVMF_VARS.fd" )
      fi
      # Use KVM if the processor supports it (first part) and the KVM module is loaded (second part)
      [[ $(grep -c -E 'vmx|svm' /proc/cpuinfo) -gt 0 && $(lsmod 2>/dev/null | grep -c kvm) -gt 0 ]] && qemu_cmdline=( "${qemu_cmdline[@]}" -enable-kvm )
      image_name=bzImage
      qemu="qemu-system-x86_64" ;;

    # Unknown arch, error out
    *)
      echo "Unknown ARCH specified!"
      exit 1 ;;
  esac
  export ARCH=${ARCH}
}

check_dependencies() {
  # Check for existence of needed binaries
  command -v nproc
  command -v "${CROSS_COMPILE:-}"as
  command -v ${qemu}
  command -v timeout
  command -v unbuffer

  for readelf in llvm-readelf-9 llvm-readelf-8 llvm-readelf-7 llvm-readelf; do
    command -v ${readelf} &>/dev/null && break
  done

  # Check for LD, CC, and AR environmental variables
  # and print the version string of each. If CC and AR
  # don't exist, try to find them.
  # lld isn't ready for all architectures so it's just
  # simpler to fall back to GNU ld when LD isn't specified
  # to avoid architecture specific selection logic.

  "${LD:="${CROSS_COMPILE:-}"ld}" --version

  if [[ -z "${CC:-}" ]]; then
    for CC in clang-9 clang-8 clang-7 clang; do
      command -v ${CC} &>/dev/null && break
    done
  fi
  ${CC} --version 2>/dev/null || {
    set +x
    echo
    echo "Looks like ${CC} could not be found in PATH!"
    echo
    echo "Please install as recent a version of clang as you can from your distro or"
    echo "properly specify the CC variable to point to the correct clang binary."
    echo
    echo "If you don't want to install clang, you can either download AOSP's prebuilt"
    echo "clang [1] or build it from source [2] then add the bin folder to your PATH."
    echo
    echo "[1]: https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/"
    echo "[2]: https://github.com/ClangBuiltLinux/linux/wiki/Building-Clang-from-source"
    echo
    exit;
  }

  if [[ -z "${AR:-}" ]]; then
    for AR in llvm-ar-9 llvm-ar-8 llvm-ar-7 llvm-ar "${CROSS_COMPILE:-}"ar; do
      command -v ${AR} 2>/dev/null && break
    done
  fi
  check_ar_version
  ${AR} --version

  if [[ -z "${NM:-}" ]]; then
    for NM in llvm-nm-9 llvm-nm-8 llvm-nm-7 llvm-nm "${CROSS_COMPILE:-}"nm; do
      command -v ${NM} 2>/dev/null && break
    done
  fi

  if [[ -z "${OBJDUMP:-}" ]]; then
    for OBJDUMP in llvm-objdump-9 llvm-objdump-8 llvm-objdump-7 llvm-objdump "${CROSS_COMPILE:-}"objdump; do
      command -v ${OBJDUMP} 2>/dev/null && break
    done
  fi
}

# Optimistically check to see that the user has a llvm-ar
# with https://reviews.llvm.org/rL354044. If they don't,
# fall back to GNU ar and let them know.
check_ar_version() {
  if ${AR} --version | grep -q "LLVM" && \
     [[ $(${AR} --version | grep version | sed -e 's/.*LLVM version //g' -e 's/[[:blank:]]*$//' -e 's/\.//g' -e 's/svn//' ) -lt 900 ]]; then
    set +x
    echo
    echo "${AR} found but appears to be too old to build the kernel (needs to be at least 9.0.0)."
    echo
    echo "Please either update llvm-ar from your distro or build it from source!"
    echo
    echo "See https://github.com/ClangBuiltLinux/linux/issues/33 for more info."
    echo
    echo "Falling back to GNU ar..."
    echo
    AR=${CROSS_COMPILE:-}ar
    set -x
  fi
}

mako_reactor() {
  # https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/Documentation/kbuild/kbuild.txt
  time \
  KBUILD_BUILD_TIMESTAMP="Thu Jan  1 00:00:00 UTC 1970" \
  KBUILD_BUILD_USER=driver \
  KBUILD_BUILD_HOST=clangbuiltlinux \
  make -j"${jobs:-$(nproc)}" CC="${CC}" HOSTCC="${CC}" LD="${LD}" \
    HOSTLD="${HOSTLD:-ld}" AR="${AR}" NM="${NM}" OBJDUMP="${OBJDUMP}" "${@}"
}

apply_patches() {
  patches_folder=$1
  if [[ -d ${patches_folder} ]]; then
    git apply -v -3 "${patches_folder}"/*.patch
  else
    return 0
  fi
}

build_linux() {
  # Wrap CC in ccache if it is available (it's not strictly required)
  CC="$(command -v ccache) ${CC}"
  [[ ${LD} =~ lld ]] && HOSTLD=${LD}

  if [[ -d ${tree} ]]; then
    cd ${tree}
    git fetch --depth=1 ${url} ${branch:=master}
    git reset --hard FETCH_HEAD
  else
    git clone --depth=1 -b ${branch:=master} --single-branch ${url}
    cd ${tree}
  fi

  git show -s | cat

  llvm_all_folder="../patches/llvm-all"
  apply_patches "${llvm_all_folder}/kernel-all"
  apply_patches "${llvm_all_folder}/${REPO}/arch-all"
  apply_patches "${llvm_all_folder}/${REPO}/${SUBARCH}"
  llvm_version_folder="../patches/llvm-$(echo __clang_major__ | ${CC} -E -x c - | tail -n 1)"
  apply_patches "${llvm_version_folder}/kernel-all"
  apply_patches "${llvm_version_folder}/${REPO}/arch-all"
  apply_patches "${llvm_version_folder}/${REPO}/${SUBARCH}"

  # Only clean up old artifacts if requested, the Linux build system
  # is good about figuring out what needs to be rebuilt
  [[ -n "${cleanup:-}" ]] && mako_reactor mrproper
  mako_reactor ${config}
  # If we're using a defconfig, enable some more common config options
  # like debugging, selftests, and common drivers
  if [[ ${config} =~ defconfig ]]; then
    cat ../configs/common.config >> .config
    # Some torture test configs cause issues on x86_64
    [[ $ARCH != "x86_64" ]] && cat ../configs/tt.config >> .config
    # Disable ftrace on arm32: https://github.com/ClangBuiltLinux/linux/issues/35
    [[ $ARCH == "arm" ]] && ./scripts/config -d CONFIG_FTRACE
    # Disable LTO and CFI unless explicitly requested
    ${disable_lto:=true} && ./scripts/config -d CONFIG_LTO -d CONFIG_LTO_CLANG
  fi
  # Make sure we build with CONFIG_DEBUG_SECTION_MISMATCH so that the
  # full warning gets printed and we can file and fix it properly.
  ./scripts/config -e DEBUG_SECTION_MISMATCH
  mako_reactor olddefconfig &>/dev/null
  mako_reactor ${image_name}
  [[ $ARCH =~ arm ]] && mako_reactor dtbs
  ${readelf} --string-dump=.comment vmlinux

  cd "${OLDPWD}"
}

boot_qemu() {
  local kernel_image

  if [[ ${image_name} = "vmlinux" ]]; then
    kernel_image=${tree}/vmlinux
  else
    kernel_image=${tree}/arch/${ARCH}/boot/${image_name}
  fi

  test -e ${kernel_image}
  qemu=( timeout 2m unbuffer "${qemu}"
                             -m "${qemu_ram:=512m}"
                             "${qemu_cmdline[@]}"
                             -display none -serial mon:stdio
                             -kernel "${kernel_image}" )
  # For arm64, we want to test booting at both EL1 and EL2
  if [[ ${ARCH} = "arm64" ]]; then
    "${qemu[@]}" -machine virt
    "${qemu[@]}" -machine "virt,virtualization=true"
  else
    "${qemu[@]}"
  fi
}

setup_variables "${@}"
check_dependencies
build_linux
boot_qemu
