# Image of the openresty chart: the official OpenResty image plus
# lua-resty-http, which Lua handlers need to call other services (the
# official image ships cjson but not lua-resty-http). Build and push it to
# Harbor, then point image.repository and image.tag of the chart at it.
#
# The tag of the base image is the OpenResty version; keep appVersion of the
# chart equal to it.
ARG OPENRESTY_VERSION=1.27.1.2
FROM openresty/openresty:${OPENRESTY_VERSION}-alpine-fat

# opm installs into /usr/local/openresty/site/lualib, which is on the default
# lua_package_path of the image.
RUN opm get ledgetech/lua-resty-http

# The chart runs the container as nobody with a read-only root filesystem and
# an emptyDir at /tmp; the nginx.conf it mounts keeps the pid and the
# temporary files there, so nothing under /usr/local/openresty is written at
# run time.
USER 65534
EXPOSE 8080
