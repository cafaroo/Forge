# Forge production deployment

Production runs from a reviewed `prod` branch and an annotated
`prod-vYYYY.MM.DD.N` tag. Deploying a tag is an explicit operator action;
ordinary pushes to `main` do not change production.

The host keeps its secrets in `/etc/forge-prod/forge.env` (mode 0600) and a
checkout in `/opt/forge-src`. The local Docker Compose override
`compose.prod.yml` binds only the web console to `FORGE_BIND_IP`, keeps the
API on the Docker network, and restarts all services after a host reboot.

Deploy:

```sh
/opt/forge-src/scripts/deploy-prod.sh prod-vYYYY.MM.DD.N
```

To revert, deploy the previous tag with the same command. Database migrations
may need a separate rollback plan; review migrations before promoting a tag.
