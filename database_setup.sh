#!/bin/bash

source /etc/profile.d/99-generate_env.sh

if [ -e "/root/finish_entrypoint.sh" ]; then
    bash /root/finish_entrypoint.sh
fi

# configure mysql database
echo "initializing mysql mariadb..."

cat > /etc/mysql/mariadb.conf.d/99-openstack.cnf <<EOF
[mysqld]
# bind-address = ${LOCAL_INT_IP}
bind-address = 0.0.0.0

default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
EOF
cat /etc/mysql/mariadb.conf.d/99-openstack.cnf

service mysql start
# echo -e "\n n\n n\n y\n y\n y\n y\n" | mysql_secure_installation
# # add databases for openstack
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

CREATE DATABASE cinder;

GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' \
IDENTIFIED BY '${CINDER_DBPASS}';
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' \
IDENTIFIED BY '${CINDER_DBPASS}';
EOF

echo "done"

if [ ! -e "/root/finish_entrypoint.sh" ]; then
cat > /root/finish_entrypoint.sh << EOF
#!/bin/bash

/bin/bash
EOF
chmod 755 /root/finish_entrypoint.sh
fi
bash
