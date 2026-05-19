# Security basics

Some practical security things to know about.

## Secrets and passwords

Don't hardcode passwords in docker-compose.yaml. Put them in .env instead (and don't commit .env to git).

Bad:
```yaml
environment:
  POSTGRES_PASSWORD: MyPassword123
```

Good:
```bash
# .env (not in git)
POSTGRES_PASSWORD=MyPassword123

# docker-compose.yaml (in git)
environment:
  POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
```

Make sure .env is readable only by you:

```bash
chmod 600 .env
ls -l .env    # Should show: -rw------- 
```

Check .env is actually ignored:
```bash
git check-ignore .env
```

Passwords should be at least 16 characters with mix of upper, lower, numbers, and symbols.

Generate one with:
```bash
openssl rand -base64 32
```

## Modern Web Protocols

This stack is built for the 2026 web. We don't just use "standard" HTTPS; we enforce modern security:

*   **TLS 1.3 Only:** We've disabled older TLS versions (1.0, 1.1, 1.2) to prevent downgrade attacks. All encrypted traffic uses the latest standard.
*   **HTTP/3 (QUIC):** Enabled by default in Traefik. It provides faster handshakes and better performance over unreliable networks.
*   **HSTS (Strict Transport Security):** Configured to tell browsers to *only* ever talk to your cloud via HTTPS.

Check your protocols with curl:
```bash
# Check for HTTP/2 and TLS 1.3
curl -v -k https://localhost:8443 2>&1 | grep -E "ALPN|SSL connection using"

# Check for HTTP/3 advertisement
curl -I -k https://localhost:8443 | grep alt-svc
```

## SSL/TLS certificates

Let's Encrypt is automatic and free. Set it up and forget it. Make sure private keys are 600:

```bash
chmod 600 config/ssl/live/*/privkey.pem
```

Check when your certificate expires:
```bash
openssl x509 -enddate -noout -in config/ssl/live/example.com/fullchain.pem
```

## Access control

Add two-factor authentication to your admin account:
1. Log in as admin
2. Settings → Security → Two-Factor Authentication
3. Use any authenticator app

For apps (phone, desktop, etc.), create app-specific passwords with limited permissions instead of using your main password.

## Firewall

Only let in what you need:

```bash
# Just HTTPS
sudo ufw allow 443/tcp
sudo ufw deny 80/tcp

# Or rate limit to slow down attacks
sudo ufw limit 443/tcp
sudo ufw limit 22/tcp
```

## Backups

Backups matter. The script does it, but:
- Test restoring occasionally to make sure backups actually work
- Keep backups off the server (separate drive, cloud, etc.) if you can
- Encrypt backups if they're going to untrusted places

```bash
# Backup
bash scripts/backup.sh

# Test restore
bash scripts/backup.sh --restore /path/to/backup.tar.gz
```

## Container security

- Everything runs without root
- Database doesn't talk to the outside world
- Services have CPU and memory limits

## Monitoring

Watch the logs occasionally:

```bash
# Recent errors
docker-compose logs | grep -i error

# Failed login attempts
docker-compose logs | grep -i failed

# See what happened
docker-compose logs -f app
docker-compose logs -f traefik
```

## If something leaks

1. Change the password immediately:
   ```bash
   # For database
   docker-compose exec postgres psql -U postgres -c "ALTER USER nextcloud WITH PASSWORD 'new_pass';"
   
   # Update .env and restart
   docker-compose restart
   ```

2. Check the logs to see what was accessed

3. Revoke and renew the SSL certificate:
   ```bash
   ```

## Quick checklist

- .env is 600 permissions
- .env is in .gitignore
- SSL certificate is valid
- HTTPS is enabled
- Firewall is configured
- 2FA on admin account
- Backups work when restored
- Logs look normal
- No hardcoded passwords in config files

For more details, see the README.
