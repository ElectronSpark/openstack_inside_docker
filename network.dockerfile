FROM ubuntu:20.04

ENV PROVIDER_INT_IP=10.0.0.15

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
RUN apt install -y openvswitch-switch-dpdk
RUN apt install -y openssh-server openssh-client libssl-dev
RUN apt install -y crudini
RUN apt install -y software-properties-common
RUN add-apt-repository cloud-archive:yoga -y

# configure NTP
# RUN echo "allow ${LOCAL_NETWORK}" >> /etc/chrony/chrony.conf
# RUN service chrony restart

# install neutron
RUN apt install -y neutron-plugin-ml2 neutron-dhcp-agent \
neutron-l3-agent neutron-metadata-agent

# RUN apt install -y neutron-linuxbridge-agent
RUN apt install -y neutron-openvswitch-agent

RUN apt install -y vim
RUN apt install -y iputils-ping tcpdump
RUN apt install -y net-tools
# mysql client
RUN apt install -y python3-pymysql 

RUN apt install -y tini

# libvirt related
RUN apt-get -y install bridge-utils dmidecode dnsmasq ebtables \
    iproute2 iptables netcat

ADD --chown=openstack:openstack admin_openrc /home/openstack/admin_openrc
ADD --chown=openstack:openstack demo_openrc /home/openstack/demo_openrc
ADD --chown=root:root ./network_setup.sh /root/network_setup.sh
ADD --chown=root:root ./config/profile.d/99-generate_env.sh /etc/profile.d/99-generate_env.sh

WORKDIR /root
USER root
RUN apt autoclean -y & apt autoremove -y
RUN echo "source /etc/profile.d/99-generate_env.sh" >> /etc/bash.bashrc
CMD ["tini", "--", "/root/network_setup.sh"]