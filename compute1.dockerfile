FROM ubuntu:20.04

ENV LOCAL_INT_IP="10.0.0.31"
ENV LOCAL_MGMT_IP="10.100.0.31"

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
RUN apt install -y openssh-server openssh-client libssl-dev \
    openvswitch-switch-dpdk chrony crudini software-properties-common
RUN add-apt-repository cloud-archive:yoga -y

# configure NTP
RUN sed -i "/^pool .* iburst maxsources [0-9]$/d" /etc/chrony/chrony.conf
RUN echo "server controller iburst" >> /etc/chrony/chrony.conf
RUN service chrony restart

RUN apt install -y nova-compute-kvm nova-compute nfs-common

RUN apt install -y neutron-openvswitch-agent

RUN apt install -y vim iputils-ping tcpdump

RUN apt-get -y install bridge-utils dmidecode dnsmasq ebtables \
    iproute2 iptables 
RUN apt install -y tini

RUN sed -i '/^#stdio_handler/ a\stdio_handler = "file"' /etc/libvirt/qemu.conf

RUN echo "KERNEL==\"kvm\", GROUP=\"kvm\", MODE=\"0660\"" > /etc/udev/rules.d/99-kvm.rules

COPY config/pools/* /etc/libvirt/storage/
COPY config/networks/* /etc/libvirt/qemu/networks/
RUN mkdir -p /etc/libvirt/storage/autostart /etc/libvirt/qemu/networks/autostart && \
    for pool in /etc/libvirt/storage/*.xml; do \
        ln -sf "../${pool##*/}" /etc/libvirt/storage/autostart/; \
    done && \
    for net in /etc/libvirt/qemu/networks/*.xml; do \
        ln -sf "../${net##*/}" /etc/libvirt/qemu/networks/autostart/; \
    done

WORKDIR /root
RUN apt autoclean -y & apt autoremove -y
ADD --chown=root:root compute1_setup.sh /root/compute1_setup.sh
ADD --chown=openstack:openstack admin_openrc /home/openstack/admin_openrc
ADD --chown=openstack:openstack demo_openrc /home/openstack/demo_openrc
