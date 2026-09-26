FROM fedora:latest

RUN dnf install -y \
    bash \
    bats \
    ca-certificates \
    git \
    && dnf clean all

WORKDIR /dotfiles
COPY . .

CMD ["bats", "tests/"]
