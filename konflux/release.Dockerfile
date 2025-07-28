FROM registry.access.redhat.com/ubi9-micro@sha256:233cce2df15dc7cd790f7f1ddbba5d4f59f31677c13a47703db3c2ca2fea67b6

ARG disk_image

COPY --from=disk_image /image/podvm.qcow2 /image/podvm.qcow2
