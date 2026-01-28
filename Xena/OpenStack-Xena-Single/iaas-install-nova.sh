#!/bin/bash
set -ex
source openrc.sh
if [[ ! -n "$(echo $FLOATING_IP)" ]];then
    echo "FLOATING_IP none"
    exit 1
fi

source /etc/keystone/admin-openrc.sh
function correct_repo() {
    sed -i -e "s|mirrorlist=|#mirrorlist=|g" /etc/yum.repos.d/CentOS-*
    sed -i -e "s|#baseurl=http://mirror.centos.org|baseurl=https://mirrors.aliyun.com|g" /etc/yum.repos.d/CentOS-*
}
# This version Nova need openvswitch package, but the version release
# repo didn't have ovs, just replace it to Ussuri.
yum -y install epel-release
yum -y install centos-release-openstack-ussuri
correct_repo
sed -i "9d" /etc/yum.repos.d/CentOS-Ceph-Nautilus.repo
ceph_nautilus_baseurl_entry="baseurl=https://mirrors.aliyun.com/centos/8/storage/\$basearch/ceph-nautilus/"
sed -i "/\[centos-ceph-nautilus\]/a$ceph_nautilus_baseurl_entry" /etc/yum.repos.d/CentOS-Ceph-Nautilus.repo
# 安装Nova需要的软件包
yum -y install openstack-nova-api openstack-nova-conductor openstack-nova-novncproxy openstack-nova-scheduler openstack-nova-compute
# 数据库配置
mysql -uroot -p$DB_PASS -e "create database IF NOT EXISTS nova_api ;"
mysql -uroot -p$DB_PASS -e "create database IF NOT EXISTS nova ;"
mysql -uroot -p$DB_PASS -e "create database IF NOT EXISTS nova_cell0 ;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS' ;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS' ;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS' ;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS' ;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS' ;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS' ;"
# Keystone认证
openstack user create --domain default --password $NOVA_PASS nova
openstack role add --project service --user nova admin
openstack service create --name nova --description "OpenStack Compute" compute
openstack endpoint create --region RegionOne compute public http://$HOST_NAME:8774/v2.1
openstack endpoint create --region RegionOne compute internal http://$HOST_NAME:8774/v2.1
openstack endpoint create --region RegionOne compute admin http://$HOST_NAME:8774/v2.1
# 主配置文件设置
crudini --set /etc/nova/nova.conf api_database connection mysql+pymysql://nova:$NOVA_DBPASS@$HOST_NAME/nova_api
crudini --set /etc/nova/nova.conf database connection mysql+pymysql://nova:$NOVA_DBPASS@$HOST_NAME/nova
crudini --set /etc/nova/nova.conf DEFAULT enabled_apis osapi_compute,metadata
crudini --set /etc/nova/nova.conf DEFAULT compute_driver libvirt.LibvirtDriver
crudini --set /etc/nova/nova.conf DEFAULT instances_path /var/lib/nova/instances
crudini --set /etc/nova/nova.conf DEFAULT transport_url rabbit://openstack:$RABBIT_PASS@$HOST_NAME
crudini --set /etc/nova/nova.conf DEFAULT my_ip $HOST_IP
crudini --set /etc/nova/nova.conf DEFAULT use_neutron true
crudini --set /etc/nova/nova.conf DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver
crudini --set /etc/nova/nova.conf DEFAULT log_dir /var/log/nova
crudini --set /etc/nova/nova.conf api auth_strategy keystone
crudini --set /etc/nova/nova.conf keystone_authtoken www_authenticate_uri http://$HOST_NAME:5000/
crudini --set /etc/nova/nova.conf keystone_authtoken auth_url http://$HOST_NAME:5000/v3
crudini --set /etc/nova/nova.conf keystone_authtoken memcached_servers $HOST_NAME:11211
crudini --set /etc/nova/nova.conf keystone_authtoken auth_type password
crudini --set /etc/nova/nova.conf keystone_authtoken project_domain_name Default
crudini --set /etc/nova/nova.conf keystone_authtoken user_domain_name Default
crudini --set /etc/nova/nova.conf keystone_authtoken project_name service
crudini --set /etc/nova/nova.conf keystone_authtoken username nova
crudini --set /etc/nova/nova.conf keystone_authtoken password $NOVA_PASS
# VNC设置
crudini --set /etc/nova/nova.conf vnc enabled true
crudini --set /etc/nova/nova.conf vnc vncserver_listen 0.0.0.0
crudini --set /etc/nova/nova.conf vnc vncserver_proxyclient_address $HOST_IP
crudini --set /etc/nova/nova.conf vnc server_listen $HOST_IP
crudini --set /etc/nova/nova.conf vnc server_proxyclient_address $HOST_IP
crudini --set /etc/nova/nova.conf vnc novncproxy_base_url http://$FLOATING_IP:6080/vnc_auto.html
crudini --set /etc/nova/nova.conf glance api_servers http://$HOST_NAME:9292
crudini --set /etc/nova/nova.conf oslo_concurrency lock_path /var/lib/nova/tmp
# 配置Placement认证
crudini --set /etc/nova/nova.conf placement region_name RegionOne
crudini --set /etc/nova/nova.conf placement project_domain_name Default
crudini --set /etc/nova/nova.conf placement project_name service
crudini --set /etc/nova/nova.conf placement auth_type password
crudini --set /etc/nova/nova.conf placement user_domain_name Default
crudini --set /etc/nova/nova.conf placement auth_url http://$HOST_NAME:5000/v3
crudini --set /etc/nova/nova.conf placement username placement
crudini --set /etc/nova/nova.conf placement password $PLACEMENT_PASS
# 同步数据库
su -s /bin/sh -c "nova-manage api_db sync" nova
su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
su -s /bin/sh -c "nova-manage db sync" nova
su -s /bin/sh -c "nova-manage cell_v2 list_cells" nova
iptables -F
iptables -X
iptables -Z
/usr/libexec/iptables/iptables.init save
# 落定服务
systemctl enable \
    openstack-nova-api.service \
    openstack-nova-scheduler.service \
    openstack-nova-conductor.service \
    openstack-nova-novncproxy.service \
    libvirtd.service \
    openstack-nova-compute.service
systemctl start \
    openstack-nova-api.service \
    openstack-nova-scheduler.service \
    openstack-nova-conductor.service \
    openstack-nova-novncproxy.service \
    libvirtd.service \
    openstack-nova-compute.service

echo Done-iass-install-nova
