#! /bin/bash
sudo yum -y update; sudo yum clean all
sudo yum -y install http://nginx.org/packages/centos/7/noarch/RPMS/nginx-release-centos-7-0.el7.ngx.noarch.rpm; sudo yum -y makecache
sudo yum -y install nginx-1.14.0
sudo rm -f /etc/nginx/conf.d/default.conf
sudo cat <<__EOF__>/etc/nginx/nginx.conf
pid /run/nginx.pid;
worker_processes auto;
worker_rlimit_nofile 1024;
events {
        multi_accept on;
        worker_connections 1024;
}
http {
    upstream myapp {
        server INTERNAL_LOADBALANCER_IP;
    }

    server {
        listen 80 default_server;
        server_name "";
        location / {
            proxy_pass http://myapp;
            proxy_set_header Host \$host;
            proxy_http_version 1.1;
            proxy_read_timeout 120s;
        }
    }
}
__EOF__
sudo systemctl restart nginx