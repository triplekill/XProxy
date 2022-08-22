FROM alpine:3.16 AS upx
ENV UPX_VERSION="3.96"
RUN sed -i 's/v3.\d\d/v3.15/' /etc/apk/repositories && \
    apk add bash build-base perl ucl-dev zlib-dev
RUN wget https://github.com/upx/upx/releases/download/v${UPX_VERSION}/upx-${UPX_VERSION}-src.tar.xz && \
    tar xf upx-${UPX_VERSION}-src.tar.xz
WORKDIR ./upx-${UPX_VERSION}-src/
RUN make -C ./src/ && mkdir -p /upx/bin/ && mv ./src/upx.out /upx/bin/upx && \
    mkdir -p /upx/lib/ && cd /usr/lib/ && cp -d ./libgcc_s.so* ./libstdc++.so* ./libucl.so* /upx/lib/

FROM golang:1.18-alpine3.16 AS xray
ENV XRAY_VERSION="1.5.9"
RUN wget https://github.com/XTLS/Xray-core/archive/refs/tags/v${XRAY_VERSION}.tar.gz && tar xf v${XRAY_VERSION}.tar.gz
WORKDIR ./Xray-core-${XRAY_VERSION}/
RUN go mod download -x
RUN env CGO_ENABLED=0 go build -v -o xray -trimpath -ldflags "-s -w" ./main/ && mv ./xray /tmp/
COPY --from=upx /upx/ /usr/
RUN upx -9 /tmp/xray

FROM golang:1.18-alpine3.16 AS v2ray
ENV V2FLY_VERSION="4.45.2"
RUN wget https://github.com/v2fly/v2ray-core/archive/refs/tags/v${V2FLY_VERSION}.tar.gz && tar xf v${V2FLY_VERSION}.tar.gz
WORKDIR ./v2ray-core-${V2FLY_VERSION}/
RUN go mod download -x
RUN env CGO_ENABLED=0 go build -v -o v2ray -trimpath -ldflags "-s -w" ./main/ && mv ./v2ray /tmp/
COPY --from=upx /upx/ /usr/
RUN upx -9 /tmp/v2ray

FROM golang:1.18-alpine3.16 AS sagray
ENV SAGER_VERSION="5.0.16"
RUN wget https://github.com/SagerNet/v2ray-core/archive/refs/tags/v${SAGER_VERSION}.tar.gz && tar xf v${SAGER_VERSION}.tar.gz
WORKDIR ./v2ray-core-${SAGER_VERSION}/
RUN go mod download -x
RUN env CGO_ENABLED=0 go build -v -o sagray -trimpath -ldflags "-s -w" ./main/ && mv ./sagray /tmp/
COPY --from=upx /upx/ /usr/
RUN upx -9 /tmp/sagray

FROM golang:1.18-alpine3.16 AS xproxy
COPY . /XProxy
WORKDIR /XProxy
RUN env CGO_ENABLED=0 go build -v -o xproxy -trimpath \
    -ldflags "-X 'main.goVersion=$(go version)' -s -w" ./cmd/ && mv ./xproxy /tmp/
COPY --from=upx /upx/ /usr/
RUN upx -9 /tmp/xproxy

FROM alpine:3.16 AS asset
WORKDIR /tmp/
RUN apk add xz
RUN wget "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
RUN wget "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
RUN mkdir -p /asset/ && tar cJf /asset/assets.tar.xz ./*.dat
COPY --from=xproxy /tmp/xproxy /asset/usr/bin/
COPY --from=sagray /tmp/sagray /asset/usr/bin/
COPY --from=v2ray /tmp/v2ray /asset/usr/bin/
COPY --from=xray /tmp/xray /asset/usr/bin/

FROM alpine:3.16
RUN apk add --no-cache dhcp iptables ip6tables radvd && \
    mkdir -p /run/radvd/ && rm -f /etc/dhcp/dhcpd.conf.example && \
    touch /var/lib/dhcp/dhcpd.leases && touch /var/lib/dhcp/dhcpd6.leases
COPY --from=asset /asset/ /
WORKDIR /xproxy
ENTRYPOINT ["xproxy"]
