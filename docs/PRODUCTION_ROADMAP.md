# Deployment Roadmap: Secure Nextcloud Stack

This roadmap outlines the systematic deployment of the Nextcloud Stack onto a clean Linux VPS. The architecture enforces **Rootless Podman** execution for maximum security.

## Phase 1: Infrastructure Provisioning (VPS)
1. **Initial Connection:** Establish SSH access as `root`.
2. **System Update:** Apply latest security patches.
   ```bash
   apt-get update && apt-get upgrade -y
   ```
3. **Dependency Installation:** Ensure core tools are present.
   ```bash
   apt-get install -y podman podman-compose git curl openssl
   ```

## Phase 2: Security Hardening & User Setup
The goal is to create a dedicated user that has **zero** system-wide privileges, only the ability to run containers.

1. **Create Service User:**
   ```bash
   # Create a locked user with no shell access
   useradd -m -s /usr/sbin/nologin nextcloud-stack
   ```
2. **Namespace Isolation:** Configure UID/GID mapping for rootless containers.
   ```bash
   # Allocate sub-uids/gids
   echo "nextcloud-stack:100000:65536" >> /etc/subuid
   echo "nextcloud-stack:100000:65536" >> /etc/subgid
   ```
3. **Permission Scoping:** Restrict the user to only necessary directories.
   - Owner of `/home/nextcloud-stack/nextcloud-docker-stack`.
   - No access to system files outside of standard container paths.

## Phase 3: Project Deployment
1. **Clone Repository:**
   ```bash
   sudo -u nextcloud-stack git clone https://github.com/suraiya8239/nextcloud-docker-stack.git /home/nextcloud-stack/nextcloud-docker-stack
   ```
2. **Configuration:**
   - Initialize `.env` with strict `600` permissions.
   - Configure TLS/SSL certificates in `config/ssl/`.
3. **Automated Launch:**
   ```bash
   sudo -u nextcloud-stack bash /home/nextcloud-stack/nextcloud-docker-stack/setup.sh --rootless --domain yourdomain.com
   ```

## Phase 4: System Integration & Auto-Start
1. **Socket Activation:** Enable systemd socket activation for the user service.
   ```bash
   loginctl enable-linger nextcloud-stack
   ```
2. **Systemd Service Setup:** Configure the stack to restart on boot.
   - Use `systemctl --user` to manage the stack as the `nextcloud-stack` user, not root.

## Phase 5: Verification & Audit
1. **User Privilege Check:**
   ```bash
   # Verify that no root privileges are held
   sudo -u nextcloud-stack sudo whoami # Should fail
   ```
2. **Container Status:**
   ```bash
   sudo -u nextcloud-stack podman ps
   ```
3. **Security Audit:** Run the built-in audit script.
   ```bash
   sudo -u nextcloud-stack bash /home/nextcloud-stack/nextcloud-docker-stack/scripts/security-audit.sh
   ```
