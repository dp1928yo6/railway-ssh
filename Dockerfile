FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PIP_BREAK_SYSTEM_PACKAGES=1

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      openssh-server ca-certificates \
      bash less nano vim-tiny curl wget git unzip zip \
      procps psmisc tmux htop iproute2 iputils-ping net-tools dnsutils \
      python3 python3-pip sudo \
 && rm -rf /var/lib/apt/lists/* \
 && rm -f /etc/ssh/ssh_host_* \
 && mkdir -p /run/sshd /root/.ssh \
 && chmod 700 /root/.ssh \
 && usermod -p '*' root

COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN sed -i 's/\r$//' /etc/ssh/sshd_config /usr/local/bin/entrypoint.sh \
 && chmod 644 /etc/ssh/sshd_config \
 && chmod 755 /usr/local/bin/entrypoint.sh

WORKDIR /root
EXPOSE 22

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
