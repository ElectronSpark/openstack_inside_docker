#!/bin/bash

if [ -e "finish_entrypoint.sh" ]; then
    bash finish_entrypoint.sh
fi

service openvswitch-switch start
ovs-vsctl add-br ${PROVIDER_INTERFACE_NAME}
# ovs-vsctl add-port ${PROVIDER_INTERFACE_NAME} gre0 -- set interface gre0 type=gre options:remote_ip=10.100.0.11
ovs-vsctl add-port ${PROVIDER_INTERFACE_NAME} ${TUNNEL_INTERFACE_NAME} -- \
    set interface ${TUNNEL_INTERFACE_NAME} type=gre \
    options:key=flow \
    options:packet_type=legacy_l2 \
    options:remote_ip=10.100.0.15
ip address add ${LOCAL_INT_IP}/${LOCAL_NETWORK_PREFIX_LENGTH} dev ${PROVIDER_INTERFACE_NAME}
ovs-vsctl set int ${TUNNEL_INTERFACE_NAME} mtu_request=8958
ovs-vsctl set int ${PROVIDER_INTERFACE_NAME} mtu_request=8958
ip link set dev ${PROVIDER_INTERFACE_NAME} up

# configure mysql database
echo "initializing mysql mariadb..."

cat > /etc/mysql/mariadb.conf.d/99-openstack.cnf <<EOF
[mysqld]
bind-address = ${LOCAL_INT_IP}

default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
EOF

service mysql start
echo -e "\n n\n n\n y\n y\n y\n y\n" | mysql_secure_installation
# add databases for openstack
echo "creating databases..."
mysql -u root <<EOF
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' \
IDENTIFIED BY '${KEYSTONE_DBPASS}';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' \
IDENTIFIED BY '${KEYSTONE_DBPASS}';

CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' \
IDENTIFIED BY '${GLANCE_DBPASS}';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' \
IDENTIFIED BY '${GLANCE_DBPASS}';

CREATE DATABASE placement;
GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' \
IDENTIFIED BY '${PLACEMENT_DBPASS}';
GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' \
IDENTIFIED BY '${PLACEMENT_DBPASS}';

CREATE DATABASE nova_api;
CREATE DATABASE nova;
CREATE DATABASE nova_cell0;
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' \
IDENTIFIED BY '${NOVA_DBPASS}';
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' \
IDENTIFIED BY '${NOVA_DBPASS}';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' \
IDENTIFIED BY '${NOVA_DBPASS}';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' \
IDENTIFIED BY '${NOVA_DBPASS}';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' \
IDENTIFIED BY '${NOVA_DBPASS}';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' \
IDENTIFIED BY '${NOVA_DBPASS}';

CREATE DATABASE neutron;
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' \
IDENTIFIED BY '${NEUTRON_DBPASS}';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' \
IDENTIFIED BY '${NEUTRON_DBPASS}';
EOF

echo "done"

if [ ! -e "finish_entrypoint.sh" ]; then
cat > finish_entrypoint.sh << EOF
#!/bin/bash

/bin/bash
EOF
chmod 755 ./finish_entrypoint.sh
fi
bash ./finish_entrypoint.sh
