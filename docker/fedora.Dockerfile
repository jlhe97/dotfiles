FROM fedora:latest

RUN dnf install -y \
    bash \
    bats \
    && dnf clean all

WORKDIR /dotfiles
COPY . .

CMD ["bats", "tests/"]
