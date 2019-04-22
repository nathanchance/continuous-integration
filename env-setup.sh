#!/usr/bin/env bash
# Configure our Docker container during Travis builds

# Show all commands and exit upon failure
set -eux

# By default, Travis's ccache size is around 500MB. We'll
# start with 2GB just to see how it plays out.
ccache -M 2G

# Enable compression so that we can have more objects in
# the cache (9 is most compressed, 6 is default)
ccache --set-config=compression=true
ccache --set-config=compression_level=9

# Set the cache directory to /travis/.ccache, which we've
# bind mounted during 'docker create' so that we can keep
# this cached across builds
ccache --set-config=cache_dir=/travis/.ccache

# Clear out the stats so we actually know the cache stats
ccache -z

# Ensure that GNU tools are not available when using LLVM tools
function remove() {
    mapfile -t files < <(type -ap "${@}")
    for file in "${files[@]}"; do rm -vf "${file}"; done
}

case ${ARCH:=arm64} in
    arm32*) CROSS_COMPILE=arm-linux-gnueabi- ;;
    arm64) CROSS_COMPILE=aarch64-linux-gnu- ;;
    ppc32) CROSS_COMPILE=powerpc-linux-gnu- ;;
    ppc64le) CROSS_COMPILE=powerpc64le-linux-gnu- ;;
esac

# Remove the target's tools
remove "${CROSS_COMPILE:-}"ar
remove "${CROSS_COMPILE:-}"gcc
[[ ${LD:-} =~ ld.lld ]] && remove ${CROSS_COMPILE:-}{ld,ld.bfd,ld.gold}
remove "${CROSS_COMPILE:-}"objcopy
remove "${CROSS_COMPILE:-}"objdump
remove "${CROSS_COMPILE:-}"nm
remove "${CROSS_COMPILE:-}"readelf
remove "${CROSS_COMPILE:-}"strip

# Remove the host tools if we are cross compiling
if [[ -n ${CROSS_COMPILE:-} ]]; then
    remove ar
    remove gcc
    [[ ${LD:-} =~ ld.lld ]] && remove {ld,ld.bfd,ld.gold}
    remove objcopy
    remove objdump
    remove nm
    remove readelf
    remove strip
fi

# Ensure that we always exit cleanly because a bash script's
# exit code is always the code of the last command
exit 0
