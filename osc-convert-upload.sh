#!/bin/bash
set -e

# required packages: jq, az, openssl, qemu-img, sbsigntools

INPUT_IMAGE=$1

here=`pwd`
SCRIPT_FOLDER=$(dirname $0)
SCRIPT_FOLDER=$(realpath $SCRIPT_FOLDER)

PODVM_BINARY_DEF=registry.redhat.io/openshift-sandboxed-containers/osc-podvm-payload-rhel9:1.9.0
PODVM_BINARY_LOCATION_DEF=/podvm-binaries.tar.gz
PAUSE_BUNDLE_DEF=quay.io/confidential-containers/podvm-binaries-ubuntu-amd64:v0.13.0
PAUSE_BUNDLE_LOCATION_DEF=/pause-bundle.tar.gz

function local_help()
{
    echo "Usage: $0 <INPUT_IMAGE>"
    echo "Usage: $0 help"
    echo ""
    echo "The purpose of this script is to take a disk and:"
    echo "1. create new certificates for the new image secureboot db, if not provided"
    echo "2. call verity script to verity protect the root disk"
    echo "3. install coco guest components in the disk"
    echo "4. call upload script to create a dm-verity vhd and upload it to Azure"
    echo ""
    echo "Options (define them as variable):"
    echo "IMAGE_CERTIFICATE_DER:      optional  - certificate in DER format to upload in the gallery. Default: generate a new one"
    echo "IMAGE_CERTIFICATE_PEM:      optional  - certificate in PEM format to upload in the gallery. Default: generate a new one"
    echo "IMAGE_PRIVATE_KEY:          optional  - key to sign the verity cmdline addon. Default: generate a new one"
    echo "SB_CERT_NAME:               optional  - name of the secureboot certificate added into the gallery. Default: My custom certificate"
    echo "WORK_FOLDER:                optional  - where to create artifacts. Defaults to a temp folder in /tmp"
    echo ""
    echo "Verity options (define them as variable):"
    echo "RESIZE_DISK:                optional  - whether to increase disk size by 10% to accomodate verity partition. Default: yes"
    echo "NBD_DEV:                    optional  - nbd\$NBD_DEV where to temporarily mount the disk. Default: 0"
    echo "VERITY_SCRIPT_LOCATION:     optional  - location of the verity.sh script. Default: $SCRIPT_FOLDER/verity.sh"
    echo "ROOT_PARTITION_UUID:        optional - UUID to find the root. Defaults to the x86_64 part type"
    echo ""
    echo "CoCo guest options (define them as variable):"
    echo ""
    echo "ARTIFACTS_FOLDER:           optional  - where the podvm binaries and pause bundle are. Default $SCRIPT_FOLDER/podvm"
    echo "PODVM_BINARY:               optional - registry containing podvm binary. Default:$PODVM_BINARY_DEF "
    echo "PODVM_BINARY_LOCATION:      optional - location in container containing podvm binary. Default: $PODVM_BINARY_LOCATION_DEF"
    echo "PAUSE_BUNDLE:               optional - registry containing pause bundle. Default: $PAUSE_BUNDLE_DEF"
    echo "PAUSE_BUNDLE_LOCATION:      optional - location in container containing pause bundle. Default: $PAUSE_BUNDLE_LOCATION_DEF"
    echo "ROOT_PASSWORD:              optional - set root's password. Default: disabled"
    echo ""
    echo "Upload options (define them as variable):"
    echo "AZURE_RESOURCE_GROUP:       mandatory - az resource group where to create the gallery"
    echo "AZURE_REGION:               optional  - az region where to create the gallery. Default: eastus"
    echo "IMAGE_GALLERY_NAME:         optional  - az gallery name. Default: my_gallery"
    echo "IMAGE_DEFINITION_NAME:      optional  - az image definition name. Default: podvm-image"
    echo "IMAGE_DEFINITION_PUBLISHER: optional  - az image definition publisher. Default: dm-verity"
    echo "IMAGE_DEFINITION_OFFER:     optional  - az image definition offer. Default: MyPublisher"
    echo "IMAGE_DEFINITION_SKU:       optional  - az image definition sku. Default: My-PodVM"
    echo "IMAGE_VERSION:              optional  - az image version. Default: My-PodVM"
    echo "IMAGE_BLOB_NAME:            optional  - az image storage blob name. Default: 1.0.0"
    echo "AZURE_SB_TEMPLATE:          optional  - az deployment template to automatically fill. Default: $SCRIPT_FOLDER/azure-sb-template.json"
    echo "AZURE_DEPLOYMENT_NAME:      optional  - az deployment name. Default: my-deployment"
    echo "UPLOAD_SCRIPT_LOCATION:     optional  - location of the upload-azure.sh script. Default: $SCRIPT_FOLDER/upload-azure.sh"
    echo ""
    echo "Exiting"
}

if [ -z ${INPUT_IMAGE} ]; then
    local_help
    exit 1
fi

if [[ $INPUT_IMAGE == "help" ]]; then
    local_help
    exit 0
fi

if [ -z ${AZURE_RESOURCE_GROUP} ]; then
    echo "AZURE_RESOURCE_GROUP is unset. Set it with AZURE_RESOURCE_GROUP=your-rg"
    echo "Exiting"
    exit 1
fi

INPUT_IMAGE=$(realpath "$INPUT_IMAGE")

UPLOAD_SCRIPT_LOCATION=${UPLOAD_SCRIPT_LOCATION:-"$SCRIPT_FOLDER/upload-azure.sh"}
UPLOAD_SCRIPT_LOCATION=$(realpath "$UPLOAD_SCRIPT_LOCATION")

IMAGE_CERTIFICATE_DER=${IMAGE_CERTIFICATE_DER:-""}
IMAGE_CERTIFICATE_PEM=${IMAGE_CERTIFICATE_PEM:-""}
IMAGE_PRIVATE_KEY=${IMAGE_PRIVATE_KEY:-""}
SB_CERT_NAME=${SB_CERT_NAME:-"My custom certificate"}

VERITY_SCRIPT_LOCATION=${VERITY_SCRIPT_LOCATION:-"$SCRIPT_FOLDER/verity.sh"}
VERITY_SCRIPT_LOCATION=$(realpath "$VERITY_SCRIPT_LOCATION")

COCO_SCRIPT_LOCATION=${COCO_SCRIPT_LOCATION:-"$SCRIPT_FOLDER/coco-components.sh"}
COCO_SCRIPT_LOCATION=$(realpath "$COCO_SCRIPT_LOCATION")

function print_params()
{
    echo ""
    echo "WORK_FOLDER: $WORK_FOLDER"
    echo "INPUT_IMAGE: $INPUT_IMAGE"
    echo "IMAGE_CERTIFICATE_DER: $IMAGE_CERTIFICATE_DER"
    echo "IMAGE_CERTIFICATE_PEM: $IMAGE_CERTIFICATE_PEM"
    echo "IMAGE_PRIVATE_KEY: $IMAGE_PRIVATE_KEY"
    echo "SB_CERT_NAME: $SB_CERT_NAME"
    echo "VERITY_SCRIPT_LOCATION: $VERITY_SCRIPT_LOCATION"
    echo "UPLOAD_SCRIPT_LOCATION: $UPLOAD_SCRIPT_LOCATION"
    echo "COCO_SCRIPT_LOCATION: $COCO_SCRIPT_LOCATION"
    echo ""
}

function error_exit() {
    echo "$1" 1>&2
    exit 1
}

# Function to get format of the podvm image
# Input: podvm image path
# Use qemu-img info to get the image info
# export the image format as PODVM_IMAGE_FORMAT
function get_podvm_image_format() {
    image_path="${1}"
    echo "Getting format of the PodVM image: ${image_path}"

    # jq -r when you want to output plain strings without quotes. Otherwise the string will be quoted
    PODVM_IMAGE_FORMAT=$(qemu-img info --output json "${image_path}" | jq -r '.format') ||
        error_exit "Failed to get podvm image info"

    # vhd images are also raw format. So check the file extension. It's crude but for
    # now it's good enough hopefully
    if [[ "${image_path}" == *.vhd ]] && [[ "${PODVM_IMAGE_FORMAT}" == "raw" ]]; then
        PODVM_IMAGE_FORMAT="vhd"
    fi

    echo "PodVM image format for ${image_path}: ${PODVM_IMAGE_FORMAT}"
    export PODVM_IMAGE_FORMAT
}

function get_input_img_format() {

    get_podvm_image_format $1

    case "${PODVM_IMAGE_FORMAT}" in
    "qcow2")
        DISK_FORMAT="qcow2"
        ;;
    "raw")
        DISK_FORMAT="raw"
        ;;
    "vhd")
        DISK_FORMAT="vpc"
        ;;
    *)
        error_exit "Invalid podvm image format: ${PODVM_IMAGE_FORMAT}"
        ;;
    esac

    export DISK_FORMAT
}

function check_certificates_input()
{
    if [[ -z "${IMAGE_PRIVATE_KEY}" && (-n "${IMAGE_CERTIFICATE_PEM}" || -n "${IMAGE_CERTIFICATE_DER}") ]]; then
        echo "Error: IMAGE_PRIVATE_KEY not defined but IMAGE_CERTIFICATE_* is."
        echo "Exiting."
        exit 1
    elif [[ -n "${IMAGE_PRIVATE_KEY}" && -z "${IMAGE_CERTIFICATE_PEM}" && -z "${IMAGE_CERTIFICATE_DER}" ]]; then
        echo "Error: IMAGE_PRIVATE_KEY defined but IMAGE_CERTIFICATE_* is not."
        echo "Exiting."
        exit 1
    fi
}

function create_sb_cert()
{
    IMAGE_CERTIFICATE_DER=$WORK_FOLDER/my_db.cer
    IMAGE_CERTIFICATE_PEM=$WORK_FOLDER/my_db.pem
    IMAGE_PRIVATE_KEY=$WORK_FOLDER/my_db.key
    openssl req -quiet -newkey rsa:4096 -nodes -keyout $IMAGE_PRIVATE_KEY -new -x509 -sha256 -subj "/CN=$SB_CERT_NAME/" --outform DER -out $IMAGE_CERTIFICATE_DER
    echo "IMAGE_CERTIFICATE_* vars not defined, creating a new certificate cer,der and key"
    openssl x509 -inform DER -in $IMAGE_CERTIFICATE_DER -outform PEM -out $IMAGE_CERTIFICATE_PEM
}

function handle_ctrlc()
{
    cd $here
    exit 0
}

WORK_FOLDER=${WORK_FOLDER:-$(mktemp -d)}
WORK_FOLDER=$(realpath "$WORK_FOLDER")

print_params

cd $WORK_FOLDER

storage_account_created=0

trap handle_ctrlc SIGINT
trap handle_ctrlc EXIT

check_certificates_input
create_sb_cert
echo ""
echo "IMAGE_CERTIFICATE_DER $IMAGE_CERTIFICATE_DER"
echo "IMAGE_CERTIFICATE_PEM $IMAGE_CERTIFICATE_PEM"
echo "IMAGE_PRIVATE_KEY $IMAGE_PRIVATE_KEY"
echo ""

get_input_img_format $INPUT_IMAGE

echo "Applying CoCo guest components..."
export PODVM_BINARY
export PODVM_BINARY_LOCATION
export PAUSE_BUNDLE
export PAUSE_BUNDLE_LOCATION
export ARTIFACTS_FOLDER
export SCRIPT_FOLDER
export $ROOT_PASSWORD
$COCO_SCRIPT_LOCATION $INPUT_IMAGE
echo ""

echo "Calling verity..."
export DISK_FORMAT
export RESIZE_DISK
export SB_PRIVATE_KEY=$IMAGE_PRIVATE_KEY
export SB_CERTIFICATE=$IMAGE_CERTIFICATE_PEM
export NBD_DEV
export VERITY_FOLDER=$WORK_FOLDER
export ROOT_PARTITION_UUID
$VERITY_SCRIPT_LOCATION $INPUT_IMAGE
echo ""

echo "Uploading to Azure..."
export AZURE_RESOURCE_GROUP
export AZURE_REGION
export IMAGE_GALLERY_NAME
export IMAGE_DEFINITION_NAME
export IMAGE_DEFINITION_PUBLISHER
export IMAGE_DEFINITION_OFFER
export IMAGE_DEFINITION_SKU
export IMAGE_VERSION
export IMAGE_BLOB_NAME
export SCRIPT_FOLDER # needed if AZURE_SB_TEMPLATE is undefined
export AZURE_SB_TEMPLATE
export AZURE_DEPLOYMENT_NAME
export WORK_FOLDER
$UPLOAD_SCRIPT_LOCATION $INPUT_IMAGE $IMAGE_CERTIFICATE_DER

cd -
