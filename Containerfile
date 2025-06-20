FROM registry.redhat.io/rhel9/rhel-bootc:latest@sha256:7350036340bf9e48dbeedea4ef0330e71d71e60e5f1a55ceabb88afea82efab7

# the following section replaces coco-components.sh

COPY scripts/coco/podvm/luks-scratch/etc/systemd/system/kata-agent.service.d/10-override.conf /etc/systemd/system/kata-agent.service.d/10-override.conf
COPY scripts/coco/podvm/luks-scratch/etc/systemd/system/luks-scratch.service /etc/systemd/system/luks-scratch.service
COPY scripts/coco/podvm/luks-scratch/usr/lib/repart.d/30-scratch.conf /usr/lib/repart.d/30-scratch.conf
COPY scripts/coco/podvm/luks-scratch/usr/local/sbin/format-scratch.sh /usr/local/sbin/format-scratch.sh

RUN chmod +x /usr/local/sbin/format-scratch.sh

COPY scripts/coco/podvm/pause-bundle.tar.gz /tmp/pause-bundle.tar.gz
COPY scripts/coco/podvm/podvm-binaries.tar.gz /tmp/podvm-binaries.tar.gz

COPY scripts/coco/podvm/podvm_maker.sh /tmp/podvm_maker.sh
RUN chmod +x /tmp/podvm_maker.sh && /tmp/podvm_maker.sh

