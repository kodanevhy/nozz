#!/bin/bash
set -ex
source openrc.sh
if [[ ! -n "$(echo $INTERFACE_NAME)" ]];then
    echo INTERFACE_NAME none
    exit 1
fi

source /etc/keystone/admin-openrc.sh
# 添加计算节点到单元数据库中
su -s /bin/sh -c "nova-manage cell_v2 discover_hosts --verbose" nova > /dev/null 2>&1
# 数据库配置
mysql -uroot -p$DB_PASS -e "create database IF NOT EXISTS neutron ;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$NEUTRON_DBPASS' ;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$NEUTRON_DBPASS' ;"
# Keystone认证
openstack user create --domain default --password $NEUTRON_PASS neutron
openstack role add --project service --user neutron admin
openstack service create --name neutron --description "OpenStack Networking" network
openstack endpoint create --region RegionOne network public http://$HOST_NAME:9696
openstack endpoint create --region RegionOne network internal http://$HOST_NAME:9696
openstack endpoint create --region RegionOne network admin http://$HOST_NAME:9696
# 安装Neutron需要的软件包
yum -y install openstack-neutron openstack-neutron-ml2 ebtables openstack-neutron-openvswitch haproxy ipset
# 主配置文件设置
crudini --set /etc/neutron/neutron.conf DEFAULT core_plugin ml2
crudini --set /etc/neutron/neutron.conf DEFAULT service_plugins router
crudini --set /etc/neutron/neutron.conf DEFAULT allow_overlapping_ips true
crudini --set /etc/neutron/neutron.conf DEFAULT transport_url rabbit://openstack:$RABBIT_PASS@$HOST_NAME
crudini --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_status_changes true
crudini --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_data_changes true
# 配置数据库连接
crudini --set /etc/neutron/neutron.conf database connection mysql+pymysql://neutron:$NEUTRON_DBPASS@$HOST_NAME/neutron
# 连接Keystone
crudini --set /etc/neutron/neutron.conf DEFAULT auth_strategy keystone
crudini --set /etc/neutron/neutron.conf keystone_authtoken www_authenticate_uri http://$HOST_NAME:5000
crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_url http://$HOST_NAME:5000
crudini --set /etc/neutron/neutron.conf keystone_authtoken memcached_servers $HOST_NAME:11211
crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_type password
crudini --set /etc/neutron/neutron.conf keystone_authtoken project_domain_name DEFAULT
crudini --set /etc/neutron/neutron.conf keystone_authtoken user_domain_name DEFAULT
crudini --set /etc/neutron/neutron.conf keystone_authtoken project_name service
crudini --set /etc/neutron/neutron.conf keystone_authtoken username neutron
crudini --set /etc/neutron/neutron.conf keystone_authtoken password $NEUTRON_PASS
# 配置锁路径
crudini --set /etc/neutron/neutron.conf oslo_concurrency lock_path /var/lib/neutron/tmp
# 在Neutron中连接Nova到Keystone
crudini --set /etc/neutron/neutron.conf nova auth_url http://$HOST_NAME:5000
crudini --set /etc/neutron/neutron.conf nova auth_type password
crudini --set /etc/neutron/neutron.conf nova project_domain_name DEFAULT
crudini --set /etc/neutron/neutron.conf nova user_domain_name DEFAULT
crudini --set /etc/neutron/neutron.conf nova region_name RegionOne
crudini --set /etc/neutron/neutron.conf nova project_name service
crudini --set /etc/neutron/neutron.conf nova username nova
crudini --set /etc/neutron/neutron.conf nova password $NOVA_PASS
# ML2插件配置
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_flat flat_networks external
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vlan network_vlan_ranges external:1:1000
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers flat,vlan,gre,vxlan,local
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 mechanism_drivers openvswitch,l2population
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 extension_drivers port_security
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup enable_ipset true
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup enable_security_group true
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup firewall_driver iptables_hybrid
# DHCP设置
crudini --set /etc/neutron/dhcp_agent.ini DEFAULT interface_driver neutron.agent.linux.interface.OVSInterfaceDriver
crudini --set /etc/neutron/dhcp_agent.ini DEFAULT dhcp_driver neutron.agent.linux.dhcp.Dnsmasq
crudini --set /etc/neutron/dhcp_agent.ini DEFAULT enable_isolated_metadata true
# 三层路由设置
crudini --set /etc/neutron/l3_agent.ini DEFAULT interface_driver neutron.agent.linux.interface.OVSInterfaceDriver
crudini --set /etc/neutron/l3_agent.ini DEFAULT ovs_integration_bridge br-int
crudini --set /etc/neutron/l3_agent.ini DEFAULT external_network_bridge br-ex
# Openvswitch网桥设置
crudini --set  /etc/neutron/plugins/ml2/openvswitch_agent.ini agent l2_population true
crudini --set  /etc/neutron/plugins/ml2/openvswitch_agent.ini agent prevent_arp_spoofing true
crudini --set  /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs integration_bridge br-int
crudini --set  /etc/neutron/plugins/ml2/openvswitch_agent.ini securitygroup firewall_driver iptables_hybrid
crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs bridge_mappings external:br-ex
crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs local_ip $HOST_IP
# 配置Metadata服务
crudini --set /etc/neutron/metadata_agent.ini DEFAULT nova_metadata_host $HOST_NAME
crudini --set /etc/neutron/metadata_agent.ini DEFAULT metadata_proxy_shared_secret $METADATA_SECRET
crudini --set /etc/neutron/metadata_agent.ini DEFAULT nova_metadata_port 8775
# 在Nova中连接Neutron到Keystone
crudini --set /etc/nova/nova.conf neutron url http://$HOST_NAME:9696
crudini --set /etc/nova/nova.conf neutron auth_url http://$HOST_NAME:5000
crudini --set /etc/nova/nova.conf neutron auth_type v3password
crudini --set /etc/nova/nova.conf neutron project_domain_name DEFAULT
crudini --set /etc/nova/nova.conf neutron user_domain_name DEFAULT
crudini --set /etc/nova/nova.conf neutron region_name RegionOne
crudini --set /etc/nova/nova.conf neutron project_name service
crudini --set /etc/nova/nova.conf neutron username neutron
crudini --set /etc/nova/nova.conf neutron password $NEUTRON_PASS
crudini --set /etc/nova/nova.conf neutron service_metadata_proxy true
crudini --set /etc/nova/nova.conf neutron metadata_proxy_shared_secret $METADATA_SECRET

# 配置内核转发
modprobe br_netfilter
echo "net.bridge.bridge-nf-call-iptables=1" >> /etc/sysctl.conf
echo "net.bridge.bridge-nf-call-ip6tables=1" >> /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
echo "net.ipv4.conf.default.rp_filter=0" >> /etc/sysctl.conf
echo "net.ipv4.conf.all.rp_filter=0" >> /etc/sysctl.conf
sysctl -p

ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini
# 同步数据库
su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
  --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron
# 创建网桥
systemctl restart openvswitch
systemctl enable openvswitch
ovs-vsctl add-br br-int > /dev/null 2>&1
ovs-vsctl add-br br-ex > /dev/null 2>&1
ovs-vsctl add-port br-ex $INTERFACE_NAME > /dev/null 2>&1
# 配置外网卡
cat > /etc/sysconfig/network-scripts/ifcfg-$INTERFACE_NAME << EOF
DEVICE=$INTERFACE_NAME
TYPE=Ethernet
BOOTPROTO=none
ONBOOT=yes
EOF
ethtool -K $INTERFACE_NAME gro off
nmcli c reload $INTERFACE_NAME
nmcli d reapply $INTERFACE_NAME
# 落定服务
systemctl restart openstack-nova-api.service
systemctl enable neutron-server.service neutron-openvswitch-agent.service neutron-dhcp-agent.service neutron-metadata-agent.service neutron-l3-agent.service
systemctl start neutron-server.service neutron-openvswitch-agent.service neutron-dhcp-agent.service neutron-metadata-agent.service neutron-l3-agent.service
systemctl restart openstack-nova-compute.service

echo Done-iass-install-neutron
