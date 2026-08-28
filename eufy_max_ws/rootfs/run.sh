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

# ---------------------------------------------------------------------
# Gespeicherte Sitzung verwerfen
# ---------------------------------------------------------------------
#
# eufy-security-ws legt Anmeldedaten, Schluessel und Geraetekennungen in
# /data/persistent.json ab. Nach einem Neubau des Images kann dort eine
# neuere Programmfassung stecken, die mit den alten Daten nicht mehr
# zurechtkommt. Eufy antwortet dann mit "get identity error" (Code 4404)
# und liefert eine leere Geraeteliste - in Home Assistant sind
# schlagartig alle Entities nicht verfuegbar.
#
# Dieser Schalter loescht die Sitzung, sodass sich der Server sauber neu
# anmeldet. Danach wieder ausschalten, sonst meldet sich das Add-on bei
# jedem Start neu an.

if bashio::config.true 'reset_session'; then
    bashio::log.warning "reset_session ist aktiv - gespeicherte Sitzung wird geloescht"
    rm -f /data/persistent.json
    rm -f /data/*.db 2>/dev/null || true
    bashio::log.info "Sitzung geloescht. Bitte reset_session danach wieder ausschalten"
fi

# Feste IP-Adressen der Stationen. Verhindert, dass sich Kameras ueber
# Eufys Cloud-Relay verbinden statt lokal. Format je Eintrag: SERIENNUMMER:IP
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
# config.json. Die wird hier bei jedem Start neu erzeugt, damit
# Aenderungen im UI sofort greifen.
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

SERVER="/opt/eufy/node_modules/eufy-security-ws/dist/bin/server.js"

if [ ! -f "${SERVER}" ]; then
    bashio::log.warning "Server nicht am erwarteten Ort, suche im Dateisystem"
    SERVER=$(find / -path /proc -prune -o -name "server.js" -path "*eufy-security-ws*" -print 2>/dev/null | head -n 1)
fi

if [ -z "${SERVER}" ] || [ ! -f "${SERVER}" ]; then
    bashio::exit.nok "eufy-security-ws wurde im Image nicht gefunden - Add-on neu bauen"
fi

# Installierte Fassung ins Protokoll schreiben. Hilft, wenn nach einem
# Neubau etwas anders laeuft als vorher.
PKG="/opt/eufy/node_modules/eufy-security-ws/package.json"
if [ -f "${PKG}" ]; then
    bashio::log.info "eufy-security-ws $(jq -r '.version' "${PKG}")"
fi
PKG_CLIENT="/opt/eufy/node_modules/eufy-security-client/package.json"
if [ -f "${PKG_CLIENT}" ]; then
    bashio::log.info "eufy-security-client $(jq -r '.version' "${PKG_CLIENT}")"
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

bashio::log.info "Starte Server auf 0.0.0.0:3000 (Host: $(hostname))"

# Host, Port und Konfigurationspfad werden ausschliesslich ueber die
# Kommandozeile ausgewertet - nicht ueber die config.json.
ARGS=(--config "${CONFIG_FILE}" --host 0.0.0.0 --port 3000)

# ---------------------------------------------------------------------
# Protokollmodus
# ---------------------------------------------------------------------

if bashio::config.true 'event_log'; then
    # Nur Erkennungen zeigen. Gefiltert wird mit awk - das BusyBox-grep
    # im Alpine-Image kennt kein --line-buffered und wuerde die Ausgabe
    # blockweise zurueckhalten.
    bashio::log.info "Ereignisfilter aktiv - es werden nur Erkennungen angezeigt"

    node "${SERVER}" "${ARGS[@]}" --verbose 2>&1 | awk '
        BEGIN { IGNORECASE = 1 }
        /heartbeat|Heartbeat|Sending ping|checkin|Checkin/ { next }
        /detected|Detected|onPerson|onMotion|onPet|onVehicle|onRing/ { print; fflush(); next }
        /person|Person|human|Human|motion|Motion|vehicle|Vehicle/ { print; fflush(); next }
        /rings|ringing|Ringing|package|Package/ { print; fflush(); next }
        /PushMessage|push message|onMessage|CusPush|received message/ { print; fflush(); next }
        /event_type|eventType|alarm|Alarm/ { print; fflush(); next }
    '
    exit 0
fi

if bashio::config.true 'debug'; then
    bashio::log.info "Debug-Modus aktiv - sehr ausfuehrliches Protokoll"
    ARGS+=(--verbose)
fi

exec node "${SERVER}" "${ARGS[@]}"
