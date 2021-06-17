FROM crystallang/crystal:latest-alpine as build

WORKDIR /src/

COPY ./server.cr /src/
COPY ./shard.yml /src/
COPY ./color_diff.cr /src/
COPY ./color_data.json /src/

RUN apk add --update --upgrade --no-cache  ca-certificates openssl-dev openssl-libs-static

RUN shards install
RUN crystal build --release --static server.cr

CMD ["./server"]
