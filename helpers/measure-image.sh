#!/bin/bash

set -euo pipefail

export PODMAN_IGNORE_CGROUPSV1_WARNING

# Usage function
usage() {
	cat <<EOF
Usage: $(basename "$0") [-h] IMG
Usage: $(basename "$0") [-h] clean

Options:
    -h          Display this help message

Example:
    $(basename "$0") quay.io/redhat-user-workloads/ose-osc-tenant/osc-dm-verity-image:test
EOF
	exit 1
}

# Parse global options
while getopts "i:o:h" opt; do
	case ${opt} in
	h)
		usage
		;;
	\?)
		echo "Invalid option" >&2
		usage
		;;
	esac
done
shift $((OPTIND - 1))

check_package() {
	PACKAGE="edk2-ovmf"
	if dnf list installed "$PACKAGE" &>/dev/null; then
		echo "Package '$PACKAGE' is installed."
	else
		echo "Package '$PACKAGE' is NOT installed. Please install it first."
		echo "dnf install -y $PACKAGE"
		exit 1
	fi
}

prepare() {
	podman create --name podvm $PODVM_IMG
	podman cp podvm:/image/podvm.qcow2 .
	podman rm podvm

	mkdir -p measure
	cd measure
	# wget https://raw.githubusercontent.com/confidential-containers/cloud-api-adaptor/refs/heads/main/src/cloud-api-adaptor/hack/podvm-measure.sh
	cp ../podvm-measure.sh .
	chmod +x podvm-measure.sh
	cp /usr/share/edk2/ovmf/OVMF_CODE.fd .
	cd -
}

run_measurements() {
	cd measure
	./podvm-measure.sh swtpm &
	./podvm-measure.sh -i ../podvm.qcow2 -o ./OVMF_CODE.fd launch &
	./podvm-measure.sh wait
	./podvm-measure.sh scrape > ../measurements.json
	./podvm-measure.sh stop
	jq -e . ../measurements.json
	cd -
	rm -rf measure
}

cleanup() {
	rm -rf podvm.qcow2 measurements.json
}

# Main command dispatch
main() {
	[[ $# -lt 1 ]] && usage

	PODVM_IMG=$1

	if [ "$PODVM_IMG" == "clean" ]; then
		echo "Clean up artifacts"
		cleanup
		exit 0
	fi

	check_package
	prepare
	run_measurements
}

main "$@"