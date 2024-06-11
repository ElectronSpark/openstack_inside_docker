FROM ubuntu:20.04

ENV LOCAL_INT_IP="10.100.0.5"

RUN apt update -y
# RUN apt install -y openssh-server openssh-client libssl-dev \
#     openvswitch-switch-dpdk chrony crudini software-properties-common

# configure mysql database
RUN apt install -y mariadb-server python3-pymysql

ADD --chown=root:root database_setup.sh /root/database_setup.sh
CMD [ "/root/database_setup.sh" ]
