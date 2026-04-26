# DWD Regenradar Plasmoid

KDE-Plasma-Widget (Plasma 6) fuer die Anzeige des DWD-Niederschlagsradars mit interaktiver Karte.

## Features

- **Interaktive Karte** — OpenStreetMap-Basiskarte mit Zoom und Pan (Qt Location)
- **DWD Radar-Overlay** — Transparentes Niederschlagsradar direkt vom DWD-WMS
- **Zeitgesteuerte Animation** — Play/Pause mit Slider und Uhrzeitanzeige
- **Verlauf & Vorhersage** — Toggle zwischen vergangenen Daten und Niederschlagsvorhersage
- **Legende** — Offizielle DWD-Niederschlagslegende als Overlay
- **Auto-Update** — Alle 5 Minuten automatische Aktualisierung

## Abhaengigkeiten

- KDE Plasma 6
- `qt6-location` (fuer die Kartenanzeige)

## Installation

```bash
cd plasma-rain-radar
kpackagetool6 -t Plasma/Applet -i .
```

Update:

```bash
cd plasma-rain-radar
kpackagetool6 -t Plasma/Applet -u .
```

## Plasma neu starten (dein Setup)

```bash
kquitapp6 plasmashell
plasmashell --replace &
```

## WMS-Konfiguration (optional)

Die folgenden Variablen koennen in `scripts/fetch_frames.sh` gesetzt werden (Fallback-Modus):
- `WMS_BASE_URL` (Default: `https://maps.dwd.de/geoserver/ows`)
- `WMS_LAYER` (Default: `dwd:Niederschlagsradar`)
- `WMS_BBOX` (Default: `47.0,5.5,55.5,15.5` — Deutschland in EPSG:4326)
- `WMS_WIDTH`, `WMS_HEIGHT`
- `MAX_FRAMES`, `STEP_MINUTES`, `TIME_DIRECTION` (`future` oder `past`)

## Datenquelle

Niederschlagsdaten: [DWD GeoServer](https://maps.dwd.de/geoserver/ows) (CC BY 4.0)
Kartendaten: © OpenStreetMap-Mitwirkende
