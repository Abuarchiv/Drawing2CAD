# Drawing2CAD – Design

Stand: 2026-10-16 · Challenge: „Drawing2CAD“ von BCT Technology AG (Black Forest Hackathon)

## 1. Anforderungen aus der Challenge (bindend)

| ID | Anforderung |
|---|---|
| R1 | KI-Prototyp analysiert technische 2D-Zeichnungen und erkennt Konturen, Maße, Bohrungen und Grund-Features |
| R2 | Unklare oder mehrdeutige Information wird markiert statt ungeprüft interpretiert |
| R3 | Das 3D-Modell entsteht ausschließlich über einen selbst gebauten, lokal laufenden MCP-Server |
| R4 | Der MCP-Server läuft komplett lokal (Docker), ohne Cloud-Abhängigkeit |
| R5 | Modellskripte laufen in einer Sandbox: kein Netzwerk, Zeitlimit pro Lauf |
| R6 | Skriptbarer Open-Source-CAD-Kern: **CadQuery** (Teamentscheidung) |
| R7 | Wenige, klar beschriebene Tools mit strukturierten Parametern; freier Code nur als Fallback |
| R8 | Nach jedem Build: (a) Solid geschlossen und gültig, (b) Modellmaße gegen Zeichnungsmaße (Gesamtgröße, Bohrungsdurchmesser, Bohrungspositionen), (c) exportiertes STEP re-importieren – Ergebnis maschinenlesbar |
| R9 | Unabhängig vom KI-Modell |
| M1 | ≥ 3 Beispielteile als STEP |
| M2 | 100 % der STEP-Dateien bestehen die Validierung und öffnen fehlerfrei in einem CAD-System (z. B. NX) |
| M3 | Jedes fehlende Maß wird aus der Geometrie angenommen und mit Begründung in einer Review-Liste geführt |
| C1 (optional) | STEP AP242 mit semantischem PMI |
| C2 (optional) | PMI-Validierung, z. B. NIST STEP File Analyzer |
| X1 (Erweiterung) | Toleranzen auslesen, bestehende Modelle ändern |

## 2. Fakten aus den Beispieldaten (verifiziert)

- 9 Teile in `/Users/abu/Downloads/Drawing2CAD/<Teil>/`: `<Teil>_dwg.pdf`, `<Teil>.stp` (Referenz, AP214), `<Teil>.prt` und `<Teil>_dwg.prt` (NX).
- Die PDFs enthalten nur ein JPEG-Bild (≈ 400 dpi, A3 quer, 1190,55 × 841,89 pt), keinen Text und keine Vektoren. Die Maße lassen sich deshalb nur per Vision auslesen.
- Die Maßstäbe sind unterschiedlich: Flansch 2:1, Rotation 1:2, alle anderen 1:1.
- Der Titel weicht vom Ordnernamen ab: Ordner `Rotation`, Zeichnungstitel „Drehteil“.
- Sammelangaben: Maschinenteil „nicht bemaßte Radien R=1“, Trägerplatte „nicht bemaßte Radien R = 20 mm“.
- Jede Referenz ist genau 1 gültiger Solid. Kennzahlen (nur zur Auswertung, **nie** als Eingabe für die Extraktion verwenden):

| Teil | Volumen mm³ | BBox mm | Zylinder-Ø in der Referenz |
|---|---|---|---|
| Befestigung | 184465.4 | 145 × 80 × 95 | 12, 20, 30, 60, 78, 80 |
| Dreistern | 34624.9 | 87 × 98.6 × 22 | 5, 9, 12, 16, 22, 40 |
| Flansch | 43831.5 | 90 × 55 × 25 | 2.5, 3.5, 20, 30 |
| Fuss | 317209.8 | 115 × 115 × 76.2 | 19, 33, 44, 57 |
| Haken | 1388581.5 | 439 × 304 × 30 | 32, 64, 70, 76, 152 |
| Maschinenteil | 68458.2 | 90 × 49 × 100 | 2, 2.5, 5, 10, 14, 50, 100 |
| Rotation | 1515437.7 | 216 × 84.5 × 216 | 12, 25, 127, 135, 156.2, 174, 210, 216 |
| Trägerplatte | 99314.0 | 15 × 140 × 118 | 4.2, 5.5, 6, 6.6, 11, 12, 16, 25, 40 |
| Welle | 354588.1 | 300 × 45 × 45 | 12, 28, 30, 35, 40, 45 |

- Gewindekonvention der Referenz: Innengewinde wird als Kernloch modelliert (Trägerplatte M5 → Ø4.2), Außengewinde als Nenndurchmesser (Maschinenteil M10 → Ø10).

## 3. Verifizierte technische Basis

- Docker-Image `python:3.12-slim` (aarch64) mit den apt-Paketen `libgl1 libglu1-mesa libxrender1 poppler-utils`. Ohne `libgl1` scheitert `import OCP`.
- `cadquery==2.8.0`, `mcp==2.3.0`. In `mcp` 2.x heißt FastMCP jetzt `MCPServer`: `from mcp.server.mcpserver import MCPServer, Image`. Außerdem gilt:
  - `@server.tool()` erzeugt das JSON-Schema aus den Typannotationen.
  - Bei ungültigen Argumenten wirft `call_tool` einen `ToolError`.
  - Gibt ein Tool ein `Image` zurück, wird daraus `ImageContent`.
  - `MCPServer(instructions=...)` ist verfügbar.
- CadQuery-Ebenen: `XY` hat die Normale +Z, `XZ` die Normale **−Y**, `YZ` die Normale +X. Ein `revolve` auf `Workplane("XZ")` um die lokale Achse (0,0)→(0,1) dreht um die globale Z-Achse.
- Build, STEP-Export und Re-Import laufen in einem Container mit `--network none` (getestet).

## 4. Architektur

```
Zeichnung (PDF)
  └─ MCP-Tool render_drawing ──▶ PNG an das KI-Modell (beliebiger multimodaler MCP-Client)
KI-Modell
  └─ füllt PartSpec (JSON) ──▶ MCP-Tool submit_spec (Schema- und Review-Regeln)
  └─ ruft Build-Tools auf ──▶ Session hängt Operation an ──▶ Sandbox-Subprozess baut ALLE Operationen neu
                                                           └─ Validierung R8a, R8b, R8c (Temp-STEP + Re-Import) ──▶ BuildReport (JSON)
  └─ export_step ──▶ gleicher Build mit Zielpfad results/<Teil>/ + review.md (nur wenn alles ok)
```

Kernentscheidungen:

1. **Das Modell ist eine Liste von Operationen.** Jede Änderung baut alle Operationen in einem frischen Sandbox-Prozess neu auf. Dadurch:
   - läuft jeder Build in der Sandbox (R5),
   - ist jedes Ergebnis aus `ops.json` reproduzierbar,
   - lassen sich Modelle per `edit_op` ändern (X1).
2. **Explizite globale Koordinaten statt Flächen-Selektoren.** Jedes Feature nennt Skizzenebene (`XY`/`XZ`/`YZ` + Offset) und Position. Kleine Modelle kommen damit zuverlässiger zurecht als mit Selektor-Strings (R7).
3. **Kanten für Rundungen und Fasen werden über einen nahen Punkt gewählt** (`near: [[x,y,z]]`). Trifft die Auswahl keine Kante, ist das ein Fehler. Es wird nie stillschweigend nichts gemacht.
4. **Die Review-Pflicht steckt im Schema.** Jedes Maß mit `assumed=true` oder `confidence < 0.8` muss in einem Review-Eintrag mit Begründung stehen, sonst lehnt `submit_spec` die Spec ab (M3, R2).
5. **Sandbox in drei Schichten:**
   - Container mit `--network none`,
   - Subprozess mit `timeout` und rlimits (CPU, Speicher, Dateigröße),
   - für `run_script` zusätzlich AST-Prüfung und eingeschränkte Builtins.

   Die eigentliche Grenze bilden Container und Prozess. Die AST-Prüfung liefert nur frühe, verständliche Fehlermeldungen.
6. **Das Modell sieht keine Referenzdaten.** Der Server hängt nur einen Ordner mit den Zeichnungs-PDFs ein. Die Teile-Session läuft außerhalb des Repos und ohne Datei-Tools, damit weder `.stp`-Dateien noch die Tabelle in Abschnitt 2 erreichbar sind.
7. **Die Auswertung gegen die Referenz ist nur ein Entwicklungswerkzeug** (`scripts/eval_refs.py`). Verglichen werden Merkmale, die nicht von der Lage im Raum abhängen: Volumen, sortierte BBox und die Menge der Zylinderdurchmesser. Der Server selbst kennt keine Referenzen.

## 5. Abnahmeschwellen

| Prüfung | Schwelle |
|---|---|
| Solid gültig | `isValid()`, genau 1 Solid, keine freien Kanten, Volumen > 0 |
| Maßvergleich (Server) | linear ≤ 0.01 mm, Bohrung: \|2r − d\| ≤ 0.01 mm, Achsabstand ≤ 0.01 mm, Achsen parallel (\|cos\| ≥ 0.9999) |
| STEP-Roundtrip | Re-Import gültig, 1 Solid, \|ΔV\|/V ≤ 1e-6 |
| Referenzvergleich MATCH | \|ΔV\| ≤ 1.0 %, sortierte BBox je Achse ≤ 0.05 mm, Zylinder-Ø-Mengen gleich (gerundet auf 0.01 mm) |

## 6. Außerhalb dieses Designs

- C1/C2 (AP242 + PMI, NIST SFA) und X1-Toleranzen bekommen erst einen eigenen Plan, wenn M1–M3 erfüllt sind. Der NIST SFA läuft nur unter Windows.
