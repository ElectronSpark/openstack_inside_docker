#!/bin/bash

source /etc/profile.d/99-generate_env.sh

if [ -e "./finish_entrypoint.sh" ]; then
    bash ./finish_entrypoint.sh
fi

echo "nfs_server:/home" > /etc/cinder/nfs_shares
chown root:cinder /etc/cinder/nfs_shares
chmod 0640 /etc/cinder/nfs_shares

crudini --set /etc/cinder/cinder.conf database \
    connection "mysql+pymysql://cinder:${CINDER_DBPASS}@database/cinder"

crudini --set /etc/cinder/cinder.conf DEFAULT \
    transport_url "rabbit://openstack:${RABBIT_PASS}@rabbitmq_server"
crudini --set /etc/cinder/cinder.conf DEFAULT \
    auth_strategy "keystone"
crudini --set /etc/cinder/cinder.conf DEFAULT \
    my_ip "${LOCAL_INT_IP}"
crudini --set /etc/cinder/cinder.conf DEFAULT \
    enabled_backends "nfs"
crudini --set /etc/cinder/cinder.conf DEFAULT \
    glance_api_servers "http://controller:9292"

crudini --set /etc/cinder/cinder.conf keystone_authtoken \
    www_authenticate_uri "http://controller:5000"
crudini --set /etc/cinder/cinder.conf keystone_authtoken \
    auth_url "http://controller:5000"
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

crudini --set /etc/cinder/cinder.conf nfs \
    volume_driver "cinder.volume.drivers.nfs.NfsDriver"
crudini --set /etc/cinder/cinder.conf nfs \
    volume_group "cinder-volumes"
crudini --set /etc/cinder/cinder.conf nfs \
    nfs_shares_config "/etc/cinder/nfs_shares"
# crudini --set /etc/cinder/cinder.conf nfs \
#     nfs_mount_options "noresvport"

# # cinder/volume/nfs.py
# stat: CommandFilter, stat, root
# mount: CommandFilter, mount, root
# df: CommandFilter, df, cinder
# du: CommandFilter, du, cinder
# truncate: CommandFilter, truncate, cinder
# chmod: CommandFilter, chmod, root
# rm: CommandFilter, rm, cinder

crudini --set /etc/cinder/cinder.conf oslo_concurrency \
    lock_path "/var/lib/cinder/tmp"

netcat -l 8000

service cinder-volume restart


if [ ! -e "finish_entrypoint.sh" ]; then
cat > finish_entrypoint.sh << EOF
#!/bin/bash

/bin/bash
EOF
chmod 755 ./finish_entrypoint.sh
fi
bash ./finish_entrypoint.sh
