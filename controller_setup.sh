#!/bin/bash

source /etc/profile.d/99-generate_env.sh

if [ -e "finish_entrypoint.sh" ]; then
    bash finish_entrypoint.sh
fi

cp -f /etc/hosts /tmp/hosts.new
sed -i "s/.*os-controller//g" /tmp/hosts.new
echo "${LOCAL_INT_IP} os-controller" >> /tmp/hosts.new
cat /tmp/hosts.new > /etc/hosts

service dbus start

echo "configuring ETCD..."
sed -i "s/^.*ETCD_NAME=.*$/ETCD_NAME=\"os-controller\"/g"   /etc/default/etcd
sed -i "s/^.*ETCD_DATA_DIR=.*$/ETCD_DATA_DIR=\"\/var\/lib\/etcd\"/g"    /etc/default/etcd
sed -i "s/^.*ETCD_INITIAL_CLUSTER_STATE=.*$/ETCD_INITIAL_CLUSTER_STATE=\"new\"/g"    /etc/default/etcd
sed -i "s/^.*ETCD_INITIAL_CLUSTER_TOKEN=.*$/ETCD_INITIAL_CLUSTER_TOKEN=\"etcd-cluster-01\"/g"    /etc/default/etcd
sed -i "s/^.*ETCD_INITIAL_CLUSTER=.*$/ETCD_INITIAL_CLUSTER=\"os-controller=http:\/\/${LOCAL_INT_IP}:2380\"/g" /etc/default/etcd
sed -i "s/^.*ETCD_INITIAL_ADVERTISE_PEER_URLS=.*$/ETCD_INITIAL_ADVERTISE_PEER_URLS=\"http:\/\/${LOCAL_INT_IP}:2380\"/g"    /etc/default/etcd
sed -i "s/^.*ETCD_ADVERTISE_CLIENT_URLS=.*$/ETCD_ADVERTISE_CLIENT_URLS=\"http:\/\/${LOCAL_INT_IP}:2379\"/g"    /etc/default/etcd
sed -i "s/^.*ETCD_LISTEN_PEER_URLS=.*$/ETCD_LISTEN_PEER_URLS=\"http:\/\/0.0.0.0:2380\"/g"  /etc/default/etcd
sed -i "s/^.*ETCD_LISTEN_CLIENT_URLS=.*$/ETCD_LISTEN_CLIENT_URLS=\"http:\/\/${LOCAL_INT_IP}:2379\"/g"  /etc/default/etcd
systemctl enable etcd
service etcd restart

# configure keystone
echo "configuring keystone..."

crudini --set /etc/keystone/keystone.conf database connection "mysql+pymysql://keystone:${KEYSTONE_DBPASS}@database/keystone"
crudini --set /etc/keystone/keystone.conf token provider "fernet"
su -s /bin/sh -c "keystone-manage db_sync" keystone
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
keystone-manage bootstrap --bootstrap-password ${KEYSTONE_PASS} \
  --bootstrap-admin-url http://os-controller:5000/v3/ \
  --bootstrap-internal-url http://os-controller:5000/v3/ \
  --bootstrap-public-url http://os-controller:5000/v3/ \
  --bootstrap-region-id RegionOne
echo "ServerName os-controller" >> /etc/apache2/apache2.conf
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
  image public http://os-controller:9292
openstack endpoint create --region RegionOne \
  image internal http://os-controller:9292
openstack endpoint create --region RegionOne \
  image admin http://os-controller:9292

# get glance endpoint id
GLANCE_ENDPOINT_ID=$(openstack endpoint list | awk '
  BEGIN { FS = " *\\| *"; OFS = "|" }
  /glance/ && /admin/ {
    print $2
  }
')

crudini --set /etc/glance/glance-api.conf database connection \
    "mysql+pymysql://glance:${GLANCE_DBPASS}@database/glance"
crudini --set /etc/glance/glance-api.conf keystone_authtoken \
    www_authenticate_uri "http://os-controller:5000"
crudini --set /etc/glance/glance-api.conf keystone_authtoken \
    auth_url "http://os-controller:5000"
crudini --set /etc/glance/glance-api.conf keystone_authtoken \
    memcached_servers "memcached_server:11211"
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
    auth_url "http://os-controller:5000"
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
crudini --set /etc/glance/glance-api.conf DEFAULT \
    use_keystone_quotas "True"

openstack role add --user glance --user-domain Default --system all reader

su -s /bin/sh -c "glance-manage db_sync" glance
service glance-api restart
# wget http://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img
sleep 5
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
  placement public http://os-controller:8778
openstack endpoint create --region RegionOne \
  placement admin http://os-controller:8778
openstack endpoint create --region RegionOne \
  placement internal http://os-controller:8778

crudini --set /etc/placement/placement.conf placement_database \
    connection "mysql+pymysql://placement:${PLACEMENT_DBPASS}@database/placement"
crudini --set /etc/placement/placement.conf api \
    auth_strategy "keystone"
crudini --set /etc/placement/placement.conf keystone_authtoken \
    auth_url "http://os-controller:5000/v3"
crudini --set /etc/placement/placement.conf keystone_authtoken \
    memcached_servers "memcached_server:11211"
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

openstack --os-placement-api-version 1.2 resource class list --sort-column name
openstack --os-placement-api-version 1.6 trait list --sort-column name

# configuring neutron network service
echo "configuring neutron..."
openstack user create --domain default --password ${NEUTRON_PASS} neutron
openstack role add --project service --user neutron admin
openstack service create --name neutron \
  --description "OpenStack Networking" network
openstack endpoint create --region RegionOne \
  network public http://os-controller:9696
openstack endpoint create --region RegionOne \
  network internal http://os-controller:9696
openstack endpoint create --region RegionOne \
  network admin http://os-controller:9696

crudini --set /etc/neutron/neutron.conf database \
    connection "mysql+pymysql://neutron:${NEUTRON_DBPASS}@database/neutron"
crudini --set /etc/neutron/neutron.conf DEFAULT \
    core_plugin "ml2"
crudini --set /etc/neutron/neutron.conf DEFAULT \
    service_plugins "router,segments"
crudini --set /etc/neutron/neutron.conf DEFAULT \
    transport_url "rabbit://openstack:${RABBIT_PASS}@rabbitmq_server"
crudini --set /etc/neutron/neutron.conf DEFAULT \
    auth_strategy "keystone"
crudini --set /etc/neutron/neutron.conf DEFAULT \
    notify_nova_on_port_status_changes "true"
crudini --set /etc/neutron/neutron.conf DEFAULT \
    notify_nova_on_port_data_changes "true"
crudini --set /etc/neutron/neutron.conf keystone_authtoken \
    www_authenticate_uri "http://os-controller:5000"
crudini --set /etc/neutron/neutron.conf keystone_authtoken \
    auth_url "http://os-controller:5000"
crudini --set /etc/neutron/neutron.conf keystone_authtoken \
    memcached_servers "memcached_server:11211"
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
    auth_url "http://os-controller:5000"
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

crudini --set /etc/nova/nova.conf neutron \
    auth_url "http://os-controller:5000"
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
  compute public http://os-controller:8774/v2.1
openstack endpoint create --region RegionOne \
  compute internal http://os-controller:8774/v2.1
openstack endpoint create --region RegionOne \
  compute admin http://os-controller:8774/v2.1

crudini --set /etc/nova/nova.conf api_database \
    connection "mysql+pymysql://nova:${NOVA_DBPASS}@database/nova_api"
crudini --set /etc/nova/nova.conf database \
    connection "mysql+pymysql://nova:${NOVA_DBPASS}@database/nova"
crudini --set /etc/nova/nova.conf DEFAULT \
    my_ip "${LOCAL_INT_IP}"
crudini --set /etc/nova/nova.conf DEFAULT \
    transport_url  "rabbit://openstack:${RABBIT_PASS}@rabbitmq_server"
crudini --set /etc/nova/nova.conf api \
    auth_strategy "keystone"
crudini --set /etc/nova/nova.conf keystone_authtoken \
    www_authenticate_uri "http://os-controller:5000/"
crudini --set /etc/nova/nova.conf keystone_authtoken \
    auth_url "http://os-controller:5000/"
crudini --set /etc/nova/nova.conf keystone_authtoken \
    memcached_servers "memcached_server:11211"
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
#     auth_url "https://os-controller/identity"
crudini --set /etc/nova/nova.conf service_user \
    auth_url "http://os-controller:5000/identity"
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
    api_servers "http://os-controller:9292"
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
    auth_url "http://os-controller:5000/v3"
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

# configure cinder
openstack user create --domain default --password ${CINDER_PASS} cinder
openstack role add --project service --user cinder admin
openstack service create --name cinderv3 \
  --description "OpenStack Block Storage" volumev3
openstack endpoint create --region RegionOne \
  volumev3 public http://os-controller:8776/v3/%\(project_id\)s
openstack endpoint create --region RegionOne \
  volumev3 internal http://os-controller:8776/v3/%\(project_id\)s
openstack endpoint create --region RegionOne \
  volumev3 admin http://os-controller:8776/v3/%\(project_id\)s

crudini --set /etc/cinder/cinder.conf database \
    connection "mysql+pymysql://cinder:${CINDER_DBPASS}@database/cinder"

crudini --set /etc/cinder/cinder.conf DEFAULT \
    transport_url "rabbit://openstack:${RABBIT_PASS}@rabbitmq_server"
crudini --set /etc/cinder/cinder.conf DEFAULT \
    auth_strategy "keystone"
crudini --set /etc/cinder/cinder.conf DEFAULT \
    my_ip "${LOCAL_INT_IP}"

crudini --set /etc/cinder/cinder.conf keystone_authtoken \
    www_authenticate_uri "http://os-controller:5000"
crudini --set /etc/cinder/cinder.conf keystone_authtoken \
    auth_url "http://os-controller:5000"
crudini --set /etc/cinder/cinder.conf keystone_authtoken \
    memcached_servers "memcached_server:11211"
crudini --set /etc/cinder/cinder.conf keystone_authtoken \
    auth_type "password"
crudini --set /etc/cinder/cinder.conf keystone_authtoken \
    project_domain_name "default"
crudini --set /etc/cinder/cinder.conf keystone_authtoken \
    user_domain_name "default"
crudini --set /etc/cinder/cinder.conf keystone_authtoken \
    project_name "service"
crudini --set /etc/cinder/cinder.conf keystone_authtoken \
    username "cinder"
crudini --set /etc/cinder/cinder.conf keystone_authtoken \
    password "${CINDER_PASS}"

crudini --set /etc/cinder/cinder.conf oslo_concurrency \
    lock_path "/var/lib/cinder/tmp"

su -s /bin/sh -c "cinder-manage db sync" cinder

# configure nova for cinder
crudini --set /etc/nova/nova.conf cinder \
    os_region_name "RegionOne"

service nova-api restart
service cinder-scheduler restart
service apache2 restart


# notice compute node
echo -n "ok" | netcat block1 8000 -q 1
echo -n "ok" | netcat compute1 8000 -q 1
echo -n "ok" | netcat network 8000 -q 1

sleep 5
su -s /bin/sh -c "nova-manage cell_v2 discover_hosts --verbose" nova

echo "creating new network..."
openstack network create  --share --external \
  --provider-physical-network provider \
  --provider-network-type flat provider
openstack subnet create --network provider \
  --allocation-pool start=${PROVIDER_NETWORK_POOL_START},end=${PROVIDER_NETWORK_POOL_END} \
  --dns-nameserver 8.8.4.4 --gateway ${PROVIDER_NETWORK_GATEWAY} \
  --subnet-range ${PROVIDER_NETWORK} \
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
