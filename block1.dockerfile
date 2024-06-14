FROM ubuntu:20.04

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
RUN apt install -y crudini
RUN apt install -y software-properties-common
RUN add-apt-repository cloud-archive:yoga -y

# configure NTP
# RUN apt install -y chrony 
# RUN sed -i "/^pool .* iburst maxsources [0-9]$/d" /etc/chrony/chrony.conf
# RUN echo "server os-controller iburst" >> /etc/chrony/chrony.conf
# RUN service chrony restart

RUN apt install -y thin-provisioning-tools cinder-volume nfs-common

# install mysql client
RUN apt install -y python3-pymysql

RUN apt install -y vim
RUN apt install -y net-tools
RUN apt install -y iputils-ping tcpdump iproute2

RUN apt install -y tini

RUN apt install -y netcat

ADD --chown=root:root block1_setup.sh /root/block1_setup.sh
ADD --chown=openstack:openstack admin_openrc /home/openstack/admin_openrc
ADD --chown=openstack:openstack demo_openrc /home/openstack/demo_openrc
ADD --chown=root:root ./config/profile.d/99-generate_env.sh /etc/profile.d/99-generate_env.sh

WORKDIR /root
USER root
RUN apt autoclean -y & apt autoremove -y
RUN echo "source /etc/profile.d/99-generate_env.sh" >> /etc/bash.bashrc
CMD ["tini", "--", "/root/block1_setup.sh"]