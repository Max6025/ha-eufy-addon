#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
set -e

bashio::log.info "Eufy Max WS wird gestartet"

USERNAME=$(bashio::config 'username')
PASSWORD=$(bashio::config 'password')

if bashio::var.is_empty "${USERNAME}" || bashio::var.is_empty "${PASSWORD}"; then
    bashio::exit.nok "Benutzername und Passwort muessen in der Konfiguration gesetzt sein"
fi

CONFIG_FILE="/data/config.json"

# eufy-security-ws liest seine Einstellungen ausschliesslich aus einer
# config.json. Die wird hier bei jedem Start aus den Add-on-Optionen neu
# erzeugt, damit Aenderungen im UI sofort greifen.
jq -n \
    --arg username "${USERNAME}" \
    --arg password "${PASSWORD}" \
    --arg country "$(bashio::config 'country')" \
    --arg language "$(bashio::config 'language')" \
    --arg device "$(bashio::config 'trusted_device_name')" \
    --argjson event "$(bashio::config 'event_duration_seconds')" \
    --argjson invitations "$(bashio::config 'accept_invitations')" \
    --argjson polling "$(bashio::config 'polling_interval_minutes')" \
    '{
        username: $username,
        password: $password,
        country: $country,
        language: $language,
        trustedDeviceName: $device,
        eventDurationSeconds: $event,
        acceptInvitations: $invitations,
        pollingIntervalMinutes: $polling,
        host: "0.0.0.0",
        port: 3000
    }' > "${CONFIG_FILE}"

chmod 600 "${CONFIG_FILE}"

# Der Server nimmt keinen Pfad als Argument, sondern erwartet die Datei
# fest unter /config.json. Die eigentliche Datei bleibt in /data, damit
# sie persistent ist, und wird dorthin verlinkt.
ln -sf "${CONFIG_FILE}" /config.json

bashio::log.info "Konfiguration geschrieben nach ${CONFIG_FILE} (verlinkt nach /config.json)"

# Der Server bindet sonst nur auf localhost und ist damit aus dem
# HA-Core-Container nicht erreichbar.
export HOST="0.0.0.0"
export PORT=3000

if bashio::config.true 'debug'; then
    export DEBUG="eufy-security-client:*"
    bashio::log.info "Debug-Modus aktiv"
fi

SERVER="/opt/eufy/node_modules/eufy-security-ws/dist/bin/server.js"

if [ ! -f "${SERVER}" ]; then
    bashio::log.warning "Server nicht am erwarteten Ort, suche im Dateisystem"
    SERVER=$(find / -path /proc -prune -o -name "server.js" -path "*eufy-security-ws*" -print 2>/dev/null | head -n 1)
fi

if [ -z "${SERVER}" ] || [ ! -f "${SERVER}" ]; then
    bashio::exit.nok "eufy-security-ws wurde im Image nicht gefunden - Add-on neu bauen"
fi

# Discovery erst nach dem Start melden, damit die Integration nicht in
# einen noch nicht lauschenden Port rennt.
(
    sleep 10
    DISCOVERY_CONFIG=$(bashio::var.json host "$(hostname)" port "^3000")
    if bashio::discovery "eufy_max" "${DISCOVERY_CONFIG}" > /dev/null; then
        bashio::log.info "Integration ueber Discovery benachrichtigt"
    else
        bashio::log.warning "Discovery fehlgeschlagen - Integration von Hand einrichten"
    fi
) &

bashio::log.info "Server laeuft auf Port 3000 (Host: $(hostname))"

exec node "${SERVER}"
