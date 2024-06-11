#!/bin/bash

if [ -e "./finish_entrypoint.sh" ]; then
    bash ./finish_entrypoint.sh
fi

service dbus start
service dnsmasq start

# libvirt related
usermod -G kvm -a "nova"
chown root:kvm /dev/kvm
libvirtd &

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


echo "configuring neutron network service"
crudini --set /etc/neutron/neutron.conf DEFAULT \
    transport_url "rabbit://openstack:${RABBIT_PASS}@controller"
crudini --set /etc/neutron/neutron.conf oslo_concurrency \
    lock_path "/var/lib/neutron/tmp"



crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs \
    bridge_mappings "provider:${PROVIDER_INTERFACE_NAME}"
crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs \
    local_ip "${LOCAL_INT_IP}"

crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini agent \
    tunnel_types "vxlan"
crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini agent \
    l2_population "true"
crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini securitygroup \
    enable_security_group "true"
crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini securitygroup \
    firewall_driver "openvswitch"

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
    password "${NEUTRON_DBPASS}"

# configure nova compute service
echo "configuring nova..."
crudini --set /etc/nova/nova.conf DEFAULT \
    transport_url "rabbit://openstack:${RABBIT_PASS}@controller"
crudini --set /etc/nova/nova.conf DEFAULT \
    my_ip "${LOCAL_MGMT_IP}"
crudini --set /etc/nova/nova.conf api \
    auth_strategy "keystone"
crudini --set /etc/nova/nova.conf keystone_authtoken \
    www_authenticate_uri "http://controller:5000/"
crudini --set /etc/nova/nova.conf keystone_authtoken \
    auth_url "http://controller:5000/"
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
    server_listen "0.0.0.0"
crudini --set /etc/nova/nova.conf vnc \
    server_proxyclient_address "\$my_ip"
crudini --set /etc/nova/nova.conf vnc \
    novncproxy_base_url "http://localhost:6080/vnc_auto.html"

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

# enable kvm
crudini --set /etc/nova/nova-compute.conf DEFAULT \
    compute_driver "libvirt.LibvirtDriver"
crudini --set /etc/nova/nova-compute.conf libvirt \
    virt_type "kvm"
crudini --set /etc/nova/nova-compute.conf libvirt \
    cpu_mode "host-passthrough"

netcat -l 8000

service nova-compute restart
# service neutron-linuxbridge-agent restart
service neutron-openvswitch-agent restart

if [ ! -e "finish_entrypoint.sh" ]; then
cat > finish_entrypoint.sh << EOF
#!/bin/bash

/bin/bash
EOF
chmod 755 ./finish_entrypoint.sh
fi
# libvirtd & bash ./finish_entrypoint.sh
bash ./finish_entrypoint.sh
