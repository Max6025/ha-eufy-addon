#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
set -e

bashio::log.info "Eufy Max WS wird gestartet"

USERNAME=$(bashio::config 'username')
PASSWORD=$(bashio::config 'password')

if bashio::var.is_empty "${USERNAME}" || bashio::var.is_empty "${PASSWORD}"; then
    bashio::exit.nok "Benutzername und Passwort muessen in der Konfiguration gesetzt sein"
fi

export USERNAME
export PASSWORD
export COUNTRY
export LANGUAGE
export PORT=3000
export TRUSTED_DEVICE_NAME
export EVENT_DURATION_SECONDS
export ACCEPT_INVITATIONS
export POLLING_INTERVAL_MINUTES

COUNTRY=$(bashio::config 'country')
LANGUAGE=$(bashio::config 'language')
TRUSTED_DEVICE_NAME=$(bashio::config 'trusted_device_name')
EVENT_DURATION_SECONDS=$(bashio::config 'event_duration_seconds')
ACCEPT_INVITATIONS=$(bashio::config 'accept_invitations')
POLLING_INTERVAL_MINUTES=$(bashio::config 'polling_interval_minutes')

if bashio::config.true 'debug'; then
    export DEBUG="eufy-security-client:*"
    bashio::log.info "Debug-Modus aktiv"
fi

# Der Integration mitteilen, wo wir erreichbar sind. Damit muss im
# Einrichtungsdialog nichts mehr von Hand eingetragen werden.
DISCOVERY_CONFIG=$(bashio::var.json \
    host "$(hostname)" \
    port "^3000" \
)

if bashio::discovery "eufy_max" "${DISCOVERY_CONFIG}" > /dev/null; then
    bashio::log.info "Integration wurde ueber Discovery benachrichtigt"
else
    bashio::log.warning "Discovery fehlgeschlagen - Integration ggf. von Hand einrichten"
fi

bashio::log.info "Server laeuft auf Port 3000 (Host: $(hostname))"

exec eufy-security-ws
