FROM ubuntu:20.04

COPY <<EOF /etc/profile.d/generate_env.sh
export LOCAL_INT_IP="$(ip route get 8.8.8.8 | sed -E 's/.*via (\S+) .*/\1/;t;d')"
export LOCAL_INT_NAME="$(ip route get 8.8.8.8 | sed -E 's/.*dev (\S+) .*/\1/;t;d')"
export LOCAL_INT_GATEWAY="$(ip route get 8.8.8.8 | sed -E 's/.*src (\S+) .*/\1/;t;d')"
EOF

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
RUN apt install -y chrony crudini software-properties-common
RUN add-apt-repository cloud-archive:yoga -y

# configure NTP
RUN sed -i "/^pool .* iburst maxsources [0-9]$/d" /etc/chrony/chrony.conf
RUN echo "server controller iburst" >> /etc/chrony/chrony.conf
RUN service chrony restart

RUN apt install -y thin-provisioning-tools cinder-volume nfs-common

RUN apt install -y vim iputils-ping tcpdump

RUN apt install -y tini

RUN apt install -y netcat

WORKDIR /root
RUN apt autoclean -y & apt autoremove -y
ADD --chown=root:root block1_setup.sh /root/block1_setup.sh
ADD --chown=openstack:openstack admin_openrc /home/openstack/admin_openrc
ADD --chown=openstack:openstack demo_openrc /home/openstack/demo_openrc
