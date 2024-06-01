#!/bin/bash

# libvirt related
# /usr/bin/tini /usr/sbin/libvirtd

if [ -e "finish_entrypoint.sh" ]; then
    bash finish_entrypoint.sh
fi

cp -f /etc/hosts /tmp/hosts.new
sed -i "s/.*controller//g" /tmp/hosts.new
echo "${LOCAL_INT_IP} controller" >> /tmp/hosts.new
cat /tmp/hosts.new > /etc/hosts

su -s /bin/bash -c "openssl rand -hex 10" openstack

# create br-provider interface
service openvswitch-switch start
ovs-vsctl add-br ${PROVIDER_INTERFACE_NAME}
ovs-vsctl add-port ${PROVIDER_INTERFACE_NAME} ${TUNNEL_INTERFACE_NAME} -- \
    set interface ${TUNNEL_INTERFACE_NAME} type=gre \
    options:key=flow \
    options:packet_type=legacy_l2 \
    options:remote_ip=10.100.0.31
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
service mysql restart
echo -e "\n n\n n\n y\n y\n y\n y\n" | mysql_secure_installation

echo "adding user openstack to rabbitmq..."
service rabbitmq-server restart
rabbitmqctl add_user openstack ${RABBIT_PASS}
rabbitmqctl set_permissions openstack ".*" ".*" ".*"

echo "configuring ETCD..."
sed -i "s/^.*ETCD_NAME=.*$/ETCD_NAME=\"controller\"/g"   /etc/default/etcd
sed -i "s/^.*ETCD_DATA_DIR=.*$/ETCD_DATA_DIR=\"\/var\/lib\/etcd\"/g"    /etc/default/etcd
sed -i "s/^.*ETCD_INITIAL_CLUSTER_STATE=.*$/ETCD_INITIAL_CLUSTER_STATE=\"new\"/g"    /etc/default/etcd
sed -i "s/^.*ETCD_INITIAL_CLUSTER_TOKEN=.*$/ETCD_INITIAL_CLUSTER_TOKEN=\"etcd-cluster-01\"/g"    /etc/default/etcd
sed -i "s/^.*ETCD_INITIAL_CLUSTER=.*$/ETCD_INITIAL_CLUSTER=\"controller=http:\/\/${LOCAL_INT_IP}:2380\"/g" /etc/default/etcd
sed -i "s/^.*ETCD_INITIAL_ADVERTISE_PEER_URLS=.*$/ETCD_INITIAL_ADVERTISE_PEER_URLS=\"http:\/\/${LOCAL_INT_IP}:2380\"/g"    /etc/default/etcd
sed -i "s/^.*ETCD_ADVERTISE_CLIENT_URLS=.*$/ETCD_ADVERTISE_CLIENT_URLS=\"http:\/\/${LOCAL_INT_IP}:2379\"/g"    /etc/default/etcd
sed -i "s/^.*ETCD_LISTEN_PEER_URLS=.*$/ETCD_LISTEN_PEER_URLS=\"http:\/\/0.0.0.0:2380\"/g"  /etc/default/etcd
sed -i "s/^.*ETCD_LISTEN_CLIENT_URLS=.*$/ETCD_LISTEN_CLIENT_URLS=\"http:\/\/${LOCAL_INT_IP}:2379\"/g"  /etc/default/etcd
systemctl enable etcd
service etcd restart

# add databases for openstack
echo "creating databases..."
# mysql -u root < controller_sql.sql
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

# configure keystone
echo "configuring keystone..."

crudini --set /etc/keystone/keystone.conf database connection "mysql+pymysql://keystone:${KEYSTONE_DBPASS}@controller/keystone"
crudini --set /etc/keystone/keystone.conf token provider "fernet"
su -s /bin/sh -c "keystone-manage db_sync" keystone
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
keystone-manage bootstrap --bootstrap-password ${KEYSTONE_PASS} \
  --bootstrap-admin-url http://controller:5000/v3/ \
  --bootstrap-internal-url http://controller:5000/v3/ \
  --bootstrap-public-url http://controller:5000/v3/ \
  --bootstrap-region-id RegionOne
echo "ServerName controller" >> /etc/apache2/apache2.conf
service apache2 restart

# . /home/openstack/admin_openrc
openstack domain create --description "An Example Domain" example
openstack project create --domain default --description "Service Project" service
openstack project create --domain default --description "Demo Project" myproject
openstack user create --domain default --password password myuser
openstack role create myrole
openstack role add --project myproject --user myuser myrole

# configure glance
echo configuring glance image service...
openstack user create --domain default --password ${GLANCE_PASS} glance
openstack role add --project service --user glance admin
openstack service create --name glance \
  --description "OpenStack Image" image
openstack endpoint create --region RegionOne \
  image public http://controller:9292
openstack endpoint create --region RegionOne \
  image internal http://controller:9292
openstack endpoint create --region RegionOne \
  image admin http://controller:9292

# get glance endpoint id
GLANCE_ENDPOINT_ID=$(openstack endpoint list | awk '
  BEGIN { FS = " *\\| *"; OFS = "|" }
  /glance/ && /admin/ {
    print $2
  }
')

crudini --set /etc/glance/glance-api.conf database connection \
    "mysql+pymysql://glance:${GLANCE_DBPASS}@controller/glance"
crudini --set /etc/glance/glance-api.conf keystone_authtoken \
    www_authenticate_uri "http://controller:5000"
crudini --set /etc/glance/glance-api.conf keystone_authtoken \
    auth_url "http://controller:5000"
crudini --set /etc/glance/glance-api.conf keystone_authtoken \
    memcached_servers "controller:11211"
crudini --set /etc/glance/glance-api.conf keystone_authtoken \
    auth_type "password"
crudini --set /etc/glance/glance-api.conf keystone_authtoken \
    project_domain_name "Default"
crudini --set /etc/glance/glance-api.conf keystone_authtoken \
    user_domain_name "Default"
crudini --set /etc/glance/glance-api.conf keystone_authtoken \
    project_name "service"
crudini --set /etc/glance/glance-api.conf keystone_authtoken \
    username "glance"
crudini --set /etc/glance/glance-api.conf keystone_authtoken \
    password "${GLANCE_PASS}"
crudini --set /etc/glance/glance-api.conf paste_deploy \
    flavor "keystone"
crudini --set /etc/glance/glance-api.conf glance_store \
    stores "file,http"
crudini --set /etc/glance/glance-api.conf glance_store \
    default_store "file"
crudini --set /etc/glance/glance-api.conf glance_store \
    filesystem_store_datadir "/var/lib/glance/images/"
crudini --set /etc/glance/glance-api.conf oslo_limit \
    auth_url "http://controller:5000"
crudini --set /etc/glance/glance-api.conf oslo_limit \
    auth_type "password"
crudini --set /etc/glance/glance-api.conf oslo_limit \
    user_domain_id "default"
crudini --set /etc/glance/glance-api.conf oslo_limit \
    username "glance"
crudini --set /etc/glance/glance-api.conf oslo_limit \
    system_scope "all"
crudini --set /etc/glance/glance-api.conf oslo_limit \
    password "password"
crudini --set /etc/glance/glance-api.conf oslo_limit \
    endpoint_id "${GLANCE_ENDPOINT_ID}"
crudini --set /etc/glance/glance-api.conf oslo_limit \
    region_name "RegionOne"

openstack role add --user glance --user-domain Default --system all reader

crudini --set /etc/glance/glance-api.conf DEFAULT \
    use_keystone_quotas "True"

su -s /bin/sh -c "glance-manage db_sync" glance
service glance-api restart
wget http://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img
glance image-create --name "cirros" \
  --file cirros-0.4.0-x86_64-disk.img \
  --disk-format qcow2 --container-format bare \
  --visibility=public

# configure placement
echo "configuring placement..."
openstack user create --domain default --password ${PLACEMENT_PASS} placement
openstack role add --project service --user placement admin
openstack service create --name placement \
  --description "Placement API" placement
openstack endpoint create --region RegionOne \
  placement public http://controller:8778
openstack endpoint create --region RegionOne \
  placement admin http://controller:8778
openstack endpoint create --region RegionOne \
  placement internal http://controller:8778

crudini --set /etc/placement/placement.conf placement_database \
    connection "mysql+pymysql://placement:${PLACEMENT_DBPASS}@controller/placement"
crudini --set /etc/placement/placement.conf api \
    auth_strategy "keystone"
crudini --set /etc/placement/placement.conf keystone_authtoken \
    auth_url "http://controller:5000/v3"
crudini --set /etc/placement/placement.conf keystone_authtoken \
    memcached_servers "controller:11211"
crudini --set /etc/placement/placement.conf keystone_authtoken \
    auth_type "password"
crudini --set /etc/placement/placement.conf keystone_authtoken \
    project_domain_name "Default"
crudini --set /etc/placement/placement.conf keystone_authtoken \
    user_domain_name "Default"
crudini --set /etc/placement/placement.conf keystone_authtoken \
    project_name "service"
crudini --set /etc/placement/placement.conf keystone_authtoken \
    username "placement"
crudini --set /etc/placement/placement.conf keystone_authtoken \
    password "${PLACEMENT_PASS}"

su -s /bin/sh -c "placement-manage db sync" placement
service apache2 restart

apt install -y python3-osc-placement
openstack --os-placement-api-version 1.2 resource class list --sort-column name
openstack --os-placement-api-version 1.6 trait list --sort-column name

# configuring neutron network service
echo "configuring neutron..."
openstack user create --domain default --password ${NEUTRON_PASS} neutron
openstack role add --project service --user neutron admin
openstack service create --name neutron \
  --description "OpenStack Networking" network
openstack endpoint create --region RegionOne \
  network public http://controller:9696
openstack endpoint create --region RegionOne \
  network internal http://controller:9696
openstack endpoint create --region RegionOne \
  network admin http://controller:9696

crudini --set /etc/neutron/neutron.conf database \
    connection "mysql+pymysql://neutron:${NEUTRON_DBPASS}@controller/neutron"
crudini --set /etc/neutron/neutron.conf DEFAULT \
    core_plugin "ml2"
crudini --set /etc/neutron/neutron.conf DEFAULT \
    service_plugins "router,segments"
crudini --set /etc/neutron/neutron.conf DEFAULT \
    allow_overlapping_ips "true"
crudini --set /etc/neutron/neutron.conf DEFAULT \
    transport_url "rabbit://openstack:${RABBIT_PASS}@controller"
crudini --set /etc/neutron/neutron.conf DEFAULT \
    auth_strategy "keystone"
crudini --set /etc/neutron/neutron.conf DEFAULT \
    notify_nova_on_port_status_changes "true"
crudini --set /etc/neutron/neutron.conf DEFAULT \
    notify_nova_on_port_data_changes "true"
crudini --set /etc/neutron/neutron.conf keystone_authtoken \
    www_authenticate_uri "http://controller:5000"
crudini --set /etc/neutron/neutron.conf keystone_authtoken \
    auth_url "http://controller:5000"
crudini --set /etc/neutron/neutron.conf keystone_authtoken \
    memcached_servers "controller:11211"
crudini --set /etc/neutron/neutron.conf keystone_authtoken \
    auth_type "password"
crudini --set /etc/neutron/neutron.conf keystone_authtoken \
    project_domain_name "default"
crudini --set /etc/neutron/neutron.conf keystone_authtoken \
    user_domain_name "default"
crudini --set /etc/neutron/neutron.conf keystone_authtoken \
    project_name "service"
crudini --set /etc/neutron/neutron.conf keystone_authtoken \
    username "neutron"
crudini --set /etc/neutron/neutron.conf keystone_authtoken \
    password "${NEUTRON_PASS}"
crudini --set /etc/neutron/neutron.conf nova \
    auth_url "http://controller:5000"
crudini --set /etc/neutron/neutron.conf nova \
    auth_type "password"
crudini --set /etc/neutron/neutron.conf nova \
    project_domain_name "default"
crudini --set /etc/neutron/neutron.conf nova \
    user_domain_name "default"
crudini --set /etc/neutron/neutron.conf nova \
    region_name "RegionOne"
crudini --set /etc/neutron/neutron.conf nova \
    project_name "service"
crudini --set /etc/neutron/neutron.conf nova \
    username "nova"
crudini --set /etc/neutron/neutron.conf nova \
    password "${NOVA_PASS}"
crudini --set /etc/neutron/neutron.conf oslo_concurrency \
    lock_path "/var/lib/neutron/tmp"

crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 \
    type_drivers "flat,vlan,vxlan"
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 \
    tenant_network_types "vxlan"
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 \
    mechanism_drivers "openvswitch,l2population"

crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 \
    extension_drivers "port_security"
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_flat \
    flat_networks "provider"
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vxlan \
    vni_ranges "1:1000"

crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup \
    enable_ipset "true"


crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs \
    bridge_mappings "provider:${PROVIDER_INTERFACE_NAME}"

crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini vxlan \
    local_ip "${LOCAL_INT_IP}"
crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini vxlan \
    l2_population "true"

crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini \
    enable_security_group "true"
crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini \
    firewall_driver "openvswitch"

crudini --set /etc/neutron/l3_agent.ini DEFAULT \
    interface_driver "openvswitch"

crudini --set /etc/neutron/dhcp_agent.ini DEFAULT \
    interface_driver "openvswitch"
crudini --set /etc/neutron/dhcp_agent.ini DEFAULT \
    dhcp_driver "neutron.agent.linux.dhcp.Dnsmasq"
crudini --set /etc/neutron/dhcp_agent.ini DEFAULT \
    enable_isolated_metadata "true"

crudini --set /etc/neutron/metadata_agent.ini DEFAULT \
    nova_metadata_host "controller"
crudini --set /etc/neutron/metadata_agent.ini DEFAULT \
    metadata_proxy_shared_secret "${NOVA_METADATA_SECRET}"

crudini --set /etc/nova/nova.conf neutron \
    auth_url "http://controller:5000"
crudini --set /etc/nova/nova.conf neutron \
    auth_type "password"
crudini --set /etc/nova/nova.conf neutron \
    project_domain_name "default"
crudini --set /etc/nova/nova.conf neutron \
    user_domain_name "default"
crudini --set /etc/nova/nova.conf neutron \
    region_name "RegionOne"
crudini --set /etc/nova/nova.conf neutron \
    project_name "service"
crudini --set /etc/nova/nova.conf neutron \
    username "neutron"
crudini --set /etc/nova/nova.conf neutron \
    password "${NEUTRON_PASS}"
crudini --set /etc/nova/nova.conf neutron \
    service_metadata_proxy "true"
crudini --set /etc/nova/nova.conf neutron \
    metadata_proxy_shared_secret "${NOVA_METADATA_SECRET}"

# restart neutron services after configuring nova
echo "configuring nova compute service..."
openstack user create --domain default --password ${NOVA_PASS} nova
openstack role add --project service --user nova admin
openstack service create --name nova \
  --description "OpenStack Compute" compute
openstack endpoint create --region RegionOne \
  compute public http://controller:8774/v2.1
openstack endpoint create --region RegionOne \
  compute internal http://controller:8774/v2.1
openstack endpoint create --region RegionOne \
  compute admin http://controller:8774/v2.1

crudini --set /etc/nova/nova.conf api_database \
    connection "mysql+pymysql://nova:${NOVA_DBPASS}@controller/nova_api"
crudini --set /etc/nova/nova.conf database \
    connection "mysql+pymysql://nova:${NOVA_DBPASS}@controller/nova"
crudini --set /etc/nova/nova.conf DEFAULT \
    my_ip "${LOCAL_INT_IP}"
crudini --set /etc/nova/nova.conf DEFAULT \
    transport_url  "rabbit://openstack:${RABBIT_PASS}@controller:5672/"
crudini --set /etc/nova/nova.conf api \
    auth_strategy "keystone"
crudini --set /etc/nova/nova.conf keystone_authtoken \
    www_authenticate_uri "http://controller:5000/"
crudini --set /etc/nova/nova.conf keystone_authtoken \
    auth_url "http://controller:5000/"
crudini --set /etc/nova/nova.conf keystone_authtoken \
    memcached_servers "controller:11211"
crudini --set /etc/nova/nova.conf keystone_authtoken \
    auth_type "password"
crudini --set /etc/nova/nova.conf keystone_authtoken \
    project_domain_name "Default"
crudini --set /etc/nova/nova.conf keystone_authtoken \
    user_domain_name "Default"
crudini --set /etc/nova/nova.conf keystone_authtoken \
    project_name "service"
crudini --set /etc/nova/nova.conf keystone_authtoken \
    username "nova"
crudini --set /etc/nova/nova.conf keystone_authtoken \
    password "${NOVA_PASS}"

crudini --set /etc/nova/nova.conf service_user \
    send_service_user_token "true"
# crudini --set /etc/nova/nova.conf service_user \
#     auth_url "https://controller/identity"
crudini --set /etc/nova/nova.conf service_user \
    auth_url "http://controller:5000/identity"
crudini --set /etc/nova/nova.conf service_user \
    auth_strategy "keystone"
crudini --set /etc/nova/nova.conf service_user \
    auth_type "password"
crudini --set /etc/nova/nova.conf service_user \
    project_domain_name "Default"
crudini --set /etc/nova/nova.conf service_user \
    project_name "service"
crudini --set /etc/nova/nova.conf service_user \
    user_domain_name "Default"
crudini --set /etc/nova/nova.conf service_user \
    username "nova"
crudini --set /etc/nova/nova.conf service_user \
    password "${NOVA_PASS}"

crudini --set /etc/nova/nova.conf vnc \
    enabled "true"
crudini --set /etc/nova/nova.conf vnc \
    server_listen "\$my_ip"
crudini --set /etc/nova/nova.conf vnc \
    server_proxyclient_address "\$my_ip"

crudini --set /etc/nova/nova.conf glance \
    api_servers "http://controller:9292"
crudini --set /etc/nova/nova.conf oslo_concurrency \
    lock_path "/var/lib/nova/tmp"

crudini --set /etc/nova/nova.conf placement \
    region_name "RegionOne"
crudini --set /etc/nova/nova.conf placement \
    project_domain_name "Default"
crudini --set /etc/nova/nova.conf placement \
    project_name "service"
crudini --set /etc/nova/nova.conf placement \
    auth_type "password"
crudini --set /etc/nova/nova.conf placement \
    user_domain_name "Default"
crudini --set /etc/nova/nova.conf placement \
    auth_url "http://controller:5000/v3"
crudini --set /etc/nova/nova.conf placement \
    username "placement"
crudini --set /etc/nova/nova.conf placement \
    password "${PLACEMENT_PASS}"

crudini --set /etc/nova/nova.conf scheduler \
    discover_hosts_in_cells_interval "300"

su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
  --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron

su -s /bin/sh -c "nova-manage api_db sync" nova
su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
su -s /bin/sh -c "nova-manage db sync" nova
su -s /bin/sh -c "nova-manage cell_v2 list_cells" nova

service nova-api restart
service nova-scheduler restart
service nova-conductor restart
service nova-novncproxy restart

service neutron-server restart
# service neutron-linuxbridge-agent restart
service neutron-l3-agent restart
service neutron-openvswitch-agent restart
service neutron-dhcp-agent restart
service neutron-metadata-agent restart

##########################################3
crudini --set /etc/nova/nova-compute.conf libvirt \
    virt_type "qemu"

service dbus start
service dnsmasq start
service haproxy start
service memcached start
service rabbitmq-server start
# notice compute node
echo -n "ok" | netcat compute1 8000 -q 1

sleep 5

echo "creating new network..."
openstack network create  --share --external \
  --provider-physical-network provider \
  --provider-network-type flat provider
openstack subnet create --network provider \
  --allocation-pool start=10.0.0.64,end=10.0.0.250 \
  --dns-nameserver 8.8.4.4 --gateway ${LOCAL_NETWORK_GATEWAY} \
  --subnet-range ${LOCAL_NETWORK} \
  provider
openstack network create selfservice
openstack subnet create --network selfservice \
  --dns-nameserver 8.8.4.4 --gateway 172.16.1.1 \
  --subnet-range 172.16.1.0/24 selfservice
openstack router create router
openstack router add subnet router selfservice
openstack router set router --external-gateway provider

openstack flavor create --id 0 --vcpus 1 --ram 64 --disk 1 m1.nano

# installing horizon
echo "installing horizon dashboard..."
apt install -y openstack-dashboard

cp local_settings.py /etc/openstack-dashboard/local_settings.py
chown horizon:horizon /etc/openstack-dashboard/local_settings.py
service apache2 restart
service apache-htcacheclean start


if [ ! -e "finish_entrypoint.sh" ]; then
cat > finish_entrypoint.sh << EOF
#!/bin/bash

/bin/bash
EOF
chmod 755 ./finish_entrypoint.sh
fi
bash ./finish_entrypoint.sh
