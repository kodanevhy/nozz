#!/bin/bash
set -ex
source openrc.sh

if [[ ! -n "$(echo $HOST_IP)" ]];then
    echo "HOST_IP none"
    exit 1
fi
if [[ ! -n "$(echo $HOST_NAME)" ]];then
    echo "HOST_NAME none"
    exit 1
fi

function correct_repo() {
    sed -i -e "s|mirrorlist=|#mirrorlist=|g" /etc/yum.repos.d/CentOS-*
    sed -i -e "s|#baseurl=http://mirror.centos.org|baseurl=https://mirrors.aliyun.com|g" /etc/yum.repos.d/CentOS-*
}

# 配置基础网络环境
systemctl stop firewalld.service || echo ''
systemctl disable firewalld.service >> /dev/null 2>&1 || echo ''
sed -i 's/SELINUX=.*/SELINUX=permissive/g' /etc/selinux/config
setenforce 0
yum remove -y firewalld
correct_repo
yum -y install iptables-services
systemctl enable iptables
systemctl restart iptables
iptables -F
iptables -X
iptables -Z
service iptables save
if [[ `ip a |grep -w $HOST_IP ` != '' ]];then
	hostnamectl set-hostname $HOST_NAME
else
  echo "Incorrect host ip: $HOST_IP"
	exit 1
fi
sed -i -e "/$HOST_NAME/d" /etc/hosts
echo "$HOST_IP $HOST_NAME" >> /etc/hosts
sed -i -e 's/#UseDNS yes/UseDNS no/g' -e 's/GSSAPIAuthentication yes/GSSAPIAuthentication no/g' /etc/ssh/sshd_config

yum config-manager --set-enabled powertools
cat >> /etc/yum.repos.d/CentOS-aliyun.repo << EOF
[extras-aliyun]
name=extras-aliyun
baseurl=https://mirrors.aliyun.com/centos/8-stream/extras/\$basearch/os/
enable=1
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-Official
EOF
# Get the OpenStack xena repo files, and then correct the repo url.
yum -y install centos-release-openstack-xena
correct_repo
# The official OpenStack xena repo files are not able to download packages,
# didn't know the reason yet, so just replace the baseurl from official
# to aliyun which tested passed.
sed -i '8d' /etc/yum.repos.d/CentOS-OpenStack-xena.repo
xena_baseurl_entry="baseurl=https://mirrors.aliyun.com/centos/8-stream/cloud/\$basearch/openstack-xena/"
sed -i "/\[centos-openstack-xena\]/a$xena_baseurl_entry" /etc/yum.repos.d/CentOS-OpenStack-xena.repo

# Fix the centos-ceph-pacific repo baseurl error.
sed -i '9d' /etc/yum.repos.d/CentOS-Ceph-Pacific.repo
ceph_pacific_baseurl_entry="baseurl=https://mirrors.aliyun.com/centos/8/storage/\$basearch/ceph-nautilus/"
sed -i "/\[centos-ceph-pacific\]/a$ceph_pacific_baseurl_entry" /etc/yum.repos.d/CentOS-Ceph-Pacific.repo

yum -y upgrade
yum -y install openstack-selinux python3-openstackclient crudini

printf "\033[35mPlease reboot now\n\033[0m"

echo Done-iass-pre-host
