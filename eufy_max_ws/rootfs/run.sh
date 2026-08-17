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

# Feste IP-Adressen der Stationen. Verhindert, dass sich Kameras ueber
# Eufys Cloud-Relay verbinden statt lokal - das Relay ist langsam und
# bricht haeufig weg. Format je Eintrag: SERIENNUMMER:IP
STATION_IPS="{}"
if bashio::config.has_value 'station_ip_addresses'; then
    STATION_IPS=$(bashio::config 'station_ip_addresses' \
        | jq -R -s 'split("\n")
                    | map(select(length > 0))
                    | map(split(":"))
                    | map(select(length == 2))
                    | map({(.[0] | ltrimstr(" ") | rtrimstr(" ")):
                           (.[1] | ltrimstr(" ") | rtrimstr(" "))})
                    | add // {}')
    bashio::log.info "Feste Stations-IPs: ${STATION_IPS}"
fi

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
    --argjson p2p "$(bashio::config 'p2p_connection_setup')" \
    --argjson stations "${STATION_IPS}" \
    '{
        username: $username,
        password: $password,
        country: $country,
        language: $language,
        trustedDeviceName: $device,
        eventDurationSeconds: $event,
        acceptInvitations: $invitations,
        pollingIntervalMinutes: $polling,
        p2pConnectionSetup: $p2p,
        stationIPAddresses: $stations,
        persistentDir: "/data"
    }' > "${CONFIG_FILE}"

chmod 600 "${CONFIG_FILE}"
bashio::log.info "Konfiguration geschrieben nach ${CONFIG_FILE}"

if bashio::config.true 'debug'; then
    VERBOSE="--verbose"
    bashio::log.info "Debug-Modus aktiv"
else
    VERBOSE=""
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
    sleep 12
    DISCOVERY_CONFIG=$(bashio::var.json host "$(hostname)" port "^3000")
    if bashio::discovery "eufy_max" "${DISCOVERY_CONFIG}" > /dev/null; then
        bashio::log.info "Integration ueber Discovery benachrichtigt"
    else
        bashio::log.warning "Discovery fehlgeschlagen - Integration von Hand einrichten"
    fi
) &

# WICHTIG: Host, Port und Konfigurationspfad werden ausschliesslich ueber
# die Kommandozeile ausgewertet. Weder die config.json noch Umgebungs-
# variablen werden dafuer gelesen. Ohne --host bindet der Server auf
# localhost und ist aus dem HA-Core-Container nicht erreichbar.
bashio::log.info "Starte Server auf 0.0.0.0:3000 (Host: $(hostname))"

# shellcheck disable=SC2086
exec node "${SERVER}" --config "${CONFIG_FILE}" --host 0.0.0.0 --port 3000 ${VERBOSE}
