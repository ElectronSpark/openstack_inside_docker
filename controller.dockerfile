FROM ubuntu:20.04

ENV LOCAL_INT_IP="10.0.0.11"
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

WORKDIR /root
USER root

# install etcd
RUN apt install -y etcd
RUN apt install -y tini

# install nova
RUN apt install -y python3-openstackclient keystone glance placement-api nova-api \
nova-conductor nova-novncproxy nova-scheduler

# install neutron
RUN apt install -y neutron-server

RUN apt install -y vim iputils-ping tcpdump

WORKDIR /root
RUN apt autoclean -y & apt autoremove -y
ADD --chown=root:root controller_sql.sql /root/controller_sql.sql
ADD --chown=openstack:openstack admin_openrc /home/openstack/admin_openrc
ADD --chown=openstack:openstack demo_openrc /home/openstack/demo_openrc
ADD --chown=root:root controller_setup.sh /root/controller_setup.sh
ADD --chown=root:root config/openstack_dashboard/local_settings.py /root/local_settings.py
ADD --chown=root:root http://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img \
    /root/cirros-0.4.0-x86_64-disk.img