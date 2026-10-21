#!/bin/bash
# Bootstrap the Ansible management user. Idempotent; runs on every boot.
set -eu

id ansible >/dev/null 2>&1 || useradd --create-home --shell /bin/bash ansible

install -d -m 700 -o ansible -g ansible /home/ansible/.ssh
echo '${ssh_public_key}' > /home/ansible/.ssh/authorized_keys
chown ansible:ansible /home/ansible/.ssh/authorized_keys
chmod 600 /home/ansible/.ssh/authorized_keys

echo 'ansible ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-ansible
chmod 440 /etc/sudoers.d/90-ansible
