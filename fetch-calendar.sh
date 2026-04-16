#!/bin/sh
# Fetches calendar events from Radicale via CalDAV REPORT.
# Credentials read from ~/.config/quickshell/calendar.conf (never committed).
# Expected format: password=yourpassword

CONF="$HOME/.config/quickshell/calendar.conf"
[ -f "$CONF" ] && . "$CONF"

NOW=$(date -u +"%Y%m%dT%H%M%SZ")

curl -s -u "nate:$password" \
  -X REPORT \
  -H "Content-Type: application/xml; charset=utf-8" \
  -H "Depth: 1" \
  --data "<?xml version=\"1.0\" encoding=\"utf-8\"?>
<C:calendar-query xmlns:D=\"DAV:\" xmlns:C=\"urn:ietf:params:xml:ns:caldav\">
  <D:prop><C:calendar-data/></D:prop>
  <C:filter>
    <C:comp-filter name=\"VCALENDAR\">
      <C:comp-filter name=\"VEVENT\">
        <C:time-range start=\"$NOW\"/>
      </C:comp-filter>
    </C:comp-filter>
  </C:filter>
</C:calendar-query>" \
  "https://calendar.poopenfarten.com/nate/3a375a1d-cea8-6085-146d-5aeb97d0480d/"
