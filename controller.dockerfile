FROM ubuntu:20.04

ENV LOCAL_INT_IP="10.100.0.11"


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
    chrony crudini software-properties-common
RUN add-apt-repository cloud-archive:yoga -y

# configure NTP
RUN echo "allow ${LOCAL_NETWORK}" >> /etc/chrony/chrony.conf
RUN service chrony restart

# install message queue
RUN apt install -y rabbitmq-server

# install memcached
RUN apt install -y python3-memcache

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

# install cinder
RUN apt -y install cinder-api cinder-scheduler

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