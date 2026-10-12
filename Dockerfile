FROM documenso/documenso:v2.20.0
# Railway volumes mount root-owned; the certificate lives on one.
USER root
COPY --chmod=755 railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
CMD ["/usr/local/bin/railway-entrypoint.sh"]
