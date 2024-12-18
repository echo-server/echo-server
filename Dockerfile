FROM openresty/openresty:1.27.1.1-0-alpine-fat

RUN opm get bungle/lua-resty-template

# Copy nginx configuration files
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY nginx.vh.default.conf /etc/nginx/conf.d/default.conf
