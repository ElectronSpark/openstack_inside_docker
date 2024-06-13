FROM ubuntu:20.04

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

# install packages
RUN apt install -y openssh-server openssh-client libssl-dev
RUN apt install -y crudini
RUN apt install -y software-properties-common
RUN add-apt-repository cloud-archive:yoga -y

# configure NTP
# RUN apt install -y chrony 
# RUN sed -i "/^pool .* iburst maxsources [0-9]$/d" /etc/chrony/chrony.conf
# RUN echo "server controller iburst" >> /etc/chrony/chrony.conf
# RUN service chrony restart

# install memcached
RUN apt install -y python3-memcache

# install mysql client
RUN apt install -y python3-pymysql

# install etcd
RUN apt install -y etcd
RUN apt install -y tini

# install nova
RUN apt install -y python3-openstackclient keystone glance placement-api nova-api \
nova-conductor nova-novncproxy nova-scheduler

# install placement client
RUN apt install -y python3-osc-placement

# install neutron
RUN apt install -y neutron-server

# install cinder
RUN apt -y install cinder-api cinder-scheduler

RUN apt install -y iputils-ping tcpdump
RUN apt install -y net-tools
RUN apt install -y vim

ADD --chown=root:root controller_sql.sql /root/controller_sql.sql
ADD --chown=openstack:openstack admin_openrc /home/openstack/admin_openrc
ADD --chown=openstack:openstack demo_openrc /home/openstack/demo_openrc
ADD --chown=root:root ./controller_setup.sh /root/controller_setup.sh
ADD --chown=root:root config/openstack_dashboard/local_settings.py /root/local_settings.py
ADD --chown=root:root http://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img \
    /root/cirros-0.4.0-x86_64-disk.img
ADD --chown=root:root ./config/profile.d/99-generate_env.sh /etc/profile.d/99-generate_env.sh

WORKDIR /root
USER root
RUN apt autoclean -y & apt autoremove -y
RUN echo "source /etc/profile.d/99-generate_env.sh" >> /etc/bash.bashrc
CMD ["tini", "--", "/root/controller_setup.sh"]