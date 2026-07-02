ARG ANVIL_SERVER_VERSION=latest
FROM anvilworks/anvil-app-server:${ANVIL_SERVER_VERSION}

USER root
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD []
