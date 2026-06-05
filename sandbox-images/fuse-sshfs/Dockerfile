FROM ghcr.io/nvidia/openshell-community/sandboxes/base:latest

USER root
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      sshfs fuse3 sshpass openssh-client netcat-openbsd iputils-ping procps \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /home/sandbox/.ssh /mnt/remote \
 && chown -R sandbox:sandbox /home/sandbox /mnt/remote \
 && printf 'Host *\n  StrictHostKeyChecking no\n  UserKnownHostsFile /dev/null\n' > /home/sandbox/.ssh/config \
 && chown sandbox:sandbox /home/sandbox/.ssh/config \
 && chmod 600 /home/sandbox/.ssh/config \
 && echo user_allow_other >> /etc/fuse.conf

USER sandbox
