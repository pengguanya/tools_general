#!/bin/bash

# Default number of kernels to keep
NUM_TO_KEEP=3

# Function to display usage information
usage() {
    echo "Usage: $0 [-n NUM_TO_KEEP] [exec]"
    echo "  -n NUM_TO_KEEP   Number of latest kernels to keep (default is 3)"
    echo "  exec             Execute the removal of old kernels"
    echo "Example:"
    echo "  sudo $0 -n 3 exec"
}

# Parse command-line arguments
EXECUTE=0
POSITIONAL=()

while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -n)
    NUM_TO_KEEP="$2"
    shift # past argument
    shift # past value
    ;;
    exec)
    EXECUTE=1
    shift # past argument
    ;;
    -h|--help)
    usage
    exit 0
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done

set -- "${POSITIONAL[@]}" # restore positional parameters

echo "Number of kernels to keep: $NUM_TO_KEEP"

# Get the current running kernel version
CURRENT_KERNEL=$(uname -r)
echo "Current kernel: $CURRENT_KERNEL"

# Get the list of installed kernel versions
INSTALLED_KERNEL_VERSIONS=$(dpkg -l | awk '/^ii/ {print $2}' | grep -E 'linux-image-[0-9]+' | sed 's/linux-image-//' | sort -V | uniq)

# Ensure the current kernel is in the installed kernels list
if ! echo "$INSTALLED_KERNEL_VERSIONS" | grep -qw "$CURRENT_KERNEL"; then
   echo "Current kernel $CURRENT_KERNEL is not in the installed kernel list!"
   exit 1
fi

# Get the list of kernel versions to keep
KERNELS_TO_KEEP=$(echo "$INSTALLED_KERNEL_VERSIONS" | tail -n "$NUM_TO_KEEP" | sort -V | uniq)

# Ensure the current kernel is included in the kernels to keep
if ! echo "$KERNELS_TO_KEEP" | grep -qw "$CURRENT_KERNEL"; then
   KERNELS_TO_KEEP=$(echo -e "$KERNELS_TO_KEEP\n$CURRENT_KERNEL" | sort -V | uniq)
fi

echo "Kernels to keep:"
echo "$KERNELS_TO_KEEP"

# Get the list of kernel versions to remove
KERNELS_TO_REMOVE=$(comm -23 <(echo "$INSTALLED_KERNEL_VERSIONS") <(echo "$KERNELS_TO_KEEP"))

echo "Kernels to remove:"
echo "$KERNELS_TO_REMOVE"

# Get the list of packages to remove for the kernels to remove
OLD_KERNEL_PACKAGES=""
for KVER in $KERNELS_TO_REMOVE; do
  PACKAGES=$(dpkg -l | awk '/^ii/ {print $2}' | grep -E "linux-(image|headers|modules|modules-extra)-$KVER")
  OLD_KERNEL_PACKAGES="$OLD_KERNEL_PACKAGES $PACKAGES"
done

echo "Packages to remove:"
echo "$OLD_KERNEL_PACKAGES"

# Execute removal if 'exec' parameter is provided
if [ "$EXECUTE" -eq 1 ]; then
    for PACKAGE in $OLD_KERNEL_PACKAGES; do
        echo "Removing $PACKAGE"
        apt purge -y "$PACKAGE"
    done
    echo "Old kernels have been removed."
else
    echo "Dry run completed."
    echo "If all looks good, run the script again with 'exec' to remove the old kernels."
    echo "Example:"
    echo "  sudo $0 -n $NUM_TO_KEEP exec"
fi
