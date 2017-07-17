#!/usr/bin/bash -ex


yum install -y python-devel zlib-devel libxml2-devel \
               mysqlclient-devel libxslt-devel postgresql-devel git \
               libffi-devel gettext openssl-devel

yum -y groupinstall 'Development Tools'

easy_install pip
pip install -U pip
pip install virtualenv flake8 tox testrepository git-review
pip install -U virtualenv

git clone https://git.openstack.org/openstack-dev/devstack
devstack/tools/create-stack-user.sh

su -s /bin/sh -c "git clone https://git.openstack.org/openstack-dev/devstack /opt/stack/devstack" stack
su -s /bin/sh -c "cat > /opt/stack/devstack/local.conf << END
[[local|localrc]]

IP_VERSION=4
SERVICE_IP_VERSION=4

DATABASE_PASSWORD=password
RABBIT_PASSWORD=password
SERVICE_TOKEN=password
SERVICE_PASSWORD=password
ADMIN_PASSWORD=password


enable_plugin neutron-lbaas https://git.openstack.org/openstack/neutron-lbaas
enable_plugin octavia https://git.openstack.org/openstack/octavia
disable_service q-lbaas
enable_service q-lbaasv2
enable_service octavia
enable_service o-cw
enable_service o-hk
enable_service o-hm
enable_service o-api

disable_service horizon

enable_plugin heat https://git.openstack.org/openstack/heat
enable_plugin magnum https://git.openstack.org/openstack/magnum

ENABLED_SERVICES+=,octavia,o-cw,o-hk,o-hm,o-api
ENABLED_SERVICES+=,q-svc,q-agt,q-dhcp,q-l3,q-meta
ENABLED_SERVICES+=,q-lbaasv2


VOLUME_BACKING_FILE_SIZE=20G
END
" stack

su -s /bin/sh -c "/opt/stack/devstack/stack.sh" stack

cd /opt/stack/magnum
cp /opt/stack/tempest/etc/tempest.conf /opt/stack/magnum/etc/tempest.conf
cp functional_creds.conf.sample functional_creds.conf

# update the IP address
HOST=$(iniget /etc/magnum/magnum.conf api host)
PORT=$(iniget /etc/magnum/magnum.conf api port)
iniset functional_creds.conf auth auth_url "http://"$HOST"/v3"
iniset functional_creds.conf auth magnum_url "http://"$HOST":"$PORT"/v1"

# update admin password
source /opt/stack/devstack/openrc admin admin
iniset functional_creds.conf admin pass $OS_PASSWORD

# update demo password
source /opt/stack/devstack/openrc demo demo
iniset functional_creds.conf auth password $OS_PASSWORD

source /opt/stack/devstack/openrc demo demo

source /opt/stack/devstack/openrc admin admin
nova keypair-add --pub-key ~/.ssh/id_rsa.pub default
nova flavor-create  m1.magnum 100 1024 10 1
nova flavor-create  s1.magnum 200 512 10 1

source /opt/stack/devstack/openrc demo demo
nova keypair-add --pub-key ~/.ssh/id_rsa.pub default

tox -e functional-k8s -- --concurrency 1
