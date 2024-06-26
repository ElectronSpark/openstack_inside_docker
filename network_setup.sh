#!/bin/bash

source /etc/profile.d/99-generate_env.sh

if [ -e "./finish_entrypoint.sh" ]; then
    bash ./finish_entrypoint.sh
fi

service dbus start
service dnsmasq start
service haproxy start
service openvswitch-switch start

ovs-vsctl add-br ${PROVIDER_INTERFACE_NAME}

ovs-vsctl add-port ${PROVIDER_INTERFACE_NAME} gre_compute1 -- \
    set interface gre_compute1 type=gre \
    options:key=flow \
    options:packet_type=legacy_l2 \
    options:remote_ip=$(getent hosts compute1 | cut -d' ' -f1)
ovs-vsctl set int gre_compute1 mtu_request=1450

ovs-vsctl set int ${PROVIDER_INTERFACE_NAME} mtu_request=1450
ip address add ${PROVIDER_INT_IP}/${PROVIDER_NETWORK_PREFIX_LENGTH} dev ${PROVIDER_INTERFACE_NAME}
ip link set dev ${PROVIDER_INTERFACE_NAME} up

# network node as the default gateway of the provider's network
sysctl -w net.ipv4.ip_forward=1
sudo iptables -A FORWARD -i eth0 -o ${PROVIDER_INTERFACE_NAME} -j ACCEPT
sudo iptables -A FORWARD -i ${PROVIDER_INTERFACE_NAME} -o eth0 -j ACCEPT
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -o ${PROVIDER_INTERFACE_NAME} -j MASQUERADE

echo "configuring neutron network service"
crudini --set /etc/neutron/neutron.conf DEFAULT \
    transport_url "rabbit://openstack:${RABBIT_PASS}@rabbitmq_server"
crudini --set /etc/neutron/neutron.conf oslo_concurrency \
    lock_path "/var/lib/neutron/tmp"


crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs \
    bridge_mappings "provider:${PROVIDER_INTERFACE_NAME}"
crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs \
    local_ip "${PROVIDER_INT_IP}"

crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini agent \
    tunnel_types "vxlan"
crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini agent \
    l2_population "true"
crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini securitygroup \
    enable_security_group "true"
crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini securitygroup \
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
    nova_metadata_host "os-controller"
crudini --set /etc/neutron/metadata_agent.ini DEFAULT \
    metadata_proxy_shared_secret "${NOVA_METADATA_SECRET}"

netcat -l 8000

# service neutron-linuxbridge-agent restart
service neutron-openvswitch-agent restart
service neutron-dhcp-agent restart
service neutron-metadata-agent restart
service neutron-l3-agent restart

if [ ! -e "finish_entrypoint.sh" ]; then
cat > finish_entrypoint.sh << EOF
#!/bin/bash

/bin/bash
EOF
chmod 755 ./finish_entrypoint.sh
fi
bash ./finish_entrypoint.sh
