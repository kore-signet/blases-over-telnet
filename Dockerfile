FROM crystallang/crystal:latest-alpine as build

WORKDIR /build/

RUN apk add --update --upgrade --no-cache  ca-certificates openssl-dev openssl-libs-static

COPY . .

RUN shards install
RUN crystal build --release --static src/server.cr

CMD ["./server"]
