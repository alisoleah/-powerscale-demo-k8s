FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    openssh-server \
    nfs-common \
    net-tools \
    iputils-ping \
    curl \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Create SSH run directory
RUN mkdir -p /run/sshd

# Enable root login and password auth for demo
RUN echo 'root:demo1234' | chpasswd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D"]
