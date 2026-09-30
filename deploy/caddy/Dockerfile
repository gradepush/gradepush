# TODO: Return to an official Caddy image when its Go runtime and dependencies pass the security gate.
FROM golang:1.27.1-alpine3.24@sha256:8a5910f31396cd4d89662f56c68b3ae31d374308270a1c3bd96672ee5ed43414 AS build
ENV GOTOOLCHAIN=local CGO_ENABLED=0
WORKDIR /src
COPY deploy/caddy/go.mod deploy/caddy/go.sum ./
RUN go mod download && go mod verify
COPY deploy/caddy/main.go ./
RUN go build -mod=readonly -trimpath -ldflags="-s -w" -o /caddy . \
    && cp /go/pkg/mod/github.com/caddyserver/caddy/v2@v2.11.4/LICENSE /CADDY-LICENSE
RUN go list -mod=readonly -m -f '{{if .Dir}}{{.Path}} {{.Dir}}{{end}}' all > /modules \
    && while read -r module directory; do \
         [ -n "$directory" ] || continue; \
         mkdir -p "/licenses/$module"; \
         find "$directory" -maxdepth 1 -type f \
           \( -iname 'license*' -o -iname 'copying*' -o -iname 'notice*' -o -iname 'copyright*' \) \
           -exec cp {} "/licenses/$module/" \;; \
       done < /modules

FROM alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6
RUN apk add --no-cache ca-certificates tzdata \
    && addgroup -S -g 10001 caddy \
    && adduser -S -D -H -u 10001 -G caddy caddy \
    && mkdir -p /data /config /etc/caddy \
    && chown 10001:10001 /data /config
COPY --from=build /caddy /usr/bin/caddy
COPY --from=build /CADDY-LICENSE /usr/share/licenses/caddy/LICENSE
COPY --from=build /licenses/ /usr/share/licenses/modules/
COPY deploy/caddy/go.mod deploy/caddy/go.sum /usr/share/licenses/gradepush/
COPY LICENSE /usr/share/licenses/gradepush/LICENSE
ENV XDG_CONFIG_HOME=/config XDG_DATA_HOME=/data
USER 10001:10001
EXPOSE 8080 8443 8443/udp
ENTRYPOINT ["caddy"]
CMD ["run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
