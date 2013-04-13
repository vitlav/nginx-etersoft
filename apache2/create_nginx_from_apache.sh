#!/bin/sh

# TODO: исключения переделать на общий список
# по умолчанию - не кэшировать главную

. ./create_nginx.config


VEDIR=/var/lib/vz/root/$VEID

# Apache2
VHOSTSDIR=$VEDIR/etc/httpd2/conf/sites-enabled

NOCACHELIST=hosts_no_cache_main.list
NOIMAGEMISSING=hosts_no_image_missing.list

LOGFILE=$0.log
NGINXSITES=/etc/nginx/sites-enabled.d/generated


mkdir -p $NGINXSITES

check_if_nocache()
{
    local SITE="$1"
    test -r $NOCACHELIST || return
    grep -q $SITE $NOCACHELIST
}


check_if_nomissing()
{
    local SITE="$1"
    test -r $NOIMAGEMISSING || return
    grep -q $SITE $NOIMAGEMISSING
}

print_nginx_conf()
{
	local IP=$1 ROOT=$2 DOMAIN=$3 ALIASLIST="$4" SUBSERVER="$5" NOCACHE="$6"
cat <<EOF
   server {
EOF
if [ -n "$IP" ] ; then
cat <<EOF
        listen $IP;
EOF
fi
cat <<EOF
        server_name $DOMAIN www.$DOMAIN $ALIASLIST;

        # Разные запрещённые файлы и каталоги
        include include/deny.conf;

        # FIXME: более прямой способ задания root
        root $ROOT;

        set \$subserver http://$SUBSERVER;

EOF

if ! check_if_nomissing $DOMAIN ; then
cat <<EOF
        # Отдаём jpeg, png, gif напрямую. Не существуют - отдаём приготовленную картинку
        include include/static-stub.conf;
EOF
fi
cat <<EOF

        # пробуем отдать напрямую статикой, не получится - на @fallback
        include include/static-fallback.conf;

        # статистика nginx-stat
        include include/stat.conf;

#        # cache html/possibly generated pages
#        location ~* \.(htm|html|shtml)$ {
#              proxy_pass http://127.0.0.1:80;
#              include include/store-proxy.conf;
#        }

#        if (\$request_method = "POST" ) {
#              return 412;
#        }

        error_page 412 = @fallback;
EOF
if ! check_if_nocache $DOMAIN ; then
cat <<EOF

        # always cache main page
        location = / {
                # Пытаемся, чтобы redirect www был только для динамики
                include include/rewrite-www.conf;
                proxy_pass \$subserver;
                include include/store-proxy.conf;
        }
EOF
fi

cat <<EOF

        include include/stop-crack.conf;

        location / {
            # Пытаемся, чтобы redirect www был только для динамики
            include include/rewrite-www.conf;

            proxy_pass \$subserver;
            include include/trans-proxy.conf;
        }

        # Напрямую
        location @fallback {
            proxy_pass \$subserver;
            include include/trans-proxy.conf;
        }

        access_log  /var/log/nginx/$DOMAIN-access.log logdetail;
        error_log   /var/log/nginx/$DOMAIN-error.log;


    }
EOF

}



get_var()
{
	grep -i "^ *$2 " "$1" | head -n 1 | sed -e "s/^[ \t]*$2[ \t]*//g" | sed -e 's/"//g'
}

get_multivar()
{
	grep -i "^ *$2 " "$1" | sed -e "s/^[ \t]*$2[ \t]*//g" | sed -e 's/"//g'
}


echo > $LOGFILE
date >> $LOGFILE

create_nginx_conf()
{
for i in $VHOSTSDIR/*.conf ; do
	SITE=$(get_var $i ServerName)
	if [ ! -n "$SITE" ] ; then
		echo "Skipping $i..." | tee -a $LOGFILE
		continue
	fi
	DROOT=$(get_var $i DocumentRoot)
	ALIASLIST=$(get_multivar $i ServerAlias | xargs -n1 echo | sort -u | grep -v "^$SITE\$" | grep -v "^www.$SITE\$" | xargs echo)
	UDIR=$(dirname "$DROOT") ; UDIR=$(dirname "$UDIR") ; UDIR=$(basename "$UDIR")

	echo
	echo "Read from $(basename $i), main site: $SITE, USER: $UDIR, ALIASLIST: $ALIASLIST"

	if [ "$VHOSTSDIR/$SITE.conf" != "$i" ] ; then
		echo "Warning: server name $SITE is not compat with file name $i" | tee -a $LOGFILE
	fi
	if [ ! -d "$VEDIR$DROOT" ] ; then
		echo "Error: DocumentRoot $VEDIR$DROOT does not exists in file $i" | tee -a $LOGFILE
	fi

	if [ -r $NGINXSITES/../$SITE.conf ] ; then
		echo "Warning: Skip $SITE.conf as already exists" | tee -a $LOGFILE
		continue
	fi

	NOCACHE=$(check_if_nocache $SITE)
	print_nginx_conf "$LISTENIP" $VEDIR$DROOT $SITE "$ALIASLIST" "$APACHEHOST" "$NOCACHE" >$NGINXSITES/$SITE.conf.new
	if [ -r $NGINXSITES/$SITE.conf ] ; then
		if diff -u $NGINXSITES/$SITE.conf $NGINXSITES/$SITE.conf.new ; then
			echo "$NGINXSITES/$SITE.conf not changed"
			rm -f $NGINXSITES/$SITE.conf.new
		else
			mv -f $NGINXSITES/$SITE.conf.new $NGINXSITES/$SITE.conf
		fi
	else
		mv -f $NGINXSITES/$SITE.conf.new $NGINXSITES/$SITE.conf
	fi
done
}

create_nginx_conf

echo
echo "From vehosts.list:" | tee -a $LOGFILE
while read VEID VEIP VESUBDIR DOMAINS ; do
    [ -z "$VEID" ] && continue
    [ "$VEID" = "#" ] && continue
    echo "$VEID with $DOMAINS"
    VEDIR=/var/lib/vz/root/$VEID
    SITE=
    OTHERDOMAINS=
    for i in $DOMAINS ; do
        if [ -z "$SITE" ] ; then
            SITE=$i
        else
            OTHERDOMAINS="$OTHERDOMAINS $i www.$i"
        fi
    done
    if [ -r $NGINXSITES/../$SITE.conf ] ; then
        echo "Warning: Skip $SITE.conf as already exists" | tee -a $LOGFILE
        continue
    fi

    NOCACHE=$(check_if_nocache $SITE)
    print_nginx_conf "$LISTENIP" $VEDIR$VESUBDIR $SITE "$OTHERDOMAINS" "$VEIP:80" "$NOCACHE" >$NGINXSITES/$SITE.conf
done <vehosts.list
