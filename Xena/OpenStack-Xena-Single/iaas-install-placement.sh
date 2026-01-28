#!/bin/bash
set -ex
source openrc.sh
source /etc/keystone/admin-openrc.sh
# 数据库配置
mysql -uroot -p$DB_PASS -e "create database IF NOT EXISTS placement ;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY '$PLACEMENT_DBPASS' ;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY '$PLACEMENT_DBPASS' ;"
# Keystone认证
openstack user create --domain default --password $PLACEMENT_PASS placement
openstack role add --project service --user placement admin
openstack service create --name placement --description "Placement API" placement
openstack endpoint create --region RegionOne placement public http://$HOST_NAME:8778
openstack endpoint create --region RegionOne placement internal http://$HOST_NAME:8778
openstack endpoint create --region RegionOne placement admin http://$HOST_NAME:8778
# 安装Placement软件包
yum -y install openstack-placement-api
# 主配置文件设置
crudini --set /etc/placement/placement.conf placement_database connection mysql+pymysql://placement:$PLACEMENT_DBPASS@$HOST_NAME/placement
crudini --set /etc/placement/placement.conf api auth_strategy keystone
crudini --set /etc/placement/placement.conf keystone_authtoken auth_url http://$HOST_NAME:5000/v3
crudini --set /etc/placement/placement.conf keystone_authtoken memcached_servers $HOST_NAME:11211
crudini --set /etc/placement/placement.conf keystone_authtoken auth_type password
crudini --set /etc/placement/placement.conf keystone_authtoken project_domain_name Default
crudini --set /etc/placement/placement.conf keystone_authtoken user_domain_name Default
crudini --set /etc/placement/placement.conf keystone_authtoken project_name service
crudini --set /etc/placement/placement.conf keystone_authtoken username placement
crudini --set /etc/placement/placement.conf keystone_authtoken password $PLACEMENT_PASS
# 添加Httpd认证
echo "
<Directory /usr/bin>
    <IfVersion >= 2.4>
        Require all granted
    </IfVersion>
    <IfVersion < 2.4>
        Order allow,deny
        Allow from all
    </IfVersion>
</Directory>
" >> /etc/httpd/conf.d/00-placement-api.conf
# 同步数据库
su -s /bin/sh -c "placement-manage db sync" placement
systemctl restart httpd

echo Done-iass-install-placement
