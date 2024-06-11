FROM ubuntu:20.04

ENV LOCAL_INT_IP="10.0.0.41"
ENV LOCAL_NETWORK_GATEWAY="10.0.0.15"
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
ENV CINDER_DBPASS="password"
ENV CINDER_PASS="password"

ENV OS_USERNAME="admin"
ENV OS_PASSWORD="${KEYSTONE_DBPASS}"
ENV OS_PROJECT_NAME="admin"
ENV OS_USER_DOMAIN_NAME="Default"
ENV OS_PROJECT_DOMAIN_NAME="Default"
ENV OS_AUTH_URL="http://controller:5000/v3"
ENV OS_IDENTITY_API_VERSION="3"

ENV CINDER_BLOCK_DEV_PATH="/dev/sdb"

# add openstack user
RUN apt update -y
RUN apt install -y sudo
RUN useradd -m -d /home/cinder --uid 1000 -s /bin/bash cinder
RUN useradd -m -d /home/openstack -s /bin/bash openstack
RUN echo 'cinder:password' | chpasswd
RUN echo 'openstack:password' | chpasswd
RUN echo 'root:password' | chpasswd
RUN usermod -aG sudo openstack
RUN usermod -aG sudo cinder
RUN echo 'openstack ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
RUN cp /usr/share/base-files/dot.profile /home/openstack/.profile
RUN cp /usr/share/base-files/dot.bashrc /home/openstack/.bashrc
RUN cp /usr/share/base-files/dot.profile /home/cinder/.profile
RUN cp /usr/share/base-files/dot.bashrc /home/cinder/.bashrc
RUN chown -R openstack:openstack /home/openstack
RUN chown -R cinder:cinder /home/cinder

# install packages
RUN apt install -y openssh-server openssh-client libssl-dev \
    openvswitch-switch-dpdk chrony crudini software-properties-common
RUN add-apt-repository cloud-archive:yoga -y

# configure NTP
RUN sed -i "/^pool .* iburst maxsources [0-9]$/d" /etc/chrony/chrony.conf
RUN echo "server controller iburst" >> /etc/chrony/chrony.conf
RUN service chrony restart

RUN apt install -y thin-provisioning-tools cinder-volume nfs-common

RUN apt install -y vim iputils-ping tcpdump

RUN apt install -y tini

WORKDIR /root
RUN apt autoclean -y & apt autoremove -y
ADD --chown=root:root block1_setup.sh /root/block1_setup.sh
ADD --chown=openstack:openstack admin_openrc /home/openstack/admin_openrc
ADD --chown=openstack:openstack demo_openrc /home/openstack/demo_openrc
