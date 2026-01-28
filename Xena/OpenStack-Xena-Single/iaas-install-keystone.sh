#!/bin/bash
set -ex
source openrc.sh
# Keystone基本组件的安装
yum -y install openstack-keystone httpd python3-mod_wsgi
# Keystone数据库的创建以及授权
mysql -uroot -p$DB_PASS -e "create database IF NOT EXISTS keystone ;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$KEYSTONE_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$KEYSTONE_DBPASS';"
# Keystone主配置文件的修改
crudini --set /etc/keystone/keystone.conf database connection  mysql+pymysql://keystone:$KEYSTONE_DBPASS@$HOST_NAME/keystone
crudini --set /etc/keystone/keystone.conf token provider fernet
su -s /bin/sh -c "keystone-manage db_sync" keystone
# Keystone安全与认证配置
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
keystone-manage bootstrap --bootstrap-password $ADMIN_PASS \
  --bootstrap-admin-url http://$HOST_NAME:5000/v3/ \
  --bootstrap-internal-url http://$HOST_NAME:5000/v3/ \
  --bootstrap-public-url http://$HOST_NAME:5000/v3/ \
  --bootstrap-region-id RegionOne
sed -i "s/#ServerName www.example.com:80/ServerName $HOST_NAME/g" /etc/httpd/conf/httpd.conf
ln -s /usr/share/keystone/wsgi-keystone.conf /etc/httpd/conf.d/
systemctl enable httpd.service
systemctl start httpd.service
# 导入临时环境变量
export OS_USERNAME=admin
export OS_PASSWORD=$ADMIN_PASS
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://$HOST_NAME:5000/v3
export OS_IDENTITY_API_VERSION=3

openstack project create --domain default --description "Service Project" service
openstack role create user

# Keystone环境变量脚本的创建
cat > /etc/keystone/admin-openrc.sh << EOF
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=$ADMIN_PASS
export OS_AUTH_URL=http://$HOST_NAME:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF

echo Done-iaas-install-keystone
