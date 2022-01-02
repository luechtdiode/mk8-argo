FROM alpine:3.15.0 AS nginx-naxsi-build

#Config files and some ideas taken from
# https://github.com/Epheo/docker-naxsi-proxy-waf/

RUN apk update && apk upgrade

#Software versions  
#nginx - see latest tags on http://nginx.org/en/download.html
ENV NGINX_VERSION 1.21.5

# naxsi - see latest tags on https://github.com/nbs-system/naxsi/releases
ENV NAXSI_VERSION 1.3

# see latest tags on https://github.com/openresty/headers-more-nginx-module/tags
ENV NGX_VERSION 0.33

# see latest tags on https://www.openssl.org
ENV OPENSSL_VERSION 3.0.1

RUN set -ex && \
    addgroup -S nginx && \
    adduser \
        -D \
        -S \
        -h /var/cache/nginx \
        -s /sbin/nologin \
        -G nginx \
        nginx
#Install dependencies
RUN apk add --no-cache --virtual .build-deps \
        wget \
        tar \
        clang \
        gcc \
        gd-dev \
        geoip-dev \
        gettext \
        libc-dev \
        libxslt-dev \
        linux-headers \
        pcre \
        pcre-dev \
        make \
        openssl-dev \
        pcre-dev \
        zlib-dev

WORKDIR /tmp

# openssl
RUN wget https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz &&  tar -xzvf openssl-${OPENSSL_VERSION}.tar.gz && rm openssl-${OPENSSL_VERSION}.tar.gz
    
# Nginx
RUN wget http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && tar xf nginx-${NGINX_VERSION}.tar.gz && rm -f nginx-${NGINX_VERSION}.tar.gz

# headers-more-nginx-module 
# see https://github.com/openresty/headers-more-nginx-module#readme
# see https://www.nginx.com/resources/wiki/modules/headers_more/
RUN wget https://github.com/openresty/headers-more-nginx-module/archive/v${NGX_VERSION}.tar.gz &&  tar -xzf v${NGX_VERSION}.tar.gz && rm v${NGX_VERSION}.tar.gz

# Naxsi see https://github.com/nbs-system/naxsi/wiki/naxsi-setup
RUN wget https://github.com/nbs-system/naxsi/archive/${NAXSI_VERSION}.zip && unzip ${NAXSI_VERSION}.zip && rm ${NAXSI_VERSION}.zip

RUN wget https://github.com/AirisX/nginx_cookie_flag_module/archive/v1.1.0.tar.gz && tar xf v1.1.0.tar.gz && rm -f v1.1.0.tar.gz

# Compiling nginx with naxsi
RUN cd nginx-${NGINX_VERSION} && CC=clang CFLAGS="-pipe -O" ./configure \
        --prefix=/etc/nginx \
        --sbin-path=/usr/sbin/nginx \
        --modules-path=/usr/lib/nginx/modules \
        --conf-path=/etc/nginx/nginx.conf \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --pid-path=/var/run/nginx.pid \
        --lock-path=/var/run/nginx.lock \
        --http-client-body-temp-path=/var/cache/nginx/client_temp \
        --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
        --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
        --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
        --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
        --user=nginx \
        --group=nginx \
        --add-module=../naxsi-${NAXSI_VERSION}/naxsi_src/ \
        --add-module=../nginx_cookie_flag_module-1.1.0 \
        --add-module=../headers-more-nginx-module-${NGX_VERSION} \
        --with-openssl=../openssl-${OPENSSL_VERSION} \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_gzip_static_module \
        --with-http_realip_module \
        --with-http_addition_module \
        --with-http_sub_module \
        --with-http_dav_module \
        --with-http_flv_module \
        --with-http_mp4_module \
        --with-http_gunzip_module \
        --with-http_gzip_static_module \
        --with-http_random_index_module \
        --with-http_secure_link_module \
        --with-http_stub_status_module \
        --with-http_auth_request_module \
        --with-http_xslt_module=dynamic \
        --with-http_image_filter_module=dynamic \
        --with-http_geoip_module=dynamic \
        --with-threads \
        --with-stream \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
        --with-stream_realip_module \
        --with-stream_geoip_module=dynamic \
        --with-http_slice_module \        
        --without-mail_pop3_module \
        --without-mail_smtp_module \
        --without-mail_imap_module \
        --without-http_uwsgi_module \
        --without-http_scgi_module && \
    make -j$(getconf _NPROCESSORS_ONLN) && \
    make install && \
    strip /usr/sbin/nginx*&& \
	ln -sf /dev/stdout /var/log/nginx/access.log && \
	ln -sf /dev/stderr /var/log/nginx/error.log

RUN rm -rf nginx-${NGINX_VERSION} naxsi-${NAXSI_VERSION} nginx_cookie_flag_module-1.1.0 headers-more-nginx-module-${NGX_VERSION} && \
    mv /usr/bin/envsubst /tmp/ && \
    run_deps="$( \
        scanelf \
                --needed \
                --nobanner \
                /usr/sbin/nginx \
                /usr/lib/nginx/modules/*.so \
                /tmp/envsubst \
            | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
            | sort -u \
            | xargs -r apk info --installed \
            | sort -u \
        )"  && \
    apk add --no-cache --virtual .nginx-run-deps $run_deps && \    
    apk del .build-deps && \
    mv /tmp/envsubst /usr/local/bin/
    
FROM scratch
LABEL maintainer "Roland Seidel <luechtdiode@interpolar.ch>"

COPY --from=nginx-naxsi-build / /

# add dhparam.pem file see https://gist.github.com/plentz/6737338
# RUN openssl dhparam -out /etc/nginx/ssl/dhparam.pem 2048
ADD ssl/dhparam.pem /etc/nginx/ssl/

STOPSIGNAL SIGTERM

#Ports
EXPOSE 80
EXPOSE 443

CMD ["nginx"]
