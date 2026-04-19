FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    bats \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /dotfiles
COPY . .

CMD ["bats", "tests/"]
