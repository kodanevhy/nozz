#!/bin/bash
set -ex
source openrc.sh
source /etc/keystone/admin-openrc.sh
# 安装Glance服务软件包
yum -y install openstack-glance
# 数据库配置
mysql -uroot -p$DB_PASS -e "create database IF NOT EXISTS glance ;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$GLANCE_DBPASS' ;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$GLANCE_DBPASS' ;"
# Keystone认证
openstack user create --domain default --password $GLANCE_PASS glance
openstack role add --project service --user glance admin
openstack service create --name glance --description "OpenStack Image" image
openstack endpoint create --region RegionOne image public http://$HOST_NAME:9292
openstack endpoint create --region RegionOne image internal http://$HOST_NAME:9292
openstack endpoint create --region RegionOne image admin http://$HOST_NAME:9292
# API主配置文件设置
crudini --set /etc/glance/glance-api.conf database connection mysql+pymysql://glance:$GLANCE_DBPASS@$HOST_NAME/glance
crudini --set /etc/glance/glance-api.conf keystone_authtoken www_authenticate_uri http://$HOST_NAME:5000
crudini --set /etc/glance/glance-api.conf keystone_authtoken auth_url http://$HOST_NAME:5000
crudini --set /etc/glance/glance-api.conf keystone_authtoken memcached_servers  $HOST_NAME:11211
crudini --set /etc/glance/glance-api.conf keystone_authtoken auth_type password
crudini --set /etc/glance/glance-api.conf keystone_authtoken project_domain_name Default
crudini --set /etc/glance/glance-api.conf keystone_authtoken user_domain_name Default
crudini --set /etc/glance/glance-api.conf keystone_authtoken project_name service
crudini --set /etc/glance/glance-api.conf keystone_authtoken username glance
crudini --set /etc/glance/glance-api.conf keystone_authtoken password $GLANCE_PASS
crudini --set /etc/glance/glance-api.conf paste_deploy flavor keystone
crudini --set /etc/glance/glance-api.conf glance_store stores file,http
crudini --set /etc/glance/glance-api.conf glance_store default_store file
crudini --set /etc/glance/glance-api.conf glance_store filesystem_store_datadir /var/lib/glance/images/
# Registry主配置文件设置
crudini --set /etc/glance/glance-registry.conf database connection mysql+pymysql://glance:$GLANCE_DBPASS@$HOST_NAME/glance
crudini --set /etc/glance/glance-registry.conf keystone_authtoken www_authenticate_uri http://$HOST_NAME:5000
crudini --set /etc/glance/glance-registry.conf keystone_authtoken auth_url http://$HOST_NAME:5000
crudini --set /etc/glance/glance-registry.conf keystone_authtoken memcached_servers $HOST_NAME:11211
crudini --set /etc/glance/glance-registry.conf keystone_authtoken auth_type password
crudini --set /etc/glance/glance-registry.conf keystone_authtoken project_domain_name Default
crudini --set /etc/glance/glance-registry.conf keystone_authtoken user_domain_name Default
crudini --set /etc/glance/glance-registry.conf keystone_authtoken project_name service
crudini --set /etc/glance/glance-registry.conf keystone_authtoken username glance
crudini --set /etc/glance/glance-registry.conf keystone_authtoken password $GLANCE_PASS
crudini --set /etc/glance/glance-registry.conf paste_deploy flavor keystone
# 同步数据库
su -s /bin/sh -c "glance-manage db_sync" glance
# 落定服务
systemctl enable openstack-glance-api.service
systemctl restart openstack-glance-api.service

echo Done-iass-install-glance
