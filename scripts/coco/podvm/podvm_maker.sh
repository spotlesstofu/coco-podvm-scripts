#! /bin/bash

dnf config-manager --add-repo=https://mirror.stream.centos.org/9-stream/AppStream/x86_64/os/ && dnf install -y --nogpgcheck afterburn e2fsprogs && dnf clean all && dnf config-manager --set-disabled "*centos*"
cat <<EOF > /etc/systemd/system/afterburn-checkin.service
[Unit]
ConditionKernelCommandLine=

[Service]
ExecStart=
ExecStart=-/usr/bin/afterburn --provider=azure --check-in

[Install]
WantedBy=multi-user.target
EOF
systemctl enable afterburn-checkin.service

tar -xzvf /tmp/podvm-binaries.tar.gz -C /
tar -xzvf /tmp/pause-bundle.tar.gz -C /
# set luks
# TODO: move to payload ?
# tar -xzvf /tmp/luks-config.tar.gz -C /

# fixes a failure of the podns@netns service
semanage fcontext -a -t bin_t /usr/sbin/ip && restorecon -v /usr/sbin/ip

systemctl enable /etc/systemd/system/luks-scratch.service

# Configuration to make PCR values to be printed at boot
cat <<EOF > /usr/libexec/gen-issue
#!/usr/bin/env bash

set -euo pipefail

if ! tpm2_pcrread sha256:0 > /dev/null 2>&1; then
   echo "No vTPM detected"
   exit 0
fi

mkdir -p /run/issue.d

rm -f /etc/issue.net
rm -f /etc/issue
{
  echo "Detected vTPM PCR values:"
  /usr/bin/tpm2_pcrread sha256:all
  echo
} > /run/issue.d/30-pcrs.issue
EOF

# this will allow /run/issue and /run/issue.d to take precedence
mv /etc/issue.d /usr/lib/issue.d || true
rm -f /etc/issue.net
rm -f /etc/issue

chmod +x /usr/libexec/gen-issue
cat  <<EOF > /etc/systemd/system/gen-issue.service
[Unit]
Description=Generate issue to print to serial console at startup

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/libexec/gen-issue

[Install]
WantedBy=multi-user.target
EOF
systemctl enable gen-issue.service

# configuration to extend PCR8 with the initdata.digest
mkdir -p /etc/systemd/system/process-user-data.service.d/
cat  <<EOF > /etc/systemd/system/process-user-data.service.d/10-override.conf
[Service]
# The digest is a string in hex representation, we truncate it to a 32 bytes hex string
ExecStartPost=-/bin/bash -c 'tpm2_pcrextend 8:sha256=\$(head -c64 /run/peerpod/initdata.digest)'
EOF
