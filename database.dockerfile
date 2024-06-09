FROM ubuntu:20.04

ENV LOCAL_INT_IP="10.0.0.5"
ENV LOCAL_NETWORK_GATEWAY="10.0.0.15"
ENV LOCAL_NETWORK_PREFIX="10.0.0.0"
ENV LOCAL_NETWORK_PREFIX_LENGTH="24"
ENV LOCAL_NETWORK="${LOCAL_NETWORK_PREFIX}/${LOCAL_NETWORK_PREFIX_LENGTH}"
ENV TUNNEL_INTERFACE_NAME="gre0"
ENV PROVIDER_INTERFACE_DEVICE="eth0"
ENV PROVIDER_INTERFACE_NAME="br-provider"

ENV MARIADB_ROOT_PASSWORD="password"
ENV MARIADB_PASSWORD="password"
ENV KEYSTONE_DBPASS="password"
ENV GLANCE_DBPASS="password"
ENV PLACEMENT_DBPASS="password"
ENV NOVA_DBPASS="password"
ENV NEUTRON_DBPASS="password"

RUN apt update -y
RUN apt install -y openssh-server openssh-client libssl-dev \
    openvswitch-switch-dpdk chrony crudini software-properties-common

# configure mysql database
RUN apt install -y mariadb-server python3-pymysql

ADD --chown=root:root database_setup.sh /root/database_setup.sh
CMD [ "/root/database_setup.sh" ]
