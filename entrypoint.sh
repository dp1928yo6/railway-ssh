#!/usr/bin/env bash
set -euo pipefail

SSH_PORT="${SSH_PORT:-22}"
DATA_DIR="${DATA_DIR:-/data}"
KEY_RE='^(ssh-(rsa|ed25519)|ecdsa-sha2-[a-z0-9-]+|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com) '

log() { printf '[railway-ssh] %s\n' "$*" >&2; }

if ! mkdir -p "$DATA_DIR" 2>/dev/null || [ ! -w "$DATA_DIR" ]; then
  log "warning: $DATA_DIR is not writable, falling back to /tmp/railway-ssh (state is lost on restart)"
  DATA_DIR=/tmp/railway-ssh
  mkdir -p "$DATA_DIR"
fi

mkdir -p /run/sshd /root/.ssh /etc/ssh/sshd_config.d
chmod 700 /root/.ssh
chown root:root /root/.ssh

# --- host keys: keep them stable across restarts when a volume is mounted ---
HOST_KEY_STORE="$DATA_DIR/ssh_host_keys"
mkdir -p "$HOST_KEY_STORE"
if compgen -G "$HOST_KEY_STORE/ssh_host_*_key" >/dev/null; then
  cp -f "$HOST_KEY_STORE"/ssh_host_* /etc/ssh/
  log "host keys restored from $HOST_KEY_STORE"
else
  ssh-keygen -A >/dev/null
  cp -f /etc/ssh/ssh_host_* "$HOST_KEY_STORE"/
  log "host keys generated and stored in $HOST_KEY_STORE"
fi
chmod 600 /etc/ssh/ssh_host_*_key
chown root:root /etc/ssh/ssh_host_*_key

# --- client keys ---
AUTH_KEYS=/root/.ssh/authorized_keys
: > "$AUTH_KEYS"

if [ -n "${AUTHORIZED_KEYS:-}" ]; then
  printf '%s\n' "$AUTHORIZED_KEYS" | sed -e 's/\\n/\n/g' -e 's/\r$//' | grep -E "$KEY_RE" >> "$AUTH_KEYS" || true
fi
if [ -n "${AUTHORIZED_KEYS_B64:-}" ]; then
  printf '%s' "$AUTHORIZED_KEYS_B64" | base64 -d 2>/dev/null | sed 's/\r$//' | grep -E "$KEY_RE" >> "$AUTH_KEYS" || true
fi

OWN_ID_FILE="$DATA_DIR/bootstrap_ed25519"
if ! grep -qE "$KEY_RE" "$AUTH_KEYS"; then
  if [ "${AUTO_GENERATE_KEY:-1}" = "1" ]; then
    if [ ! -f "$OWN_ID_FILE" ]; then
      ssh-keygen -t ed25519 -N '' -C "railway-ssh bootstrap" -f "$OWN_ID_FILE" >/dev/null
      log "bootstrap identity created at $OWN_ID_FILE"
    fi
    cat "$OWN_ID_FILE.pub" >> "$AUTH_KEYS"
    log "no AUTHORIZED_KEYS given: using the generated bootstrap identity (shown on the login screen)"
  else
    log "warning: no client key configured and AUTO_GENERATE_KEY=0, nobody can log in over SSH"
  fi
fi

sort -u "$AUTH_KEYS" -o "$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"

# --- runtime sshd settings ---
RUNTIME_CONF=/etc/ssh/sshd_config.d/99-railway-runtime.conf
{
  printf 'Port %s\n' "$SSH_PORT"
  if [ -n "${ROOT_PASSWORD:-}" ]; then
    printf 'PasswordAuthentication yes\nKbdInteractiveAuthentication yes\n'
  fi
} > "$RUNTIME_CONF"

PERMIT_ROOT=prohibit-password
if [ -n "${ROOT_PASSWORD:-}" ]; then
  printf 'root:%s\n' "$ROOT_PASSWORD" | chpasswd
  PERMIT_ROOT=yes
  log "password login for root enabled because ROOT_PASSWORD is set"
else
  # a locked account (! in /etc/shadow) is refused by sshd even for key logins
  usermod -p '*' root 2>/dev/null || sed -i 's/^root:[^:]*:/root:*:/' /etc/shadow
fi
printf 'PermitRootLogin %s\n' "$PERMIT_ROOT" >> "$RUNTIME_CONF"
chmod 600 "$RUNTIME_CONF"

# --- connection info for the login banner ---
PROXY_HOST="${RAILWAY_TCP_PROXY_DOMAIN:-}"
PROXY_PORT="${RAILWAY_TCP_PROXY_PORT:-}"
WEB_HOST="${RAILWAY_PUBLIC_DOMAIN:-}"

{
  echo "Railway SSH box - logged in as root"
  echo "-------------------------------------------------------------"
  if [ -n "$PROXY_HOST" ] && [ -n "$PROXY_PORT" ]; then
    echo "SSH from your computer:"
    echo "  ssh -p ${PROXY_PORT} root@${PROXY_HOST}"
    echo "  host ${PROXY_HOST}   port ${PROXY_PORT}"
  else
    echo "SSH: TCP Proxy is not enabled yet."
    echo "  Railway -> service -> Settings -> Networking -> TCP Proxy"
    echo "  target port: ${SSH_PORT}"
  fi
  if [ -n "$WEB_HOST" ]; then
    echo "This service: https://${WEB_HOST}"
  fi
  echo "sshd listens on 0.0.0.0:${SSH_PORT} inside the container"
  echo "-------------------------------------------------------------"
} > /etc/motd

if [ -f "$OWN_ID_FILE" ] && ! grep -qE "$KEY_RE" <<<"${AUTHORIZED_KEYS:-}"; then
  {
    echo ""
    echo "No key from your own computer is registered yet."
    echo "Log in with the identity below, then set AUTHORIZED_KEYS to your own"
    echo "public key and redeploy (this bootstrap identity is then not shown):"
    echo ""
    sed 's/^/    /' "$OWN_ID_FILE"
  } >> /etc/motd
fi

log "clients connect to ${PROXY_HOST:-<tcp-proxy-domain>}:${PROXY_PORT:-<tcp-proxy-port>} -> container port ${SSH_PORT}"
log "authorized client keys: $(grep -cE "$KEY_RE" "$AUTH_KEYS")"

/usr/sbin/sshd -t
log "starting sshd on 0.0.0.0:${SSH_PORT}"
exec /usr/sbin/sshd -D -e
