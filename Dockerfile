FROM ubuntu:16.04

ARG ONEPASS=onepassword
ARG SSHPATH=./id_rsa*

RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && apt-get install -y wget apt-transport-https && \
    wget -q -O- https://downloads.opennebula.org/repo/repo.key | apt-key add - && \
    echo "deb https://downloads.opennebula.org/repo/5.8/Ubuntu/16.04 stable opennebula" > /etc/apt/sources.list.d/opennebula.list && \
    apt-get update && \
    apt-get install -y opennebula opennebula-sunstone opennebula-gate opennebula-flow opennebula-node \
    gcc libmysqlclient-dev ruby-dev make sudo lsb-release net-tools \
    vim xml-twig-tools jq qemu-kvm openssh-server -y && \
    /usr/share/one/install_gems --yes

COPY ${SSHPATH} /var/lib/one/.ssh/

COPY entrypoint.sh /

ADD init.tar /etc/init.d/

RUN echo "oneadmin:${ONEPASS}" > /var/lib/one/.one/one_auth

ENTRYPOINT [ "/entrypoint.sh" ]