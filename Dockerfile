FROM crystallang/crystal:latest-alpine as build

WORKDIR /build/

COPY . .

RUN apk add --update --upgrade --no-cache  ca-certificates openssl-dev openssl-libs-static

RUN shards install
RUN crystal build --release --static src/server.cr

CMD ["./server"]
