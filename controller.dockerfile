FROM ubuntu:20.04

ENV LOCAL_INT_IP="10.0.0.11"
ENV LOCAL_NETWORK_GATEWAY="10.0.0.1"
ENV LOCAL_NETWORK_PREFIX="10.0.0.0"
ENV LOCAL_NETWORK_PREFIX_LENGTH="24"
ENV LOCAL_NETWORK="${LOCAL_NETWORK_PREFIX}/${LOCAL_NETWORK_PREFIX_LENGTH}"
ENV TUNNEL_INTERFACE_NAME="gre0"
ENV PROVIDER_INTERFACE_DEVICE="eth0"
ENV PROVIDER_INTERFACE_NAME="br-provider"

ENV DEMO_PASS="password"
ENV DATABASE_PASS="password"
ENV RABBIT_PASS="password"
ENV KEYSTONE_DBPASS="password"
ENV KEYSTONE_PASS="password"
ENV GLANCE_DBPASS="password"
ENV GLANCE_PASS="password"
ENV PLACEMENT_DBPASS="password"
ENV PLACEMENT_PASS="password"
ENV NOVA_DBPASS="password"
ENV NOVA_PASS="password"
ENV NOVA_METADATA_SECRET="secret"
ENV NEUTRON_DBPASS="password"
ENV NEUTRON_PASS="password"

ENV OS_USERNAME="admin"
ENV OS_PASSWORD="${KEYSTONE_DBPASS}"
ENV OS_PROJECT_NAME="admin"
ENV OS_USER_DOMAIN_NAME="Default"
ENV OS_PROJECT_DOMAIN_NAME="Default"
ENV OS_AUTH_URL="http://controller:5000/v3"
ENV OS_IDENTITY_API_VERSION="3"


# add openstack user
RUN apt update -y
RUN apt install -y sudo
RUN useradd -m -d /home/openstack -s /bin/bash openstack
RUN echo 'openstack:password' | chpasswd
RUN echo 'root:password' | chpasswd
RUN usermod -aG sudo openstack
RUN echo 'openstack ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
RUN cp /usr/share/base-files/dot.profile /home/openstack/.profile
RUN cp /usr/share/base-files/dot.bashrc /home/openstack/.bashrc
RUN chown -R openstack:openstack /home/openstack

SHELL ["/bin/bash", "-c"]

# install packages
RUN apt install -y openssh-server openssh-client libssl-dev \
    openvswitch-switch-dpdk chrony crudini software-properties-common
RUN add-apt-repository cloud-archive:yoga -y

# configure NTP
RUN echo "allow ${LOCAL_NETWORK}" >> /etc/chrony/chrony.conf
RUN service chrony restart

# configure mysql database
RUN apt install -y mariadb-server python3-pymysql

# install message queue
RUN apt install -y rabbitmq-server

# install memcached
RUN apt install -y memcached python3-memcache
RUN sed -i "s/^-l 127.0.0.1$/-l ${LOCAL_INT_IP}/g" /etc/memcached.conf

WORKDIR /root
USER root

# install etcd
RUN apt install -y etcd

# install nova
RUN apt install -y python3-openstackclient keystone glance placement-api nova-api \
nova-conductor nova-novncproxy nova-scheduler

# install neutron
RUN apt install -y neutron-server neutron-plugin-ml2 neutron-dhcp-agent \
neutron-l3-agent neutron-metadata-agent

# RUN apt install -y neutron-linuxbridge-agent
RUN apt install -y neutron-openvswitch-agent

RUN apt install -y vim iputils-ping tcpdump

# libvirt related
RUN apt-get -y install bridge-utils dmidecode dnsmasq ebtables \
    iproute2 iptables 
RUN apt install -y libvirt-clients libvirt-daemon-system \
    ovmf qemu-efi qemu-kvm tini qemu

RUN sed -i '/^#stdio_handler/ a\stdio_handler = "file"' /etc/libvirt/qemu.conf

COPY config/pools/* /etc/libvirt/storage/
COPY config/networks/* /etc/libvirt/qemu/networks/
RUN mkdir -p /etc/libvirt/storage/autostart /etc/libvirt/qemu/networks/autostart && \
    for pool in /etc/libvirt/storage/*.xml; do \
        ln -sf "../${pool##*/}" /etc/libvirt/storage/autostart/; \
    done && \
    for net in /etc/libvirt/qemu/networks/*.xml; do \
        ln -sf "../${net##*/}" /etc/libvirt/qemu/networks/autostart/; \
    done

ADD --chown=root:root controller_sql.sql /root/controller_sql.sql
ADD --chown=openstack:openstack admin_openrc /home/openstack/admin_openrc
ADD --chown=openstack:openstack demo_openrc /home/openstack/demo_openrc
ADD --chown=root:root controller_setup.sh /root/controller_setup.sh
ADD --chown=root:root config/openstack_dashboard/local_settings.py /root/local_settings.py
# WORKDIR /home/openstack
# USER openstack
