# Add after store-*
# TODO: separate
# For tunnel to the real web server

# set upstream:
#upstream azbykar {
#    server azbykar.azbyka.ru:80;
#    keepalive 128;
#}
#
# use:
#    proxy_pass http://azbykar;
#    include include/trans-reproxy.conf;

# do not forget in server {
# http://sysoev.ru/nginx/docs/http/ngx_http_realip_module.html
# set_real_ip_from   91.232.225.22;
# real_ip_header     X-Real-IP;
#

#include include/trans-mediateproxy.conf;

# http://www.pentarh.com/wp/2008/07/18/using-nginx-apache/
proxy_set_header Connection close;

proxy_set_header Host $host;

# set X-Forwarded-For from $remote_addr or from upstream nginx
set $ourremote_addr $remote_addr;
if ($proxy_add_x_forwarded_for = "") {
    set $ourremote_addr $proxy_add_x_forwarded_for;
}

proxy_set_header X-Real-IP $ourremote_addr;

# Нужно для модуля RPAF в Apache, в котором указывается RPAFheader X-Forwarded-For
# http://padlik.ru/entries/86.html
proxy_set_header X-Forwarded-For $ourremote_addr;

# it will container port/IP
proxy_set_header X-Forwarded-By    $server_addr:$server_port;

# set X-Forwarded from $scheme or from upstream nginx
set $ourscheme $scheme;
if ( $http_x_forwarded_proto != "") {
    set $ourscheme $http_x_forwarded_proto;
}
proxy_set_header  X-Forwarded-Proto $ourscheme;


# permanent connection
# http://nginx.org/ru/docs/http/ngx_http_upstream_module.html#keepalive
proxy_http_version 1.1;
proxy_set_header Connection "";

# Чтобы апач не пытался ничего сжимать (нужно для sub_filter и вообще)
proxy_set_header Accept-Encoding "";

