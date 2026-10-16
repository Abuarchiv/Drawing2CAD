# Drawing2CAD – Design

Stand: 2026-10-17 · Challenge: „Drawing2CAD“ von BCT Technology AG (Black Forest Hackathon, Team MSN)

## 0. Bewertung und Gewinnstrategie

**So wird bewertet** (Plattform und Plattform-Assistent, abgefragt am 17.10.2026):

- **50 % Technical Score.** Eine KI prüft Code, Architektur und Baubarkeit der Abgabe. Abgegeben werden Repo-URL, Branch, optional Tag, 40-stellige Commit-SHA und ein README-Text mit Build- und Run-Anleitung. Ein fehlgeschlagener Build disqualifiziert nicht, senkt aber den Score.
- **50 % Pitch.** Die Jury entscheidet nach dem Live-Pitch (So 13:00 bzw. 14:00, rund 15 Teams in zwei Runden, also etwa 5 Minuten je Team). Das Pitch-Deck (PDF) liest die Jury vorab, es wird während des Pitches gezeigt.
- Die Einzelkriterien erscheinen erst auf der Ergebnisseite. **Abgabefrist: So 18.10.2026, 11:30.** Es gibt genau eine finale Abgabe, jedes Mitglied kann sie ersetzen.
- Der Team-Key für OpenRouter (13,33 $) endet mit der Veranstaltung. Danach muss alles mit eigenem Endpunkt oder lokalem Modell laufen.

**Strategie.** Jede Bewertungsachse bekommt einen eigenen, belegbaren Baustein:

| Achse | Was die Prüfer sehen wollen | Unsere Antwort |
|---|---|---|
| Baubarkeit (KI) | Die README-Befehle laufen auf einem frischen Linux-Rechner | `docker build` und `docker run … pytest` laufen grün, ohne BCT-Daten und ohne API-Key, auf amd64 und arm64. Eine Demo baut das eigene Demo-Teil deterministisch. |
| Architektur (KI) | klare Schichten, begründete Entscheidungen | Op-Liste, Sandbox-Worker, MCP-Schicht und Agent-Schicht sind getrennt. `docs/architecture.md` enthält Diagramm und Entscheidungen. |
| Code-Qualität (KI) | Typen, Tests, keine toten Pfade | pydantic-Schemas, pro Modul eine Testdatei, CI-Workflow |
| Anforderungen (KI und Jury) | jede Muss- und Kann-Anforderung belegt | Anforderungsmatrix im README: Anforderung → Modul → Test → Beleg |
| Ergebnis (Jury) | funktioniert es mit echten Daten? | Benchmark aller 21 BCT-Teile gegen die Referenz-STEPs (Volumen, BBox, Zylinder-Ø) |
| Vertrauen (BCT) | keine stillen Annahmen | Review-Liste, farbig markierte Flächen im STEP, Rückverfolgung jedes Modellwerts auf ein Zeichnungsmaß |
| Extras (Jury) | AP242-PMI, PMI-Prüfung, Toleranzen, lokale Modelle | je ein Baustein mit Beleg (Abschnitt 1, C1, C2, X1, R9) |
| Pitch (Jury) | klare Geschichte, Demo, Zahlen | 5-Minuten-Skript, Demo mit dem BCT-Prüffall Sensoraufnahme, Backup-Video, Deck mit Benchmark |

**Alleinstellung gegenüber anderen Teams derselben Challenge:**

1. Gemessene Ergebnisse auf allen 21 BCT-Teilen statt auf drei ausgewählten.
2. Fehlende Maße werden aus der Zeichnung abgeleitet, begründet und im STEP markiert (Prüffall Sensoraufnahme: Breite 20).
3. Jeder Modellwert verweist auf ein Zeichnungsmaß (`refs`). Daraus folgt der Umbau auf Toleranzmitte ohne Handarbeit.
4. Der Server ist modellunabhängig. Die Bauphase läuft auch mit einem lokalen Modell, die Daten bleiben im Haus.
5. Jeder Build läuft in einer Sandbox und wird sofort geprüft (Solid, Maße, STEP-Roundtrip).

**Grenze:** Einen Sieg kann niemand garantieren, weil Konkurrenz und Jury-Kriterien offen sind. Der Plan sichert deshalb zuerst, was ganz in unserer Hand liegt: Baubarkeit, Muss-Ziele, Pitch-Deck. Danach folgen die Extras, sortiert nach Nutzen pro Stunde.

## 1. Anforderungen aus der Challenge (bindend)

| ID | Anforderung |
|---|---|
| R1 | KI-Prototyp analysiert technische 2D-Zeichnungen und erkennt Konturen, Maße, Bohrungen, Grund-Features und Hinweise (Notes) |
| R2 | Unklare oder mehrdeutige Information wird markiert statt ungeprüft interpretiert |
| R3 | Das 3D-Modell entsteht ausschließlich über einen selbst gebauten, lokal laufenden MCP-Server |
| R4 | Der MCP-Server läuft komplett lokal (Docker), ohne Cloud-Abhängigkeit |
| R5 | Modellskripte laufen in einer Sandbox: kein Netzwerk, Zeitlimit pro Lauf |
| R6 | Skriptbarer Open-Source-CAD-Kern: **CadQuery** (Teamentscheidung) |
| R7 | Wenige, klar beschriebene Tools mit strukturierten Parametern; freier Code nur als Fallback |
| R8 | Nach jedem Build: (a) Solid geschlossen und gültig, (b) Modellmaße gegen Zeichnungsmaße (Gesamtgröße, Bohrungsdurchmesser, Bohrungspositionen), (c) exportiertes STEP re-importieren – Ergebnis maschinenlesbar |
| R9 | Unabhängig vom KI-Modell |
| R10 | Unklare Information wird im 3D-Modell sichtbar markiert, „mit PMIs oder Farben“ (Pitch-Folie „Milestones“, Punkt 4) |
| M1 | ≥ 3 Beispielteile als STEP |
| M2 | 100 % der STEP-Dateien bestehen die Validierung und öffnen fehlerfrei in einem CAD-System (z. B. NX) |
| M3 | Jedes fehlende Maß wird aus der Geometrie angenommen und mit Begründung in einer Review-Liste geführt |
| C1 (optional) | STEP AP242 mit semantischem PMI |
| C2 (optional) | PMI-Validierung, z. B. NIST STEP File Analyzer |
| X1 (Erweiterung) | Toleranzen auslesen, asymmetrische Toleranzen auf Toleranzmitte übertragen, prüfen, ob das 3D-Modell alle Maße innerhalb der Toleranz erfüllt; bestehende Modelle ändern |
| J1 (Abgabe) | Build und Tests laufen per README auf linux/amd64 und linux/arm64, ohne BCT-Daten und ohne API-Key |
| J2 (Abgabe) | README mit Schnellstart, Architektur, Anforderungsmatrix, Ergebnissen und Grenzen; keine Secrets, keine Hinweise auf Entwicklungswerkzeuge |
| J3 (Abgabe) | Automatische Tests für jedes Modul, CI-Workflow |
| P1 (Pitch) | Pitch-Deck als PDF vor dem Pitch auf der Plattform, mit Benchmark-Zahlen und Demo-Bildern |
| P2 (Pitch) | Demo einer kompletten Umsetzung (live oder als Video), Upload einer Zeichnung bis zum markierten STEP |

## 2. Fakten aus den Beispieldaten (verifiziert)

- Quelle: `/Users/abu/Downloads/OneDrive_1_16.10.2026/` (ersetzt den ersten Download `/Users/abu/Downloads/Drawing2CAD`, dessen 9 Teile darin enthalten sind):
  - `Drawing2CAD/<Ordner>/` mit 21 Teilen, je PDF-Zeichnung, Referenz-`.stp`, meist `.prt` (NX). Laut `Readme.txt` ist die STEP-Datei zum Vergleich der Ergebnisse gedacht.
  - `bct_isolim.xml`: ISO-286-Passungsabmaße je Toleranzklasse (z. B. `H7`, `h10`) und Nennmaßbereich, in mm.
  - `bct_toltabs.xml`: Allgemeintoleranzen nach DIN ISO 2768 (fein, mittel, grob, sehr grob) für Längen, Winkel, Bohrungen und Fasen sowie eine Tabelle nach Dezimalstellen.
  - `2026_Hackathon_Challenges_Pitch (1).pptx`: Challenge-Folien. Milestones: (1) Zeichnung hochladen und automatisch analysieren, (2) Konturen, Bohrungen, Maße, Features, Notes erkennen, (3) Solid-3D-Modell erzeugen, (4) unklare Information mit PMIs oder Farben markieren, (5) Demonstration mit echten Beispieldaten. Erweiterung: Toleranzen extrahieren, asymmetrische Toleranzen auf die Mitte legen, Einhaltung prüfen.
- Dateinamen sind uneinheitlich: `<Teil>_dwg.pdf` (die ersten 9 Teile), `<Teil>.pdf` (neue Teile), Nummern mit Leerzeichen bei den komplexen Zeichnungen (`1 106 0168 3.pdf`). Ordnernamen enthalten Leerzeichen und Klammern (`Getriebedeckel (optional PMI)`).
- **Alle PDFs sind Vektorzeichnungen.** Die 9 alten Teile enthalten zusätzlich nur ein Rasterbild, und zwar die schattierte Iso-Ansicht (z. B. Fuss: Bild bei x 698–1143 pt). Konturen, Maßlinien und Text sind Vektoren. Folgen:
  - Rendern liefert bei jeder Auflösung scharfe Ausschnitte.
  - Text ist in 18 Zeichnungen in Pfade umgewandelt (`pdftotext` liefert nichts). Nur die drei komplexen Zeichnungen haben echten Text, Symbole (Form- und Lagetoleranz, Durchmesser) aber in einer Symbolschrift ohne Unicode-Zuordnung.
  - Kreise und Bögen der orthogonalen Ansichten sind kubische Bézierkurven. Ihr Mittelpunkt folgt exakt aus den Tangenten der Kontrollpunkte. Die vielen kurzen Liniensegmente sind Ellipsen der Iso-Ansicht (daran scheiterte der erste Kreisfit). Polylinien sind exakt stetig, Verketten über die Stream-Reihenfolge genügt. Die komplexen Zeichnungen speichern jedes Segment als eigenen Pfad auf einem 0,12-pt-Raster.
  - **Vektormessung funktioniert** (R&D 17.10., Task 14): 29 von 29 Prüfwerten auf vier Zeichnungen weichen höchstens 0,0003 mm ab. Die fehlende Breite der Sensoraufnahme misst 20,0000 mm bei 2:1.
  - Die Strichbreite sichtbarer Kanten hängt von der Vorlage ab: 1,417 pt (Sensoraufnahme), 1,984 pt (3-Loch-Hebel), 0,992 pt (Fuss, Flansch). Maß- und Hilfslinien liegen teils in derselben Klasse und werden über ihre losen Enden abgetrennt.
  - **Datenfehler bei BCT:** Das Schriftfeld des 3-Loch-Hebels nennt 1:1, gezeichnet ist 2:1 (alle Kreise doppelt so groß wie bemaßt). Der Abgleich gedruckter Maße mit der Geometrie erkennt das (9 von 9 Stimmen). Das gehört als `conflict` in die Review-Liste.
- Seiten: A3 quer (1190,55 × 841,89 pt) und A4 hoch (595,28 × 841,89 pt). Komplexe Zeichnung 1 hat 4 Seiten, Komplexe Zeichnung 2 hat 3 Seiten.
- Maßstäbe (Schriftfeld): Flansch 2:1, Rotation 1:2, Sensoraufnahme 2:1, sonst überwiegend 1:1. Der Maßstab ist pro Zeichnung abzulesen.
- Bewusste Lücke: `Sensoraufnahme (optional PMI)/Readme.txt` sagt, die Breite fehle absichtlich, solle angenommen und zur Kontrolle markiert werden. Sie beträgt 20 mm. Das ist der Prüffall für M3 und R10.
- PMI in den BCT-Referenzen (aus NX 2606, AP242, R&D 17.10.):
  - `Sensoraufnahme_PMI.stp`: Die fehlende Breite steht als **semantisches Maß** im Modell (`DIMENSIONAL_LOCATION` 20 mm zwischen den Flächen y = −10 und y = +10), ohne Notiz. Die zweite Farbe (RGB 0.2/0.4/0.8) liegt nur auf zwei Kosmetik-Gewindekreisen R4 und markiert die Annahme nicht.
  - `Getriebedeckel_PMI.stp`: 16 semantische Maße, davon 4 mit `PLUS_MINUS_TOLERANCE` und eins mit `LIMITS_AND_FITS` (H7), dazu 18 tessellierte Beschriftungen. Keine Bezüge, keine Form- und Lagetoleranzen.
- Der Titel weicht vom Ordnernamen ab: Ordner `Rotation`, Zeichnungstitel „Drehteil“.
- Sammelangaben: Maschinenteil „nicht bemaßte Radien R=1“, Trägerplatte „nicht bemaßte Radien R = 20 mm“.
- Referenzen: je 1 Solid. **Ausnahme: Die Referenz von Komplexe Zeichnung 2 ist laut `isValid()` ungültig.** Kennzahlen (nur zur Auswertung, **nie** als Eingabe für die Extraktion verwenden):

| Teil | Flächen | Volumen mm³ | BBox mm | Zylinder-Ø in der Referenz |
|---|---|---|---|---|
| 3-Loch-Hebel | 22 | 19093.7 | 133.5 × 64.7 × 8 | 10, 12, 18, 20, 22, 29 |
| Achse | 12 | 1109.8 | 17.1 × 13 × 13 | 5, 9.6, 10, 13 |
| Befestigung | 36 | 184465.4 | 145 × 80 × 95 | 12, 20, 30, 60, 78, 80 |
| Dreistern | 38 | 34624.9 | 87 × 98.6 × 22 | 5, 9, 12, 16, 22, 40 |
| Fixierung | 17 | 24610.2 | 85.61 × 80 × 45.61 | 4.5, 5, 24, 30, 80 |
| Flansch | 45 | 43831.5 | 90 × 55 × 25 | 2.5, 3.5, 20, 30 |
| Fuss | 20 | 317209.8 | 115 × 115 × 76.2 | 19, 33, 44, 57 |
| Getriebedeckel | 37 | 19044.9 | 23 × 68 × 68 | 6.6, 11.6, 14, 28, 68 |
| Grundplatte | 188 | 285390.6 | 358 × 170 × 16 | 3, 6, 12, 95 |
| Haken | 23 | 1388581.5 | 439 × 304 × 30 | 32, 64, 70, 76, 152 |
| Komplexe Zeichnung 1 | 273 | 281180.6 | 113 × 118 × 81 | 39 verschiedene |
| Komplexe Zeichnung 2 | 207 | 385223.7 | 125 × 70 × 100 | 15 verschiedene (Referenz ungültig) |
| Komplexe Zeichnung 3 | 55 | 11712.3 | 17 × 17 × 87.5 | 13 verschiedene |
| Lagerschaft | 40 | 112146.2 | 180 × 90 × 30 | 4, 20, 70 |
| Maschinenteil | 70 | 68458.2 | 90 × 49 × 100 | 2, 2.5, 5, 10, 14, 50, 100 |
| Rotation | 25 | 1515437.7 | 216 × 84.5 × 216 | 12, 25, 127, 135, 156.2, 174, 210, 216 |
| Schnittmenge | 36 | 409470.3 | 110 × 130 × 100 | 15, 20, 40 |
| Sensoraufnahme | 11 | 4110.0 | 49 × 20 × 5 | 5.5, 6.8, 20 |
| Splint | 22 | 1331.9 | 68.5 × 13 × 4.87 | 1, 5, 8 |
| Trägerplatte | 40 | 99314.0 | 15 × 140 × 118 | 4.2, 5.5, 6, 6.6, 11, 12, 16, 25, 40 |
| Welle | 23 | 354588.1 | 300 × 45 × 45 | 12, 28, 30, 35, 40, 45 |

- Gewindekonvention der Referenzen: Die NX-Teile modellieren Innengewinde als Kernlochbohrung (Trägerplatte M5 → Ø4.2, Sensoraufnahme M8 → Ø6.8), Außengewinde mit Nenndurchmesser (Maschinenteil M10 → Ø10). Die Referenzen der komplexen Zeichnungen nutzen den Kerndurchmesser d − 1.082532·P (M3 → 2.459, M10×1 → 8.917) und färben Gewindeflächen grün (RGB 0.396/0.941/0.451). Deshalb kennt `holes` beide Varianten (`thread_core`).
- Toleranztabellen, geprüft gegen die Passmaßtabelle in Komplexe Zeichnung 3: `h10` für 3–6 mm ergibt 0 / −0.048, also Ø6 h10 = 5.952 bis 6.000. Das stimmt. Die XML-Zeilen nutzen teils `from`/`up_to` statt `over`/`to`.

## 3. Verifizierte technische Basis

- Docker-Image `python:3.12-slim` (aarch64) mit den apt-Paketen `libgl1 libglu1-mesa libxrender1 poppler-utils`. Ohne `libgl1` scheitert `import OCP`.
- `cadquery==2.8.0`, `mcp==2.3.0`. In `mcp` 2.x heißt FastMCP jetzt `MCPServer`: `from mcp.server.mcpserver import MCPServer, Image`. Außerdem gilt:
  - `@server.tool()` erzeugt das JSON-Schema aus den Typannotationen.
  - Bei ungültigen Argumenten wirft `call_tool` einen `ToolError`.
  - Gibt ein Tool ein `Image` zurück, wird daraus `ImageContent`.
  - `MCPServer(instructions=...)` ist verfügbar.
- CadQuery-Ebenen: `XY` hat die Normale +Z, `XZ` die Normale **−Y**, `YZ` die Normale +X. Ein `revolve` auf `Workplane("XZ")` um die lokale Achse (0,0)→(0,1) dreht um die globale Z-Achse.
- Build, STEP-Export und Re-Import laufen in einem Container mit `--network none` (getestet).
- Farbige Flächen im STEP: `asm = cq.Assembly(solid, name=..., color=cq.Color(...))`, `asm.addSubshape(face, name=..., color=cq.Color(1, 0.5, 0))`, `asm.export(path)` schreibt AP214 mit `COLOUR_RGB` und `STYLED_ITEM`. Der Re-Import ergibt denselben Solid (getestet). Hängt man `addSubshape` an einen Knoten ohne eigenen Shape, gibt es eine Warnung, deshalb den Solid direkt im Wurzelknoten übergeben.
- AP242 mit semantischem PMI über XCAF (OCP 7.9.3, R&D 17.10., Task 15). Schreiben und Zurücklesen gehen, mit vier Fallen:
  - Das Schema `AP242DIS` wird erst nach `STEPControl_Controller.Init_s()` angenommen; `AP242` lehnt OCCT ab.
  - Die Wurzel muss ein Compound sein, sonst liefert `AddSubShape` Null-Labels.
  - Der Passungsgrad wird um 2 zu hoch geschrieben, daher `DimensionGrade(n − 1)`, abgesichert durch einen Test.
  - `FindAttribute` füllt unter OCP kein Handle, daher `TDF_AttributeIterator`.

  XCAF-Notizen werden nicht exportiert. Was ankommt: Maßbeschreibung als `DESCRIPTIVE_REPRESENTATION_ITEM`, Flächennamen (`write.stepcaf.subshapes.name`), Layer und Farben.
- GLB für die Web-Ansicht: `cq.Assembly.export("x.glb")` liefert ein gültiges glTF mit einem Material je Farbe (Khronos-Validator: 0 Fehler). Flächennamen übernimmt glTF nicht.

## 4. Architektur

```
Browser (Web-UI :8080)                         beliebiger MCP-Client (stdio)
  │ Upload PDF, Live-Ereignisse (SSE)            │
  ▼                                              │
app-Container (Internet erlaubt)                 │
  d2c.web ── d2c.agent ── LLM-Endpunkt (OpenAI-kompatibel: OpenRouter, Ollama, LM Studio)
               │ MCP über streamable HTTP, nur internes Docker-Netz
               ▼                                 ▼
mcp-Container (internes Netz, kein Internet)
  d2c.server ── Session ── Sandbox-Worker (Subprozess, Timeout, rlimits) ── CadQuery/OCCT
     │                         └─ Prüfungen R8a–c ──▶ BuildReport (JSON)
     └─ export_step ──▶ results/<Teil>/: STEP (Farben, ggf. AP242-PMI), GLB, review.md, review.json, ops.json, spec.json

Ablauf im Modell: render_drawing (PNG + Seiteninfo) → PartSpec (JSON) → submit_spec (Schema- und Review-Regeln)
  → Build-Tools (jede Änderung baut ALLE Operationen neu und prüft) → export_step (nur wenn alles ok)
```

Kernentscheidungen:

1. **Das Modell ist eine Liste von Operationen.** Jede Änderung baut alle Operationen in einem frischen Sandbox-Prozess neu auf. Dadurch:
   - läuft jeder Build in der Sandbox (R5),
   - ist jedes Ergebnis aus `ops.json` reproduzierbar,
   - lassen sich Modelle per `edit_op` ändern (X1).
2. **Explizite globale Koordinaten statt Flächen-Selektoren.** Jedes Feature nennt Skizzenebene (`XY`/`XZ`/`YZ` + Offset) und Position. Kleine Modelle kommen damit zuverlässiger zurecht als mit Selektor-Strings (R7).
3. **Kanten für Rundungen und Fasen werden über einen nahen Punkt gewählt** (`near: [[x,y,z]]`). Trifft die Auswahl keine Kante, ist das ein Fehler. Es wird nie stillschweigend nichts gemacht.
4. **Die Review-Pflicht steckt im Schema.** Jedes Maß mit `assumed=true` oder `confidence < 0.8` muss in einem Review-Eintrag mit Begründung stehen, sonst lehnt `submit_spec` die Spec ab (M3, R2).
5. **Review-Einträge werden im STEP markiert (R10, C1).** Jeder Review-Eintrag nennt Punkte im Modell (`mark_near`). Flächen in deren Nähe exportiert der Server orange eingefärbt, benannt (`CHECK <id>`) und auf dem Layer `ASSUMED_CHECK`. Ein angenommenes Maß kommt zusätzlich als semantisches PMI-Maß mit Beschreibung „ASSUMED …“ in die AP242-Datei, so wie BCT es in `Sensoraufnahme_PMI.stp` vormacht.
6. **Sandbox in drei Schichten:**
   - Container mit `--network none`,
   - Subprozess mit `timeout` und rlimits (CPU, Speicher, Dateigröße),
   - für `run_script` zusätzlich AST-Prüfung und eingeschränkte Builtins.

   Die eigentliche Grenze bilden Container und Prozess. Die AST-Prüfung liefert nur frühe, verständliche Fehlermeldungen.
7. **Das Modell sieht keine Referenzdaten.** Der Server hängt nur einen Ordner mit den Zeichnungs-PDFs ein. Die Teile-Session läuft außerhalb des Repos und ohne Datei-Tools, damit weder `.stp`-Dateien noch die Tabelle in Abschnitt 2 erreichbar sind.
8. **Die Auswertung gegen die Referenz ist nur ein Entwicklungswerkzeug** (`scripts/eval_refs.py`). Verglichen werden Merkmale, die nicht von der Lage im Raum abhängen: Volumen, sortierte BBox und die Menge der Zylinderdurchmesser. Der Server selbst kennt keine Referenzen. Ist eine Referenz ungültig, wird die Zeile trotzdem ausgewertet und als „Referenz ungültig“ gekennzeichnet.
9. **Agent und Server sind getrennt.** Der Server hat nie Internet (internes Docker-Netz bzw. `--network none`). Der Agent spricht nur mit dem LLM-Endpunkt und über MCP mit dem Server. Jeder andere MCP-Client kann den Server genauso nutzen.
10. **Zwei Phasen, ein Vertrag.** Lesephase: ein Vision-Modell füllt die PartSpec. Bauphase: ein beliebiges Modell, auch ein kleines lokales ohne Bildverständnis, setzt die Spec in Operationen um. Die PartSpec ist die Schnittstelle zwischen beiden.
11. **Rückverfolgbarkeit.** Jede Operation kann ihre Zahlenwerte per `refs` an Maß-ids binden. Das liefert die Tabelle „Traceability“ in der Review-Liste und erlaubt den automatischen Umbau auf Toleranzmitte (X1).
12. **Die Web-Oberfläche hat keinen eigenen Zustand.** Sie zeigt den Ergebnisordner und die Ereignisse des Agenten.

## 5. Abnahmeschwellen

| Prüfung | Schwelle |
|---|---|
| Solid gültig | `isValid()`, genau 1 Solid, keine freien Kanten, Volumen > 0 |
| Maßvergleich (Server) | linear ≤ 0.01 mm, Bohrung: \|2r − d\| ≤ 0.01 mm, Achsabstand ≤ 0.01 mm, Achsen parallel (\|cos\| ≥ 0.9999) |
| STEP-Roundtrip | Re-Import gültig, 1 Solid, \|ΔV\|/V ≤ 1e-6 |
| Referenzvergleich MATCH | \|ΔV\| ≤ 1.0 %, sortierte BBox je Achse ≤ 0.05 mm, Zylinder-Ø-Mengen gleich (gerundet auf 0.01 mm) |

## 6. Außerhalb dieses Designs

- Form- und Lagetoleranzen als semantisches PMI (die BCT-Referenzen enthalten selbst keine). Die Textebene liest sie, die Review-Liste führt sie auf.
- Der NIST STEP File Analyzer (C2) läuft nur unter Windows mit Excel. Ihn bedient die Rolle QA an einem Windows-Rechner. Auf dem Mac prüft `read_pmi` die Dateien automatisch.
