# How to create a dm-verity image

1. Download official RHEL ISO and build a CVM with `rhel9-dm-root.ks`:
```
ISO_PATH=RHEL-9.6.0-x86_64-dvd1.iso
KS_LOCATION=rhel9-dm-root.ks

virt-install --virt-type kvm --os-variant rhel9.0 --arch x86_64 --boot uefi --name rhel-uki --memory 8192 --location $ISO_PATH --disk bus=scsi,size=5 --initrd-inject=$KS_LOCATION --nographics --extra-args "console=ttyS0 inst.ks=file:/rhel9-dm-root.ks" --transient
```

2. Do custom modifications in the image

3. Define the following vars (available also with `osc-convert-upload.sh help`)
```
AZURE_RESOURCE_GROUP:       mandatory - az resource group where to create the gallery
AZURE_REGION:               optional  - az region where to create the gallery. Default: eastus
IMAGE_GALLERY_NAME:         optional  - az gallery name. Default: my_gallery
IMAGE_DEFINITION_NAME:      optional  - az image definition name. Default: podvm-image
IMAGE_DEFINITION_PUBLISHER: optional  - az image definition publisher. Default: dm-verity
IMAGE_DEFINITION_OFFER:     optional  - az image definition offer. Default: MyPublisher
IMAGE_DEFINITION_SKU:       optional  - az image definition sku. Default: My-PodVM
IMAGE_VERSION:              optional  - az image version. Default: My-PodVM
IMAGE_BLOB_NAME:            optional  - az image storage blob name. Default: 1.0.0
IMAGE_CERTIFICATE_DER:      optional  - certificate in DER format to upload in the gallery. Default: generate a new one
IMAGE_CERTIFICATE_PEM:      optional  - certificate in PEM format to upload in the gallery. Default: generate a new one
IMAGE_PRIVATE_KEY:          optional  - key to sign the verity cmdline addon. Default: generate a new one
AZURE_SB_TEMPLATE:          optional  - az deployment template to automatically fill. Default: ./azure-sb-template.json
AZURE_DEPLOYMENT_NAME:      optional  - az deployment name. Default: my-deployment
SB_CERT_NAME:               optional  - name of the secureboot certificate added into the gallery. Default: My custom certificate
VERITY_SCRIPT_LOCATION:     optional  - location of the verity.sh script. Default: ./verity.sh
NBD_DEV:                    optional  - nbd$NBD_DEV where to temporarily mount the disk. Default: 0
WORK_FOLDER:                optional  - where to create artifacts. Defaults to a temp folder in /tmp
```

4. Run `osc-convert-upload.sh` that internally calls `verity.sh` and `upload.sh`
```
RHEL_QCOW2=rhel_9.6-x86_64-cvm.qcow2

osc-convert-upload.sh $RHEL_QCOW2
```

5. Image will be available in the specified Azure image gallery. The script will print as last line the full Azure Image ID.