FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    sudo \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash testuser \
    && echo 'testuser ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

WORKDIR /home/testuser/dotfiles
COPY . .
RUN chown -R testuser:testuser /home/testuser

USER testuser
ENV HOME=/home/testuser

ENV MAIL_MODE=bridge
ENV PROXY_HOST_PORT=proxy.invalid:8080

RUN ./install.sh --name "Test User" --email "test@example.com"

RUN command -v stunnel && command -v msmtp

RUN test -f "$HOME/.config/stunnel/fastmail.conf" \
    && grep -q '^connect = proxy.invalid:8080' "$HOME/.config/stunnel/fastmail.conf" \
    && grep -q '^protocol = connect' "$HOME/.config/stunnel/fastmail.conf" \
    && grep -q '^protocolHost = imap.fastmail.com:993' "$HOME/.config/stunnel/fastmail.conf" \
    && grep -q '^protocolHost = smtp.fastmail.com:465' "$HOME/.config/stunnel/fastmail.conf"

# The bridge must never trade away certificate verification; that is the whole
# reason it is stunnel and not a socat listener.
RUN test "$(grep -c '^verifyChain = yes' "$HOME/.config/stunnel/fastmail.conf")" = "2" \
    && grep -q '^checkHost = imap.fastmail.com' "$HOME/.config/stunnel/fastmail.conf" \
    && grep -q '^checkHost = smtp.fastmail.com' "$HOME/.config/stunnel/fastmail.conf" \
    && ! grep -q '127.0.0.1' "$HOME/.config/stunnel/fastmail.conf"

# stunnel itself is the only real judge of whether the generated file parses.
RUN timeout 5 stunnel "$HOME/.config/stunnel/fastmail.conf" || true; \
    grep -q 'Configuration successful' "$HOME/.local/state/stunnel-fastmail.log"

RUN test "$(stat -c %a "$HOME/.msmtprc")" = "600" \
    && grep -q '^host localhost' "$HOME/.msmtprc" \
    && grep -q '^port 1465' "$HOME/.msmtprc" \
    && grep -q '^from test@example.com' "$HOME/.msmtprc" \
    && grep -q 'passwordeval "\$HOME/bin/mail-pass"' "$HOME/.msmtprc" \
    && ! grep -qE '^password ' "$HOME/.msmtprc"

RUN grep -q '^Host localhost' "$HOME/.mbsyncrc" \
    && grep -q '^Port 1993' "$HOME/.mbsyncrc" \
    && grep -q '^SSLType None' "$HOME/.mbsyncrc" \
    && ! grep -q 'imap.fastmail.com' "$HOME/.mbsyncrc"

RUN grep -q '^set sendmail' "$HOME/.neomutt/local.rc" \
    && ! grep -q '^set smtp_url' "$HOME/.neomutt/local.rc"

# In bridge mode git must hand off to msmtp, and the three socket-mode keys
# have to be gone or git complains they are unused.
RUN test "$(git config --global --get sendemail.smtpserver)" = "$(command -v msmtp)" \
    && test -z "$(git config --global --get sendemail.smtpserverport || true)" \
    && test -z "$(git config --global --get sendemail.smtpencryption || true)" \
    && test -z "$(git config --global --get sendemail.smtpuser || true)"

# A container has no user service manager, so enabling the unit fails. Writing
# the unit and the rest of the config must still happen.
RUN test -f "$HOME/.config/systemd/user/stunnel-fastmail.service" \
    && grep -q '^ExecStart=.*stunnel' "$HOME/.config/systemd/user/stunnel-fastmail.service"

# The generated local.rc has to satisfy the header_cache setting in .neomuttrc,
# whatever backends this distro's neomutt was built with.
RUN neomutt -Q sendmail > /tmp/nm.log 2>&1; \
    cat /tmp/nm.log; \
    ! grep -qiE 'unknown option|errors in' /tmp/nm.log
