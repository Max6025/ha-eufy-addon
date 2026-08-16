#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
set -e

bashio::log.info "Eufy Max WS wird gestartet"

USERNAME=$(bashio::config 'username')
PASSWORD=$(bashio::config 'password')

if bashio::var.is_empty "${USERNAME}" || bashio::var.is_empty "${PASSWORD}"; then
    bashio::exit.nok "Benutzername und Passwort muessen in der Konfiguration gesetzt sein"
fi

COUNTRY=$(bashio::config 'country')
LANGUAGE=$(bashio::config 'language')
TRUSTED_DEVICE_NAME=$(bashio::config 'trusted_device_name')
EVENT_DURATION_SECONDS=$(bashio::config 'event_duration_seconds')
ACCEPT_INVITATIONS=$(bashio::config 'accept_invitations')
POLLING_INTERVAL_MINUTES=$(bashio::config 'polling_interval_minutes')

export USERNAME PASSWORD COUNTRY LANGUAGE TRUSTED_DEVICE_NAME
export EVENT_DURATION_SECONDS ACCEPT_INVITATIONS POLLING_INTERVAL_MINUTES
export PORT=3000

if bashio::config.true 'debug'; then
    export DEBUG="eufy-security-client:*"
    bashio::log.info "Debug-Modus aktiv"
fi

# Das npm-Paket legt keinen ausfuehrbaren Befehl an, die server.js wird
# direkt mit Node gestartet.
SERVER="/opt/eufy/node_modules/eufy-security-ws/dist/bin/server.js"

if [ ! -f "${SERVER}" ]; then
    bashio::log.warning "Server nicht am erwarteten Ort, suche im Dateisystem"
    SERVER=$(find / -path /proc -prune -o -name "server.js" -path "*eufy-security-ws*" -print 2>/dev/null | head -n 1)
fi

if [ -z "${SERVER}" ] || [ ! -f "${SERVER}" ]; then
    bashio::exit.nok "eufy-security-ws wurde im Image nicht gefunden - Add-on neu bauen"
fi

bashio::log.info "Starte ${SERVER}"

# Discovery erst nach dem Start melden, damit die Integration nicht in
# einen noch nicht lauschenden Port rennt.
(
    sleep 8
    DISCOVERY_CONFIG=$(bashio::var.json host "$(hostname)" port "^3000")
    if bashio::discovery "eufy_max" "${DISCOVERY_CONFIG}" > /dev/null; then
        bashio::log.info "Integration ueber Discovery benachrichtigt"
    else
        bashio::log.warning "Discovery fehlgeschlagen - Integration von Hand einrichten"
    fi
) &

bashio::log.info "Server laeuft auf Port 3000 (Host: $(hostname))"

exec node "${SERVER}"
