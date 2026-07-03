ARG ANVIL_SERVER_VERSION=latest
FROM anvilworks/anvil-app-server:${ANVIL_SERVER_VERSION}

USER root
# git + ssh client clone the app at runtime; util-linux provides setpriv to drop to the anvil user.
RUN (microdnf install -y git openssh-clients util-linux && microdnf clean all) \
    || (dnf install -y git openssh-clients util-linux && dnf clean all)
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
# Normalise line endings (strip CR) so the script runs regardless of host checkout settings.
RUN sed -i 's/\r$//' /usr/local/bin/docker-entrypoint.sh \
    && chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD []
