#!/bin/bash
set -ex
# 加载环境变量
source openrc.sh
# 安装软件包
yum -y install openstack-dashboard
# 主配置文件设置
sed -i "/^OPENSTACK_HOST =/cOPENSTACK_HOST = \"$HOST_NAME\"" /etc/openstack-dashboard/local_settings
sed -i "/^ALLOWED_HOSTS =/cALLOWED_HOSTS = ['*','localhost']" /etc/openstack-dashboard/local_settings
sed -i "/^#SESSION_ENGINE =/cSESSION_ENGINE = 'django.contrib.sessions.backends.cache'" /etc/openstack-dashboard/local_settings
sed -i "/^TIME_ZONE =/cTIME_ZONE=\"Asia/Shanghai\"" /etc/openstack-dashboard/local_settings
sed -i "/#CACHES = {/i\CACHES = {\n    'default': {\n        'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache',\n        'LOCATION': '$HOST_NAME:11211',\n    },\n}" /etc/openstack-dashboard/local_settings
sed -i '/OPENSTACK_KEYSTONE_URL = /aOPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True' /etc/openstack-dashboard/local_settings
sed -i '/OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = /aOPENSTACK_API_VERSIONS = {\n    \"identity\": 3,\n    \"image\": 2,\n    \"volume\": 3,\n}' /etc/openstack-dashboard/local_settings
sed -i '/OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = /aOPENSTACK_KEYSTONE_DEFAULT_DOMAIN = \"Default\"\nOPENSTACK_KEYSTONE_DEFAULT_ROLE = \"user\"' /etc/openstack-dashboard/local_settings
sed -i "/WSGISocketPrefix run\/wsgi/a\WSGIApplicationGroup %{GLOBAL}" /etc/httpd/conf.d/openstack-dashboard.conf
ln -s /etc/openstack-dashboard /usr/share/openstack-dashboard/openstack_dashboard/conf
sed -i "/^WEBROOT = /cWEBROOT = '/dashboard'  # from openstack_auth" /usr/share/openstack-dashboard/openstack_dashboard/defaults.py
sed -i "/WEBROOT = /cWEBROOT = '/dashboard'" /usr/share/openstack-dashboard/openstack_dashboard/test/settings.py
sed -i "/ExecCGI/aRequire all granted" /usr/share/keystone/wsgi-keystone.conf

# I don't know why the Xena version repo but download 20 version dashboard package,
# for that reason, two codes are not absolutely the same, so here 20 need to be
# compatible.
mkdir /usr/share/openstack-dashboard/openstack_dashboard/wsgi
cat >> /usr/share/openstack-dashboard/openstack_dashboard/wsgi/django.wsgi << EOF
# Copyright (c) 2017 OpenStack Foundation.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
WSGI config for openstack_dashboard project.
"""

import logging
import os
import sys

from django.core.wsgi import get_wsgi_application

# Add this file path to sys.path in order to import settings
sys.path.insert(0, os.path.normpath(os.path.join(
    os.path.dirname(os.path.realpath(__file__)), '../..')))
os.environ['DJANGO_SETTINGS_MODULE'] = 'openstack_dashboard.settings'
sys.stdout = sys.stderr

logging.warning(
    "Use of this 'djano.wsgi' file has been deprecated since the Rocky "
    "release in favor of 'wsgi.py' in the 'openstack_dashboard' module. This "
    "file is a legacy naming from before Django 1.4 and an importable "
    "'wsgi.py' is now the default. This file will be removed in the T release "
    "cycle."
)

application = get_wsgi_application()
EOF

# 重启服务
systemctl restart httpd.service memcached.service

printf "\033[35mNow dashboard done, visit at http://HOST_IP/dashboard.\nNOTE: port 6080 may be rejected by your security rules.\n\033[0m"

echo Done-iaas-install-dashboard
