# Drawing2CAD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ein lokal laufender MCP-Server (Docker, CadQuery) mit modellunabhängigem Agenten und Web-Oberfläche macht aus einer technischen 2D-Zeichnung ein validiertes STEP-Modell. Unklare Stellen stehen in einer Review-Liste und sind im STEP farbig markiert. Fehlende Maße werden aus der Vektorgeometrie gemessen, Toleranzen ausgewertet. Ein Benchmark vergleicht die Ergebnisse mit allen 21 BCT-Referenzen.

**Architecture:** Das Modell ist eine Liste von Operationen. Jede Änderung baut alle Operationen in einem Sandbox-Subprozess neu und gibt einen maschinenlesbaren BuildReport zurück (Solid gültig, Maße gegen Spec, STEP-Roundtrip). `export_step` schreibt das geprüfte STEP mit Review-Liste. Der Server läuft ohne Internet. Ein Agent (beliebiger OpenAI-kompatibler Endpunkt) oder jeder andere MCP-Client steuert ihn. Die Web-Oberfläche zeigt Ergebnisse und Live-Läufe.

**Tech Stack:** Python 3.12, cadquery 2.8.0, mcp 2.3.0 (`MCPServer`; Starlette und httpx kommen mit), pydantic 2, PyMuPDF 1.28.2 (Vektormessung), poppler-utils, pytest, Docker (amd64 und arm64), Docker Compose.

**Spec:** `docs/superpowers/specs/2026-10-16-drawing2cad-design.md`

## Global Constraints

- Repo-Wurzel: `/Users/abu/hackathon`, Branch `main`, Remote `origin` = `https://github.com/Abuarchiv/Drawing2CAD.git`. Es wird nur lokal committet, Push nur nach ausdrücklicher Freigabe.
- Commit-Nachrichten im Conventional-Commits-Stil. Kein Hinweis auf KI-Werkzeuge, keine Co-Author-Zeilen.
- Basis-Image `python:3.12-slim`. apt-Pakete: `libgl1 libglu1-mesa libxrender1 poppler-utils`.
- Versionen fest gepinnt: `cadquery==2.8.0`, `mcp==2.3.0`, `pytest==8.*`.
- Import immer `from mcp.server.mcpserver import MCPServer, Image`. `mcp.server.fastmcp` existiert in mcp 2.x nicht.
- Einheiten immer mm und Grad. Globales Koordinatensystem mit Z nach oben.
- Ebenen (CadQuery-Konvention, gemessen):
  - `XY`: Normale +Z, u = X, v = Y
  - `XZ`: Normale **−Y**, u = X, v = +Z
  - `YZ`: Normale +X, u = Y, v = Z
  - Diese Zeilen stehen auch im Docstring von `SketchPlane`.
- Datenquelle: `/Users/abu/Downloads/OneDrive_1_16.10.2026/` (21 Teile unter `Drawing2CAD/`, dazu `bct_isolim.xml` und `bct_toltabs.xml`). Ordnernamen enthalten Leerzeichen und Klammern, die PDF-Namen sind uneinheitlich (`*_dwg.pdf`, `*.pdf`, `1 106 0168 3.pdf`).
- Drei Datenordner, alle nicht versioniert:
  - `data/` ist die vollständige Kopie mit Referenz-STEPs. Nur Tests und `scripts/eval_refs.py` nutzen sie.
  - `drawings/` enthält nur die PDFs. Nur dieser Ordner wird für den MCP-Server als `/data` eingehängt (read-only).
  - `tables/` enthält die beiden BCT-XML-Tabellen und wird als `/tables` eingehängt (`D2C_TABLES`, nur für Task 14).
- Ergebnisse liegen unter `/app/results`. `D2C_DATA` und `D2C_RESULTS` überschreiben die Pfade, beide werden bei jedem Aufruf gelesen.
- Sandbox-Grenzwerte:
  - `D2C_TIMEOUT` (Standard 60 s) ist die Wanduhr-Grenze über `subprocess.run(timeout=…)`.
  - RLIMIT_AS 4 GiB, RLIMIT_FSIZE 200 MiB.
  - RLIMIT_CPU = 4·⌈Timeout⌉ + 10 s, nur als Rückfallgrenze. Grund: `import cadquery` allein braucht ca. 2 s CPU in 1,2 s Wanduhrzeit (12 Threads). Ein CPU-Limit gleich dem Timeout würde den Worker vorher per SIGKILL beenden (gemessen).
- Toleranzen: linear 0.01 mm, Achsparallelität |cos| ≥ 0.9999, Roundtrip |ΔV|/V ≤ 1e-6.
- Review-Pflicht: Jedes Maß mit `assumed=true` oder `confidence < 0.8` steht in mindestens einem `ReviewItem.refs`.
- Kernloch-Tabelle für `kind="tapped"` (Innengewinde → Kernloch-Ø): M2 1.6, M2.5 2.05, M3 2.5, M4 3.3, M5 4.2, M6 5.0, M8 6.8, M10 8.5, M12 10.2.
- **TEST-Befehl** (gilt für jeden Task): `docker run --rm --network none -v "$PWD":/app d2c pytest -q <pfad>`
- **Baubar ohne BCT-Daten und ohne API-Key.** Den Technical Score vergibt eine KI, die das Repo nach README baut (50 % der Wertung). Tests, die BCT-Dateien brauchen, tragen `@pytest.mark.bct`. Sie werden mit Begründung übersprungen, wenn `/app/data` fehlt. Alle übrigen Tests nutzen eigene Fixtures unter `tests/fixtures/`. Das Image baut auf `linux/amd64` und `linux/arm64` (amd64 verifiziert: Build 144 s, STEP-Roundtrip gültig).
- BCT-Daten und daraus erzeugte Ergebnisse (`data/`, `drawings/`, `tables/`, `results/`) sind nicht versioniert, bis BCT eine Veröffentlichung im öffentlichen Repo freigibt.
- Sprache: Code, Docstrings, Tool-Beschreibungen, `d2c/instructions.md` und README auf Englisch (auch kleine lokale Modelle verstehen das am besten). Planungsdokumente auf Deutsch.
- Secrets nur in `.env`, das in `.gitignore` steht. Nie einen Key committen.
- Das Modell darf weder die Referenz-STEPs noch die Spec-Tabelle mit Referenzwerten erreichen. Dafür sorgen der Mount nur von `drawings/` und eine Session außerhalb des Repos ohne Datei-Tools (Task 9).

## Zeitplan, Gates und Rollen

Stand Sa 17.10. 00:50. Abgabe So 11:30, Pitch ab 13:00.

| Zeitraum | Gate | Inhalt |
|---|---|---|
| Sa 00:30–07:00 | **G1** 07:00 | Tasks 1–10: Kern. Alle Tests grün, Demo-Teil exportiert, isolierte Teile-Sitzung läuft. |
| Sa 07:00–10:00 | **G2** 10:00 | Task 18 M1 (Sensoraufnahme, Fuss, Welle) → **Muss-Ziel erreicht**. Parallel Task 11 und 14. |
| Sa 10:00–18:00 | **G3** 18:00 | Tasks 12, 13, 15, 16; Task 18 weiter (Ziel: mindestens 12 Teile). NX-Check der ersten STEPs mit BCT-Mentor. |
| Sa 18:00–24:00 | **G4** 24:00 | Task 17, Task 18 weiter, Deck-Entwurf (Task 20). Danach keine neuen Tools mehr. |
| So 00:00–09:00 | **G5** 09:00 | Task 18 Rest (komplexe Zeichnungen soweit möglich), Task 19, Deck und Video. |
| So 09:00–11:15 | Abgabe | Task 21, Puffer bis 11:30. |

**Schnittlinien**, falls ein Gate reißt:
- G1 nach 09:00: Task 17 nur als Ergebnis-Browser ohne Upload; Task 13 nur, wenn komplexe Zeichnungen angegangen werden.
- G2 nach 13:00: Komplexe Zeichnungen 1 und 2 entfallen; Task 15 nur Farben, kein AP242-PMI.
- G3 nach 21:00: Task 16 nur mit Skript-Tests und einem lokalen Modell, kein Live-Upload.
- Nie gekürzt: Baubarkeit (J1), Tests, README, M1, Review-Liste mit Markierung, Pitch-Deck.

**Rollen** (Namen vergibt das Team):

| Rolle | Aufgaben |
|---|---|
| Core (abu mit KI-Implementierern) | Tasks 1–17, 19, 21; Teile-Läufe steuern |
| QA | Task 18 d: jede `review.md` gegen die Zeichnung prüfen; STEPs in einem CAD-Viewer öffnen; mit Windows-Laptop den NIST STEP File Analyzer (C2) |
| Pitch | Task 20: Storyline, Deck, Video, Generalprobe. Kontakt zu Jan Müllerleile (BCT, Implementation Consultant CAD), sobald G2 steht: (1) als „schnelles Team“ die Erweiterung anmelden und nach den zusätzlichen Beispieldaten fragen (Folie 12: „Jan will provide sample data“), (2) die ersten STEPs in NX öffnen lassen (M2, Farben), (3) Freigabe klären, ob erzeugte Modelle der Beispielteile ins öffentliche Repo dürfen |
| Demo/UI | Task 17 prüfen und gestalten, Screenshots fürs Deck; danach QA |

Für die Teamarbeit über GitHub braucht es die Push-Freigabe. Bis dahin bleibt alles lokal auf `dev`.

## Review Focus

1. **Komma als Dezimaltrennzeichen** („76,2“ als 762 gelesen): `Dimension.text` und `value` müssen übereinstimmen. Test `test_text_value_mismatch_rejected` in Task 2.
2. **Rundung oder Fase trifft keine oder ungewollte Kanten**: Keine Kante gewählt ist ein Fehler, die Anzahl gewählter Kanten steht im Report. Tests `test_fillet_no_edge_errors` und `test_fillet_reports_edge_count` in Task 3.
3. **Feature schwebt neben dem Grundkörper** (2 Solids): Der Report meldet `solids=2, ok=false`. Test `test_two_solids_not_ok` in Task 4.
4. **Endlosschleife im Fallback-Skript**: Der Prozess wird nach dem Timeout beendet, die Operation wird nicht angehängt. Tests `test_timeout_kills` (Task 5) und `test_failed_build_not_appended` (Task 7).
5. **Pfad außerhalb von `/data`, Leerzeichen oder Klammern im Pfad, Umlaut im Teilnamen** (`Komplexe Zeichnung 1/1 106 0168 3.pdf`, `Trägerplatte`): Ein Pfad außerhalb wird abgewiesen, die anderen funktionieren. Tests `test_render_rejects_outside_data`, `test_render_path_with_spaces` (Task 6), `test_umlaut_part_name` (Task 7).
6. **Review-Markierung trifft keine Fläche**: Die Markierung wäre unsichtbar. Der Report meldet `ok=false`. Test `test_mark_without_face_not_ok` (Task 4).

---

## Dateistruktur

| Datei | Verantwortung |
|---|---|
| `Dockerfile`, `pyproject.toml`, `.gitignore`, `.dockerignore` | Image und Paket (`pip install -e .[dev]`) |
| `d2c/spec.py` | `PartSpec` und Untermodelle, Review- und Konsistenzregeln |
| `d2c/ops.py` | Operations-Modelle (pydantic, diskriminiert über `op`) und `build(ops)` |
| `d2c/checks.py` | Solid-Prüfung, Maßvergleich, STEP-Roundtrip, Kennzahlen |
| `d2c/worker.py` | Subprozess-Einstieg: JSON über stdin → baut, prüft, exportiert → JSON über stdout |
| `d2c/sandbox.py` | Startet den Worker mit Timeout und rlimits, AST-Prüfung für Skripte |
| `d2c/drawing.py` | PDF → PNG (Ganzseite oder Ausschnitt) mit pdftoppm |
| `d2c/session.py` | Teil-Sessions im Speicher, Persistenz nach `results/<Teil>/` |
| `d2c/review.py` | Erzeugt `review.md` aus Spec und Report |
| `d2c/server.py` | `MCPServer` mit den Tools als dünne Schicht über `session`, stdio oder HTTP |
| `d2c/tolerances.py` | ISO 286 / ISO 2768, Toleranzmitte, Konformität (Task 12) |
| `d2c/vector.py` | Maße aus der PDF-Vektorgeometrie (Task 14) |
| `d2c/agent.py` | Modellunabhängiger Agent für OpenAI-kompatible Endpunkte (Task 16) |
| `d2c/web/` | Ergebnis-Browser und Live-Läufe (Task 17) |
| `d2c/demo.py` | Deterministische Demo ohne LLM (Task 11) |
| `d2c/instructions.md` | Arbeitsanweisung an das KI-Modell (wird als `instructions` mitgegeben) |
| `scripts/eval_refs.py` | Vergleich `results/*/*.step` gegen Referenzen, gibt eine Markdown-Tabelle aus |
| `scripts/replay.py` | Baut alle `results/*/ops.json` neu und prüft sie |
| `docker-compose.yml` | Dienste `mcp` (internes Netz) und `app` (Web, Agent) |
| `tests/` | Je Modul eine Testdatei, `tests/conftest.py`, `tests/fixtures/` (Demo-Zeichnung, Demo-Spec und -Ops, eigene Toleranztabellen) |

---

### Task 1: Gerüst, Docker-Image, Beispieldaten

**Files:** Create `Dockerfile`, `pyproject.toml`, `.gitignore`, `.dockerignore`, `d2c/__init__.py`, `tests/conftest.py`, `tests/test_smoke.py`

**Interfaces:** Produces: Image `d2c` mit `WORKDIR /app`, Entrypoint `python -m d2c.server`. Der TEST-Befehl überschreibt den Entrypoint nicht, sondern ruft `pytest` als Kommando auf. Deshalb nutzt das Image `CMD` statt `ENTRYPOINT`.

- [ ] **Step 1:** Repo ist bereits eingerichtet (`main` folgt `origin/main`). Beispieldaten kopieren:
  - `rsync -a /Users/abu/Downloads/OneDrive_1_16.10.2026/Drawing2CAD/ data/`
  - `rsync -a --include '*/' --include '*.pdf' --exclude '*' /Users/abu/Downloads/OneDrive_1_16.10.2026/Drawing2CAD/ drawings/`
  - `mkdir -p tables && cp /Users/abu/Downloads/OneDrive_1_16.10.2026/bct_*.xml tables/`
- [ ] **Step 2:** `.gitignore`: `data/`, `drawings/`, `tables/`, `results/`, `.env`, `__pycache__/`, `*.egg-info/`, `.pytest_cache/`. `.dockerignore`: `data/`, `drawings/`, `tables/`, `results/`, `.env`, `.git/`.
- [ ] **Step 3:** `pyproject.toml`:
  - Projekt `d2c`, `requires-python = ">=3.12,<3.13"`
  - Abhängigkeiten `cadquery==2.8.0`, `mcp==2.3.0`
  - Extra `dev = ["pytest==8.*"]`
  - Paketdaten `d2c/instructions.md`
  - `[tool.pytest.ini_options]` mit `testpaths = ["tests"]` und `markers = ["bct: needs the BCT sample data mounted at /app/data"]`
- [ ] **Step 4:** `Dockerfile`:
  - apt-Pakete aus den Global Constraints installieren
  - `COPY . /app`, dann `pip install --no-cache-dir -e /app[dev]`
  - `CMD ["python", "-m", "d2c.server"]`
- [ ] **Step 5:** `tests/conftest.py`:
  - autouse-Fixture: `monkeypatch.setenv("D2C_RESULTS", str(tmp_path / "results"))` und `monkeypatch.setenv("D2C_DATA", "/app/data")`. So schreibt kein Test in echte Ergebnisordner.
  - Hook `pytest_collection_modifyitems`: Ist `/app/data` kein Verzeichnis, bekommt jeder Test mit Marker `bct` ein `pytest.mark.skip(reason="BCT sample data not mounted at /app/data")`.
  - Konstante `BCT_DATA = Path("/app/data")` zum Import in Tests.
- [ ] **Step 6:** Test schreiben: `tests/test_smoke.py::test_imports` importiert `cadquery`, `MCPServer`, `Image` und prüft, dass `cadquery.__version__ == "2.8.0"`. `test_pdftoppm_available` prüft, dass `shutil.which("pdftoppm")` und `shutil.which("pdftotext")` nicht None sind. `test_bct_marker_skips_without_data` (Marker `bct`, prüft nur, dass `BCT_DATA` ein Verzeichnis ist; ohne Daten wird er übersprungen).
- [ ] **Step 7:** `docker build -t d2c .`, dann den TEST-Befehl mit `tests/test_smoke.py` ausführen. Erwartet: `3 passed`. Zusätzlich ohne Daten: `docker run --rm --network none d2c pytest -q tests/test_smoke.py` (Image-Inhalt, kein Mount) → `2 passed, 1 skipped`.
- [ ] **Step 8:** Commit `chore: scaffold d2c package and docker image`.

**Dauer:** ca. 30 min

---

### Task 2: PartSpec – Zwischenbeschreibung der Zeichnung

**Files:** Create `d2c/spec.py`, `tests/test_spec.py`

**Interfaces – Produces** (alle `pydantic.BaseModel`, `extra="forbid"`):
- `Source(view: str, cell: str | None)` – `cell` ist das Rasterfeld des Zeichnungsrahmens (A3: A–F/1–8, A4: A–F/1–4) und muss auf `^[A-F][1-8]$` passen. `None` steht für Zeichnungen ohne Raster (die komplexen Zeichnungen).
- `Dimension(id: str, kind: Literal["length","diameter","radius","angle","chamfer","thread","count"], value: float, text: str, source: Source | None, confidence: float (0..1), assumed: bool = False, assumption_basis: str | None = None, tol_upper: float | None = None, tol_lower: float | None = None, fit: str | None = None)` – `tol_upper`/`tol_lower` sind Abmaße in mm (z. B. „31 -0,1“ → `tol_upper=0`, `tol_lower=-0.1`), `fit` ist eine ISO-286-Toleranzklasse (Pattern `^[A-Za-z]{1,2}\d{1,2}$`, z. B. `h10`, `H7`)
- `View(id: str, kind: Literal["front","top","side","section","detail","iso"], scale: str, note: str = "")`
- `Feature(id: str, type: Literal["base","boss","pocket","hole","slot","fillet","chamfer","thread","revolve","other"], dim_ids: list[str], note: str = "")`
- `ExpectedHole(d: float, at: tuple[float,float,float], axis: tuple[float,float,float], dim_ids: list[str])`
- `Expected(bbox: tuple[float,float,float], holes: list[ExpectedHole] = [])` – `bbox` ist Pflicht (xlen, ylen, zlen in Modellkoordinaten)
- `ReviewItem(id: str, refs: list[str], issue: Literal["missing","ambiguous","low_confidence","conflict","convention"], assumption: str, reason: str, mark_near: list[tuple[float,float,float]] = [])` – `mark_near` sind Modellpunkte, an denen die betroffenen Flächen liegen (für die Farbmarkierung, Task 4)
- `Note(id: str, text: str, source: Source | None)` – Hinweise der Zeichnung wortgetreu, z. B. „nicht bemaßte Radien R=1“, Zentrierbohrung „DIN 332 - A 2,0 x 4,25“, Oberflächenangaben
- `PartSpec(name: str (Pattern ^[\w-]+$), drawing: str, page: int = 1, title: str, scale: str, units: Literal["mm"] = "mm", views: list[View], dimensions: list[Dimension], features: list[Feature], notes: list[Note] = [], expected: Expected, review: list[ReviewItem], general_tolerance: str | None = None)` – `general_tolerance` aus dem Schriftfeld, Pattern `^ISO 2768-[fmcv]$` – `drawing` ist der Pfad relativ zu `/data` und bestimmt in `eval_refs` den Referenzordner (erste Pfadkomponente)
- `PartSpec`-Validator. Bei jeder Verletzung wirft er `ValueError` und nennt die betroffene id:
  - (a) ids über Dimensionen, Features, Views, Notes und Review-Einträge hinweg eindeutig
  - (b) jede `ref` (Maß, Feature oder Note) und jede `dim_id` existiert, jedes `source.view` verweist auf eine vorhandene View-id
  - (c) jedes Maß mit `assumed` oder `confidence < 0.8` steht in einem `ReviewItem.refs`
  - (d) `assumed=true` erfordert eine nicht-leere `assumption_basis`
  - (e) `reason` und `assumption` sind nicht leer
  - (f) Text-Wert-Abgleich für Maße mit `assumed=false`: `nums = re.findall(r"\d+(?:[.,]\d+)?", text)`. Mindestens eine Zahl muss nach `float(n.replace(",", "."))` gleich `value` sein (±1e-9). Das deckt „76,2“, „2x Ø6,6“, „Ø6 h10“, „31 -0,1“, „5x45°“, „M8“ ab und fängt „76,2“ mit `value=762`.
  - (h) Toleranzen: Ist `tol_upper` oder `tol_lower` gesetzt, müssen beide gesetzt sein und `tol_lower <= tol_upper` gelten.
  - (g) Gibt es ein Feature mit `type="hole"`, darf `expected.holes` nicht leer sein

- [ ] **Step 1: Tests schreiben** in `tests/test_spec.py`. Basis-Fixture `minimal_spec()` mit 1 View, 2 Maßen (`d1` „Ø19“ = 19.0, conf 0.95; `d2` „76,2“ = 76.2, conf 0.9) und 1 Feature.
  - `test_minimal_valid`
  - `test_duplicate_ids_rejected`
  - `test_unknown_ref_rejected`
  - `test_low_confidence_requires_review` (conf 0.7 ohne Review → Fehler, Meldung enthält `d1`)
  - `test_assumed_requires_basis_and_review`
  - `test_text_value_mismatch_rejected` („76,2“ mit value 762 → Fehler)
  - `test_chamfer_first_number` („5x45°“ mit value 5 → gültig)
  - `test_bad_cell_rejected` („K9“)
  - `test_umlaut_name_ok` (`name="Trägerplatte"`)
  - `test_hole_feature_requires_expected_hole`
  - `test_tolerance_fields_validated` (`tol_lower=0.1, tol_upper=-0.1` → Fehler; nur `tol_upper` → Fehler; `fit="h10"` gültig; `fit="10h"` → Fehler; `general_tolerance="ISO 2768-m"` gültig, `"ISO 2768-x"` → Fehler)
- [ ] **Step 2:** TEST-Befehl `tests/test_spec.py` → FAIL (`ModuleNotFoundError: d2c.spec`).
- [ ] **Step 3:** Modelle und Validator wie oben in `d2c/spec.py` implementieren.
- [ ] **Step 4:** TEST-Befehl → `11 passed`.
- [ ] **Step 5:** Commit `feat(spec): PartSpec schema with review and consistency rules`.

**Dauer:** ca. 1 h

---

### Task 3: Operationen und Geometrie-Build

**Files:** Create `d2c/ops.py`, `tests/test_ops.py`

**Interfaces – Produces:**
- `SketchPlane(name: Literal["XY","XZ","YZ","custom"], offset: float = 0.0, origin: (x,y,z) | None = None, normal: (x,y,z) | None = None, xdir: (x,y,z) | None = None)` → `cq.Workplane(cq.Plane.named(name))`, um `offset` entlang der Normalen verschoben. Bei `custom` sind `origin` und `normal` Pflicht (`cq.Plane(origin, xdir, normal)`; ohne `xdir` wird eine zur Normalen senkrechte Richtung gewählt, sodass u möglichst entlang der globalen X liegt, sonst Y). So entstehen schräge Bohrungen und Flächen (Befestigung, komplexe Zeichnungen). Bei den benannten Ebenen sind `origin`/`normal`/`xdir` verboten.
- `Profile = Annotated[Union[RectProfile, CircleProfile, SlotProfile, PathProfile], Field(discriminator="type")]`. Alle Koordinaten sind lokale Ebenen-Koordinaten (u, v):
  - `RectProfile(type="rect", center: (u,v), w: float, h: float, corner_radius: float = 0)` – `corner_radius > 0` rundet alle 4 Ecken: `wp.center(u, v).placeSketch(cq.Sketch().rect(w, h).vertices().fillet(r))` (verifiziert: 115×115, R22, t 19 → V = 243381.1).
  - `CircleProfile(type="circle", center, d: float)`
  - `SlotProfile(type="slot", center, center_distance: float, width: float, angle: float = 0)` – `center_distance` ist der Abstand der beiden Bogenmittelpunkte (so ist die Nut der Welle bemaßt). Umsetzung: `slot2D(center_distance + width, width, angle)`, denn CadQuery misst die Gesamtlänge (verifiziert: `slot2D(80,12)` → xlen 80, V/t = 68·12 + π·36).
  - `PathProfile(type="path", start: (u,v), segments: list[Segment], fillets: list[{"at": (u,v), "r": float}] = [])`
    - `Segment` = `{"kind":"line","to":(u,v)}` | `{"kind":"arc3","via":(u,v),"to":(u,v)}` | `{"kind":"radius_arc","to":(u,v),"r":float}`. Docstring zu `radius_arc`: „r > 0: Bogen im Uhrzeigersinn, nur ≤ 180°. `arc3` bevorzugen.“
    - Der Pfad wird automatisch geschlossen.
    - `fillets` rundet einzelne Ecken des Profils: `cq.Face.makeFromWires(wire).fillet2D(r, [vertex])`. Die Ecke wird im Umkreis von 0.5 mm um `at` gesucht. Ergibt die Suche nicht genau 1 Treffer, folgt `BuildError`.
    - Tangentiale Übergänge (Haken R35/R16, Trägerplatte R8/R20) werden so als scharfe Ecke plus Rundung gebaut, ohne Tangentenpunkte auszurechnen (verifiziert: Haken ΔV 0.000 %, gültig).
- Operationen (diskriminiert über `op`):
  - `ExtrudeOp(op="extrude", profile, plane, distance: float, mode: Literal["add","cut"]="add", both: bool=False)` – extrudiert entlang +Normale (negativer `distance` = −Normale), `both` symmetrisch.
  - `RevolveOp(op="revolve", points: list[(r,z)] | None = None, profile: PathProfile | None = None, angle: float=360, mode="add")` – Profil auf `XZ` (u = r, v = z), Achse = globale Z. Genau eins von `points` (Polygonzug) oder `profile` (Pfad mit Bögen und `fillets`, z. B. Freistiche R0,3) ist Pflicht. Alle r ≥ 0, sonst Fehler.
  - `HolesOp(op="holes", plane, positions: list[(u,v)] = [], polar: PolarPattern | None = None, d: float, depth: float | None = None, kind: Literal["plain","cbore","csk","tapped"]="plain", cbore_d, cbore_depth, csk_d, csk_angle: float = 90, thread: str | None = None, flip: bool = False)` – bohrt ab der Ebene in **−Normale** (`flip=True`: +Normale). `depth=None` heißt durchgehend (Bohrlänge = BBox-Diagonale + 1). Bei `kind="tapped"` ist `thread` Pflicht (`M<d>` oder `M<d>x<P>`, z. B. „M5“, „M10x1“) und `d` muss dem Nenndurchmesser entsprechen, sonst Fehler. Der gebohrte Ø hängt von `thread_core: Literal["tap_drill","minor"] = "tap_drill"` ab: `tap_drill` nimmt die Kernloch-Tabelle (Regelgewinde) bzw. d − P (Feingewinde); `minor` nimmt den Kerndurchmesser d − 1.082532·P nach ISO 68-1. Steigungen der Regelgewinde: M2 0.4, M2.5 0.45, M3 0.5, M4 0.7, M5 0.8, M6 1.0, M8 1.25, M10 1.5, M12 1.75, M16 2.0, M20 2.5. Hintergrund: Die NX-Referenzen modellieren Innengewinde als Kernlochbohrung (M5 → 4.2), die Referenzen der komplexen Zeichnungen als Kerndurchmesser (M3 → 2.459). Die Wahl gehört als `convention` in die Review-Liste.
  - `PolarPattern(center: (u,v), pitch_d: float, count: int, start_angle: float = 0)` – Positionen bei `start_angle + i*360/count`. Genau eins von beiden ist Pflicht: `positions` nicht leer **oder** `polar` gesetzt. Sonst `ValueError`.
  - `EdgeFinishOp(op="edge_finish", kind: Literal["fillet","chamfer"], size: float, near: list[(x,y,z)], tol: float = 0.5)` – wählt alle Kanten, deren Abstand zu einem `near`-Punkt ≤ `tol` ist. Nahtkanten werden nicht gezählt: Kante `e` ist Naht, wenn `BRep_Tool.IsClosed_s(e.wrapped, f.wrapped)` für eine angrenzende Fläche `f` gilt. 0 Treffer → `BuildError("no edge within tol of near points")`.
  - `ScriptOp(op="script", code: str)` – führt den Code mit `result` (aktuelles `cq.Workplane`), `cq` und `math` aus. Danach muss `result` ein `cq.Workplane` sein.
- `Op = Annotated[Union[ExtrudeOp, RevolveOp, HolesOp, EdgeFinishOp, ScriptOp], Field(discriminator="op")]`
- Jede Operation erbt von `OpBase(BaseModel, extra="forbid")` mit `refs: dict[str, str] = {}`. Ein Eintrag ordnet einen Zahlenparameter der Operation einer `Dimension.id` aus der PartSpec zu, z. B. `{"d": "d3", "profile.w": "d7", "plane.offset": "d2", "positions.1.0": "d9"}`. Schlüssel sind Punkt-Pfade in `model_dump()`, Listenindizes als Zahl. Ein `model_validator` prüft, dass jeder Pfad auf eine Zahl (`int`/`float`, nicht `bool`) zeigt, sonst `ValueError` mit dem Pfad. `build()` ignoriert `refs`. Zweck: Rückverfolgbarkeit jedes Modellwerts auf ein Zeichnungsmaß und automatischer Umbau auf Toleranzmitte (Task 12). Dazu gibt es `get_path(d: dict, path: str)` und `set_path(d: dict, path: str, value: float)` als Modulfunktionen.
- `class BuildError(Exception)`
- `build(ops: list[Op]) -> tuple[cq.Workplane, list[dict]]` – gibt Modell und `build_notes` zurück, z. B. `{"op_index": i, "edges_selected": n}` oder `{"op_index": i, "drilled_d": 4.2}`. Die erste Operation muss `mode="add"` haben. `cut` vor dem ersten `add` → `BuildError`.

- [ ] **Step 1: Tests schreiben** in `tests/test_ops.py`. Erwartungen sind exakt nachgerechnet, Toleranz 1e-6 relativ:
  - `test_extrude_xy_positive_z` (rect 10×20, d 5 → bbox z ∈ [0,5], V = 1000)
  - `test_extrude_xz_goes_negative_y` (bbox y ∈ [−5,0])
  - `test_extrude_offset_plane` (XY, offset 19 → zmin = 19)
  - `test_revolve_cylinder_volume` ([(0,0),(10,0),(10,5),(0,5)] → V = π·100·5)
  - `test_revolve_negative_r_rejected`
  - `test_holes_through` (Box 20×20×10, d 5 → V = 4000 − π·6.25·10)
  - `test_holes_blind_depth`
  - `test_holes_tapped_m5_uses_4_2` (Notiz `drilled_d == 4.2`)
  - `test_holes_tapped_wrong_nominal_rejected` (thread M5, d 6 → Fehler)
  - `test_holes_polar_positions` (count 6, pitch_d 50 → Bohrungsmitten bei Radius 25 ±1e-6)
  - `test_holes_cbore_and_csk_volume_less_than_plain`
  - `test_slot_cut_volume` (center_distance 80, width 12 → V_cut = 80·12·t + π·36·t)
  - `test_path_profile_with_arc` (Halbkreis-Pfad → V = π r²/2 · t)
  - `test_fillet_no_edge_errors`
  - `test_fillet_reports_edge_count` (near = Mitte einer Box-Kante → `edges_selected == 1`)
  - `test_fillet_seam_not_counted` (Zylinder r 10 auf Platte, near = (10, 0, z_Übergang) → `edges_selected == 1`)
  - `test_holes_requires_positions` (weder `positions` noch `polar` → Fehler)
  - `test_path_fillets_corner` (Quadrat 20×20 als Pfad, `fillets=[{at: Ecke, r: 5}]` → V/t = 400 − (25 − π·25/4))
  - `test_cut_first_rejected`
  - `test_script_op_runs` (`result = result.faces(">Z").workplane().hole(2)`)
  - `test_custom_plane_inclined_hole` (Box 40×40×20, Bohrung Ø6 auf `custom`-Ebene mit Ursprung (0,0,20) und Normale (1,0,1) normiert → Zylinderachse unter 45° gegen Z, |cos| zu (1,0,1)/√2 ≥ 0.9999)
  - `test_revolve_profile_with_fillet` (Rechteck-Profil r 0..10, z 0..20 als `profile` mit `fillets` R2 an der Ecke (10,20) → V = π·100·20 − Rundungsabzug (Pappus, Toleranz 1e-4 relativ))
  - `test_thread_minor_and_fine` (M3 mit `thread_core="minor"` → `drilled_d` 2.4588 ±1e-4; M10x1 mit `tap_drill` → 9.0; M10x1 mit `minor` → 8.9175 ±1e-4)
  - `test_refs_valid_paths` (`ExtrudeOp` mit `refs={"profile.w": "d1", "plane.offset": "d2", "distance": "d3"}` ist gültig; `get_path`/`set_path` lesen und schreiben `profile.w`)
  - `test_refs_bad_path_rejected` (`refs={"profile.q": "d1"}` → Fehler; `refs={"mode": "d1"}` → Fehler, kein Zahlenwert)
- [ ] **Step 2:** TEST-Befehl `tests/test_ops.py` → FAIL (`ModuleNotFoundError: d2c.ops`).
- [ ] **Step 3:** In `d2c/ops.py` implementieren.
  - Jede Operation erzeugt einen eigenen Solid, der per `union` bzw. `cut` mit dem Ergebnis verknüpft wird (`clean=True`).
  - Bohrungen sind Zylinder (plus Senkung oder Kegel), keine `Workplane.hole`-Aufrufe. Grund: `hole` hängt von der aktuellen Fläche ab.
  - Kantenwahl: Kanten aus dem **aktuellen** Solid nehmen (`sel = [e for e in wp.edges().vals() if min(e.distance(cq.Vertex.makeVertex(*p)) for p in near) <= tol]`), dann `wp.newObject(sel).fillet(size)` bzw. `.chamfer(size)`. Kanten aus einer anderen Instanz führen zu `Standard_Failure` (verifiziert).
- [ ] **Step 4:** TEST-Befehl → `25 passed`.
- [ ] **Step 5:** Commit `feat(ops): operation models and CadQuery build`.

**Dauer:** ca. 5,5 h

---

### Task 3b: Op-Ergänzungen aus dem Zeichnungskatalog

**Files:** Modify `d2c/ops.py`, `tests/test_ops.py`

Herkunft: Zeichnungskatalog der sieben neuen Teile (Op-Lücken nach Häufigkeit). Aufgenommen wird, was mehrere Teile oder ein Pflichtteil braucht und wenig kostet. Shell, regelbasierte Kantenwahl, Sweep und Senkungstabellen betreffen je ein Teil und bleiben bei `run_script` bzw. in der Review-Liste.

**Interfaces – Produces** (alle Werte im Container verifiziert):
- `ExtrudeOp.taper: float = 0` – Entformungsschräge in Grad, positiv verjüngt in Extrusionsrichtung, über `extrude(..., taper=t)`. Gilt für alle Modi und für `both`. Verifiziert: Kreis Ø90, Höhe 30, 2° → V = 186443.1 (Kegelstumpf r 45 → 43.952); Tasche mit 3° als Schnitt ergibt einen gültigen Solid. Lagerschaft (2°) und Grundplatte (3°).
- `ExtrudeOp.mode: Literal["add", "cut", "intersect"]` – `intersect` bildet die Schnittmenge mit dem bisherigen Körper (Teil „Schnittmenge“). Wie `cut` nicht als erste Op erlaubt.
- `HullProfile(type="hull", circles: list[(u, v, r)])` mit mindestens 2 Kreisen, alle r > 0: konvexe Hülle der Kreise als Profil (Lagerschaft: Nabe und Augen; Hebel-artige Umrisse ohne Hohlkehlen). **Nicht** über `cq.Sketch().hull()`: Das liefert bei Kreisen auf einer Linie entlang u falsche Ergebnisse (Kreise r45 bei (0,0), r15 bei (±75,0) → BBox 135 statt 180) oder bricht ab (`BRep_API: command not done` bei drei gleichen Kreisen). Stattdessen eigene exakte Konstruktion:
  - Reihenfolge der Kreise auf der Hülle über die Stützfunktion h(θ) = max_i(c_i · e(θ) + r_i) auf 7200 Winkeln (zyklische Folge der argmax-Läufe; ein Kreis darf mehrfach vorkommen).
  - Je Übergang i → j die äußere Tangente: Normale n mit n · (c_j − c_i) = r_i − r_j, Berührpunkte c_i + r_i·n und c_j + r_j·n.
  - Daraus ein `PathProfile` (Bogen `arc3` über den Bogenmittelpunkt, dann `line`) und denselben Build-Weg wie `path`. Enthält ein Kreis alle anderen, ist das Ergebnis dieser Kreis.
- `build_notes` meldet `{"op_index": i, "taper": t}`, wenn `taper ≠ 0`, und `{"op_index": i, "hull_circles": [Indizes in Umlaufreihenfolge]}`.

- [ ] **Step 1: Tests schreiben:**
  - `test_extrude_taper_volume` (Kreis Ø90, Höhe 30, 2° → V = 186443.1 ± 0.5)
  - `test_extrude_taper_cut_valid` (Box 100 × 100 × 20, Tasche Ø40 10 tief mit 3° → gültig, Volumen zwischen „ohne Tasche“ und „zylindrische Tasche“)
  - `test_extrude_intersect` (Box 50 × 50 × 50 ∩ Kreis Ø40 entlang Y extrudiert → gültig, V = π·20²·50 ± 0.5)
  - `test_intersect_first_op_rejected` (`BuildError`)
  - `test_hull_collinear_u_and_v` (Kreise r45 bei (0,0), r15 bei (±75,0), Höhe 10 → BBox 180 × 90 × 10, V = 104369.6 ± 0.5; dieselben Kreise entlang v → gleiches Volumen)
  - `test_hull_three_equal_circles` (r10 bei (−50,0), (0,0), (50,0) → gültig, BBox 120 × 20, V = 10·(100·20 + π·100) ± 0.5)
  - `test_hull_contained_circle` (r30 bei (0,0), r5 bei (10,0) → Ergebnis wie Kreis Ø60)
- [ ] **Step 2:** TEST-Befehl `tests/test_ops.py` → neue Tests FAIL.
- [ ] **Step 3:** Implementieren.
- [ ] **Step 4:** TEST-Befehl `tests/` → alle grün.
- [ ] **Step 5:** Commit `feat(ops): draft angle, intersect mode and exact circle hull profile`.

**Dauer:** ca. 1,5 h

---

### Task 4: Prüfungen (R8a, R8b, R8c) und Kennzahlen

**Files:** Create `d2c/checks.py`, `tests/test_checks.py`

**Interfaces – Consumes:** `Expected`, `ExpectedHole` (Task 2). **Produces:**
- `solid_check(wp: cq.Workplane) -> dict` → `{"valid": bool, "solids": int, "free_edges": int, "volume": float, "bbox": [xmin,ymin,zmin,xmax,ymax,zmax], "ok": bool}`. Dabei gilt `ok = valid and solids == 1 and free_edges == 0 and volume > 0`. Freie Kanten werden über `ShapeAnalysis_FreeBounds(shape, False, True)` ermittelt (Konstruktor ohne Toleranz; die Variante mit Toleranz zählt bei einer Einzelfläche 0).
- `dimension_check(wp, expected: Expected) -> list[dict]` – `bbox` vergleicht die Kantenlängen (xlen, ylen, zlen) in Modellkoordinaten. Rückgabe je Prüfung `{"check": "bbox_x"|"bbox_y"|"bbox_z"|"hole", "expected": ..., "actual": ..., "ok": bool, "dim_ids": [...]}`.
  - Für eine Bohrung zählt nur eine zylindrische Fläche (`BRepAdaptor_Surface`, `GeomAbs_Cylinder`), die alle drei Bedingungen erfüllt: \|2r − d\| ≤ 0.01, Abstand des Punkts `at` zur Zylinderachse ≤ 0.01, \|cos(Achse, axis)\| ≥ 0.9999.
  - `actual` für eine Bohrung: nächstgelegener Zylinder `{d, dist}` oder `null`.
- `select_faces(shape, near: list[tuple3], tol: float = 0.5) -> list[cq.Face]` – Flächen mit `face.distance(cq.Vertex.makeVertex(*p)) <= tol` für einen der Punkte
- `step_roundtrip(wp, path: str, marks: list[dict] = []) -> dict` – `marks` = `[{"id": str, "near": [...]}]`.
  - Export: `asm = cq.Assembly(wp.val(), name=<Dateiname ohne Endung>, color=cq.Color(0.6, 0.67, 0.69))`. Für jede Markierung und jede gewählte Fläche `asm.addSubshape(face, name=<id>, color=cq.Color(1.0, 0.5, 0.0))`, dann `asm.export(path)`.
  - Prüfung: Re-Import mit `cq.importers.importStep`.
  - Rückgabe `{"path", "reimport_valid", "solids", "volume_rel_diff", "marks": [{"id", "faces": n}], "ok"}`. `ok` ist falsch, wenn eine Markierung 0 Flächen trifft.
- `metrics(shape) -> dict` → `{"volume", "bbox_sorted": [a ≤ b ≤ c], "cyl_diameters": sorted unique, auf 0.01 gerundet}` (genutzt von `eval_refs`).

- [ ] **Step 1: Tests schreiben:**
  - `test_box_solid_ok`
  - `test_two_solids_not_ok` (zwei getrennte Boxen per `add` → `solids == 2`, `ok` falsch)
  - `test_bbox_check_pass_and_fail`
  - `test_hole_found_by_diameter_and_position`
  - `test_hole_wrong_position_fails` (um 0.5 mm versetzt)
  - `test_hole_wrong_diameter_fails`
  - `test_roundtrip_ok` (tmp_path)
  - `test_marked_faces_colored` (Box, Markierung auf der Oberseite → `faces == 1`, Datei enthält mindestens 2× `COLOUR_RGB`, Re-Import 1 gültiger Solid)
  - `test_mark_without_face_not_ok` (Punkt 50 mm neben der Box → `ok` falsch)
  - `test_metrics_cyl_diameters` (Box mit Ø5- und Ø8-Bohrung → `[5.0, 8.0]`)
- [ ] **Step 2:** TEST-Befehl `tests/test_checks.py` → FAIL.
- [ ] **Step 3:** Implementieren.
- [ ] **Step 4:** TEST-Befehl → `10 passed`.
- [ ] **Step 5:** Commit `feat(checks): solid, dimension and STEP roundtrip validation`.

**Dauer:** ca. 2 h

---

### Task 5: Worker und Sandbox (R5)

**Files:** Create `d2c/worker.py`, `d2c/sandbox.py`, `tests/test_sandbox.py`

**Interfaces – Consumes:** `build`, `BuildError` (Task 3), Check-Funktionen (Task 4). **Produces:**
- Worker-Protokoll: stdin `{"ops": [...], "expected": {...} | null, "marks": [...], "export_path": str | null}` → stdout genau eine JSON-Zeile:
  - Jeder Report hat immer die Schlüssel `ok, error, solid, dims, build_notes, roundtrip`. Die Markierungen stehen in `roundtrip.marks`. Bei Fehler gilt `error = "<Typ>: <Meldung>"`, die übrigen Felder sind `null` bzw. `[]`.
  - Der Worker exportiert bei **jedem** Build (R8c): nach `export_path`, sonst nach `model.step` in seinem temporären cwd. Danach re-importiert er. Bei Erfolg ist `roundtrip` nie `null`.
  - `ok` = Solid ok **und** alle Maßprüfungen ok **und** Roundtrip ok.
- `check_script(code: str) -> None` – wirft `ValueError` bei:
  - jeder `import`-Anweisung (`cq` und `math` sind bereits vorgegeben)
  - den Namen `open exec eval compile __import__ globals locals vars getattr setattr delattr input breakpoint`
  - Attributen oder Namen, die mit `_` beginnen
- `run_worker(payload: dict, timeout: float | None = None) -> dict`:
  - `subprocess.run([sys.executable, "-I", "-m", "d2c.worker"], input=json, capture_output=True, timeout=t, preexec_fn=_limits, env={"PATH": os.environ["PATH"]}, cwd=<tmp>)` innerhalb von `with tempfile.TemporaryDirectory() as tmp`
  - Timeout → Report mit `error = "timeout after <t>s"`
  - Rückgabecode −9 oder −24 (SIGKILL/SIGXCPU) ohne JSON → Report mit `error = "timeout after <t>s (cpu limit)"`
  - anderer Exit-Code ≠ 0 ohne JSON → Report mit `error = "worker crashed: <letzte 500 Zeichen stderr>"`
  - `ScriptOp`s werden vor dem Start mit `check_script` geprüft.
- Im Worker läuft `ScriptOp` mit eingeschränkten Builtins: `abs min max range len float int round sum enumerate zip list tuple dict print`.

- [ ] **Step 1: Tests schreiben:**
  - `test_worker_builds_box` (`ok`, `roundtrip["ok"]` ist wahr)
  - `test_worker_reports_build_error` (cut zuerst)
  - `test_timeout_kills` (Script `while True: pass`, timeout 2 → Fehler `timeout`, Laufzeit < 4 s)
  - `test_script_import_os_rejected`
  - `test_script_open_rejected`
  - `test_script_dunder_rejected` (`result.__class__`)
  - `test_export_roundtrip_via_worker` (export_path in tmp → `roundtrip.ok`)
- [ ] **Step 2:** TEST-Befehl `tests/test_sandbox.py` → FAIL.
- [ ] **Step 3:** Implementieren.
- [ ] **Step 4:** TEST-Befehl → `7 passed`.
- [ ] **Step 5:** Commit `feat(sandbox): isolated build worker with timeout and limits`.

**Dauer:** ca. 1,5 h

---

### Task 6: Zeichnung rendern

**Files:** Create `d2c/drawing.py`, `tests/test_drawing.py`, `scripts/make_demo_drawing.py`, `tests/fixtures/demo_drawing.pdf` (vom Skript erzeugt und eingecheckt)

**Interfaces – Produces:**
- `data_root() -> Path` liest `D2C_DATA` (Standard `/data`) bei **jedem Aufruf**, damit `monkeypatch.setenv` in Tests wirkt
- `resolve_drawing(pdf: str) -> Path`:
  - relativ zu `data_root()` auflösen
  - nach `resolve()` muss der Pfad unter `data_root()` liegen und auf `.pdf` enden, sonst `ValueError`
  - bei fehlender Datei nennt die Meldung alle vorhandenen `*.pdf` (relativ zu `data_root()`)
- `render(pdf: str, page: int = 1, dpi: int = 100, crop: tuple[float,float,float,float] | None = None) -> bytes` (PNG):
  - Seitenzahl aus `pdfinfo`. `page` außerhalb von 1..n → `ValueError` mit der Seitenzahl
  - Seitengröße aus `pdfinfo`, `crop` in Seitenbruchteilen (x0, y0, x1, y1), 0 ≤ x0 < x1 ≤ 1
  - effektive dpi = `min(dpi, 600, floor(2000·72 / längste Ausschnittkante in pt))`, damit die längste Bildseite höchstens 2000 px hat. Die Zeichnungen sind Vektoren, höhere Auflösung bringt also echte Schärfe.
  - Aufruf: `pdftoppm -png -singlefile -f <page> -l <page> -r <dpi> [-x -y -W -H] <pdf> <tmp>` als Argumentliste (kein Shell-String, wegen der Leerzeichen)
- `pdf_info(pdf: str, page: int = 1) -> dict` → `{"pages": n, "page": page, "width_pt": w, "height_pt": h}` aus `pdfinfo -f <page> -l <page>`. `render` nutzt dieselbe Funktion.
- **Eigene Demo-Zeichnung** (damit Tests und README-Demo ohne BCT-Daten laufen): `scripts/make_demo_drawing.py` schreibt mit reiner Standardbibliothek eine 2-seitige PDF (A4 hoch, 595.28 × 841.89 pt) nach `tests/fixtures/demo_drawing.pdf`. Inhalt ist das eigene Teil „D2C Demo Bracket“, geometrisch exakt im Maßstab 1:1 (mm → pt mit 72/25,4):
  - Teil: Platte 80 × 50, Ecken R5, Dicke 10 (**absichtlich nicht bemaßt**, Prüffall wie bei BCT); Zapfen Ø30 mittig, Oberkante bei Gesamthöhe 25; Durchgangsbohrung Ø16 H7 mittig; 4× Ø6,6 durchgehend auf 60 × 30.
  - Seite 1: Draufsicht (Kontur mit R5-Bögen als Bézierkurven, Kreise Ø30, Ø16, 4× Ø6,6) und Vorderansicht (Platte, Zapfen, verdeckte Bohrungskanten gestrichelt), Linienbreite 0.5 pt sichtbar, 0.25 pt Maß- und Mittellinien. Maßtexte als echter Text (Helvetica, `/Encoding /WinAnsiEncoding`, Ø = Byte 0xD8): `80`, `50`, `R5`, `Ø30`, `Ø16 H7`, `4x Ø6,6`, `60`, `30`, `25`. Schriftfeld: `D2C Demo Bracket`, `Drawing no. D2C-001`, `Scale 1:1`, `General tolerances ISO 2768-m`.
  - Seite 2: `Notes: 1. Material S235JR. 2. Deburr all edges.`

- [ ] **Step 1: Skript ausführen, PDF erzeugen, Tests schreiben.** Fixture `demo_root`: `tmp_path/"Demo Teil (A)"/"demo drawing.pdf"` als Kopie der Demo-PDF, `monkeypatch.setenv("D2C_DATA", str(tmp_path))`. Bildbreite immer aus dem PNG-IHDR-Header lesen.
  - `test_demo_drawing_has_text_layer` (`pdftotext` der Fixture enthält `Ø16 H7` und `ISO 2768-m`)
  - `test_pdf_info_pages_and_size` (2 Seiten, 595.28 × 841.89 ±0.01)
  - `test_render_full_page_size` (dpi 100 → Breite 827 ±1)
  - `test_render_path_with_spaces` (`Demo Teil (A)/demo drawing.pdf`, page 2 → PNG)
  - `test_page_out_of_range` (page 3 → `ValueError`, Meldung nennt 2 Seiten)
  - `test_render_crop_size` (crop (0, 0, 0.5, 0.5), dpi 100 → Breite 413 ±1)
  - `test_render_caps_long_side_2000` (dpi 600, ganze Seite → längste Seite ≤ 2000)
  - `test_render_rejects_outside_data` (`../../etc/passwd`)
  - `test_missing_lists_available` (Meldung nennt `Demo Teil (A)/demo drawing.pdf`)
  - `test_render_bct_fuss` mit `@pytest.mark.bct` (`D2C_DATA=/app/data`, `Fuss/Fuss_dwg.pdf`, dpi 100 → Breite 1654 ±1)
- [ ] **Step 2:** TEST-Befehl → FAIL.
- [ ] **Step 3:** Implementieren (nur Standardbibliothek und `subprocess`, kein Pillow).
- [ ] **Step 4:** TEST-Befehl → `10 passed`.
- [ ] **Step 5:** Commit `feat(drawing): render drawing pages and crops, demo drawing fixture`.

**Dauer:** ca. 45 min

---

### Task 7: Session, Persistenz, Review-Liste

**Files:** Create `d2c/session.py`, `d2c/review.py`, `tests/test_session.py`

**Interfaces – Consumes:** `PartSpec` (Task 2), `Op` (Task 3), `run_worker` (Task 5). **Produces:**
- `results_root() -> Path` liest `D2C_RESULTS` (Standard `/app/results`) bei jedem Aufruf
- `class Session`:
  - `specs: dict[str, PartSpec]`, `ops: dict[str, list[dict]]`, `last: dict[str, dict]`
  - `submit_spec(spec: PartSpec) -> dict` – setzt die Ops des Teils zurück, schreibt `results/<name>/spec.json` → `{"ok": True, "part": name, "dimensions": n, "review_items": m}`
  - `apply(part: str, op: dict) -> dict`:
    - baut `ops + [op]` per `run_worker` mit `expected` und `marks` aus `spec.review` (nur Einträge mit `mark_near`)
    - bei `error` (Build-Fehler oder Timeout) wird die Op **nicht** angehängt
    - sonst wird sie angehängt (auch bei `ok=false`), `ops.json` wird geschrieben
    - Rückgabe: Report mit `op_index`
    - Jede `refs`-Zuordnung der Op muss auf eine `Dimension.id` der Spec zeigen, sonst `ValueError("unknown dimension id '<id>' in refs")` vor dem Build.
  - `edit_op(part, index, op) -> dict`, `delete_op(part, index) -> dict` – gleiche Regeln: Der Zustand ändert sich nur, wenn der Build ohne `error` durchläuft.
  - `move_op(part, index, new_index) -> dict` – gleiche Regel. Wird gebraucht, wenn eine Rundung erst vor späteren Schnitten gültig ist.
  - Ist ein Teil nicht im Speicher, aber `results/<name>/spec.json` vorhanden, lädt die Session `spec.json` und `ops.json` nach. So überleben Ops einen Server-Neustart.
  - `state(part) -> dict` → `{"spec_summary", "ops", "last_report"}`
  - `export(part) -> dict`:
    - baut mit `export_path = results/<name>/<name>.step`
    - verweigert den Export, wenn `ok=false`: Rückgabe `{"ok": false, "error": "validation failed", "report": ...}`, nichts wird geschrieben bzw. eine halb geschriebene Datei wird gelöscht
    - schreibt `report.json` und `review.md`
    - Erfolg: `{"ok": true, "files": {"step", "report", "review", "review_json", "ops", "spec"}, "report": ...}`
- Unbekanntes Teil (weder im Speicher noch auf der Platte) → `KeyError("unknown part '<name>'; call submit_spec first")`.
- `review.render(spec: PartSpec, ops: list[dict], report: dict) -> str` – Markdown auf Englisch mit:
  - Kopf (Titel, Zeichnung, Maßstab, Allgemeintoleranz)
  - Tabelle `## Assumptions and open issues` (id, Maß/Feature, Problem, Annahme, Begründung, Quelle, im STEP markierte Flächen)
  - Liste `## Drawing notes` (alle `notes`)
  - Tabelle `## Traceability` (Op-Index, Parameterpfad, Wert, Maß-id, gedruckter Text) für jeden `refs`-Eintrag
  - Tabelle `## Values without dimension reference`: Größenparameter der Ops (`d w h distance size corner_radius width center_distance depth pitch_d cbore_d cbore_depth csk_d` sowie jedes `r` in `revolve.points`), die weder per `refs` zugeordnet sind noch einem `Dimension.value` entsprechen (±0.01). Abgeleitete Werte wie 15 = 25 − 10 stehen hier absichtlich, damit ein Prüfer sie sieht.
  - Tabelle `## Validation` (Prüfung, Soll, Ist, ok)
  - Ergebniszeile `All checks passed: yes` bzw. `no`
- `review.to_json(spec, ops, report) -> dict` mit denselben Inhalten maschinenlesbar (`assumptions`, `notes`, `traceability`, `unreferenced`, `validation`, `all_ok`); `export` schreibt es als `review.json` (für Web-Ansicht und Auswertung).

- [ ] **Step 1: Tests schreiben** (`D2C_RESULTS` kommt aus `conftest.py`):
  - `test_apply_appends_on_success`
  - `test_failed_build_not_appended` (cut als erste Op)
  - `test_invalid_geometry_appended_but_not_ok` (zwei getrennte Bodies)
  - `test_edit_delete_move_op`
  - `test_export_writes_files` (`<name>.step`, `report.json`, `review.md`, `review.json`, `ops.json`, `spec.json`)
  - `test_export_refuses_when_not_ok` (keine `.step`-Datei vorhanden)
  - `test_review_lists_every_assumed_dimension`
  - `test_umlaut_part_name` (`Trägerplatte` → Dateien existieren)
  - `test_unknown_part_error`
  - `test_review_lists_unreferenced_op_values`
  - `test_refs_unknown_dimension_rejected` (Op mit `refs={"d": "nope"}` → `ValueError`, Zustand unverändert)
  - `test_review_traceability_table` (Op mit `refs={"d": "d1"}` → Zeile mit `d1` und gedrucktem Text unter `## Traceability`, Wert nicht unter `## Values without dimension reference`)
  - `test_reload_from_disk` (neue `Session`-Instanz findet Spec und Ops)
- [ ] **Step 2:** TEST-Befehl → FAIL.
- [ ] **Step 3:** Implementieren.
- [ ] **Step 4:** TEST-Befehl → `13 passed`.
- [ ] **Step 5:** Commit `feat(session): op-list sessions, persistence and review list`.

**Dauer:** ca. 1,5 h

---

### Task 8: MCP-Server und Tool-Beschreibungen

**Files:** Create `d2c/server.py`, `d2c/instructions.md`, `tests/test_server.py`, `tests/fixtures/demo_spec.json`, `tests/fixtures/demo_ops.json`

**Interfaces – Consumes:** `Session` (Task 7), `render` (Task 6), Modelle aus Task 2 und 3. **Produces:** `server = MCPServer("drawing2cad", instructions=<instructions.md>)` mit genau diesen 12 Tools. Jeder Docstring enthält einen Satz zum Zweck, die Einheiten, die Konvention für Ebene und Richtung und ein Minimalbeispiel.

| Tool | Signatur | Rückgabe |
|---|---|---|
| `render_drawing` | `(pdf: str, page: int = 1, dpi: int = 100, crop: list[float] \| None = None)` | Liste `[Image (png), str]`; der Text ist JSON aus `pdf_info` plus effektiver dpi, damit das Modell die Seitenzahl kennt |
| `submit_spec` | `(spec: PartSpec)` | dict |
| `extrude` | `(part: str, profile: Profile, plane: SketchPlane, distance: float, mode: "add"\|"cut" = "add", both: bool = False)` | Report |
| `revolve` | `(part: str, points: list[list[float]], angle: float = 360, mode = "add")` | Report |
| `add_holes` | `(part: str, plane: SketchPlane, d: float, positions: list[list[float]] = [], polar: PolarPattern \| None = None, depth: float \| None = None, kind = "plain", cbore_d = None, cbore_depth = None, csk_d = None, csk_angle = 90, thread = None, flip = False)` | Report |
| `edge_finish` | `(part: str, kind: "fillet"\|"chamfer", size: float, near: list[list[float]], tol: float = 0.5)` | Report |
| `run_script` | `(part: str, code: str)` | Report – Docstring: „Nur verwenden, wenn kein anderes Tool die Geometrie abdeckt“ |
| `edit_op` | `(part: str, index: int, op: Op)` – Session erhält `op.model_dump()` | Report |
| `delete_op` | `(part: str, index: int)` | Report |
| `move_op` | `(part: str, index: int, new_index: int)` | Report |
| `get_state` | `(part: str)` | dict |
| `export_step` | `(part: str)` | Rückgabe von `Session.export` |

Fehler aus `Session` und `drawing` (`KeyError`, `ValueError`, `IndexError`) fängt jedes Tool selbst ab und wirft sie neu als `ToolError(e.args[0] if e.args else str(e))` (aus `mcp.server.mcpserver.exceptions`). Grund: mcp 2.3 reicht nur die Meldung von `ToolError` an den Client durch, jede andere Ausnahme wird zu „Error executing tool <name>“ ohne Text (verifiziert). `if __name__ == "__main__": server.run("stdio")`.

`d2c/instructions.md` (Englisch, knapp, nummeriert; kleine Modelle müssen es befolgen können) legt den Ablauf fest:
1. Ganzseite mit 100 dpi rendern, bei mehreren Seiten jede Seite. Ansichten, Maßstab (Schriftfeld), Sammelangaben und Hinweise bestimmen.
2. Jede Ansicht als Ausschnitt mit 300–600 dpi rendern.
3. Jede Maßzahl mit `text` wie gedruckt, `source.cell` und `confidence` erfassen. Was in keiner Ansicht bemaßt ist, mit `assumed=true` und `assumption_basis` erfassen. Die Basis ist das Maßverhältnis in der Zeichnung, z. B. „Breite = 2 × Bogenradius“. Hinweise als `notes` erfassen.
4. `expected` füllen: Gesamt-BBox in Modellkoordinaten, jede Bohrung mit Position.
5. Für jeden Review-Eintrag `mark_near` setzen: ein Punkt auf jeder Fläche, die das unklare Maß bestimmt. Dann `submit_spec`.
6. Geometrie aufbauen, Grundkörper zuerst. Die Reihenfolge ist frei, solange der Report gültig bleibt.
   - Profil-Ecken mit `fillets` im `path`-Profil runden statt mit `edge_finish`.
   - Fasen und Absatz-Einstiche an Drehteilen als Punkte ins `revolve`-Profil legen.
   - `edge_finish` direkt nach dem Körper, dessen Kanten es betrifft. Meldet der Report danach `valid=false`, die Op mit `move_op` früher einordnen.
7. Nach jedem Report:
   - Bei `error`, `solid.ok=false` oder `roundtrip.ok=false` sofort korrigieren.
   - Fehlschläge in `dims` für noch nicht gebaute Features sind bis zur letzten Op normal.
   - Vor `export_step` müssen alle `dims` ok sein. Sonst Ursache ablesen und mit `edit_op` oder `delete_op` korrigieren, höchstens 3 Versuche pro Feature. Danach einen Review-Eintrag anlegen statt weiter raten.
8. `export_step`.

Zusätzliche Regeln:
- Gewinde: innen als `kind="tapped"`, außen als Nenndurchmesser plus Review-Eintrag mit `issue="convention"`.
- Die Referenz-STEPs niemals verwenden.

- [ ] **Step 1: Tests schreiben.** In-process über `await server.call_tool(...)` (pytest mit `asyncio.run`, ohne Plugin).
  - `test_lists_12_tools` (`list_tools` → genau die 12 Namen)
  - `test_render_returns_png_and_info` (Demo-Zeichnung aus `tests/fixtures/` in tmp mit Ordner `Demo Teil (A)`: ImageContent mit `mime_type == "image/png"` und TextContent mit `"pages": 2`)
  - `test_bad_args_tool_error` (`ToolError`)
  - `test_unknown_part_message` (`get_state(part="nope")` → `ToolError`, Meldung enthält `call submit_spec first`)
  - `test_demo_end_to_end`: eigenes Demo-Teil „D2C Demo Bracket“ (Task 6), keine BCT-Daten.
    - `tests/fixtures/demo_spec.json`: name `demo_bracket`, drawing `Demo Teil (A)/demo drawing.pdf`, scale `1:1`, `general_tolerance` `ISO 2768-m`, Views `v_top` (top) und `v_front` (front). Maße: `d80` „80“, `d50` „50“, `r5` „R5“, `d30` „Ø30“, `d16` „Ø16 H7“ (`fit` `H7`), `d66` „4x Ø6,6“ (6.6), `p60` „60“, `p30` „30“, `h25` „25“ (alle confidence 0.95), dazu `t10` (10, text "", `assumed=true`, `assumption_basis` „plate thickness not dimensioned; measured in front view at scale 1:1“, confidence 0.6). Features `f_plate` (base), `f_boss` (boss), `f_bore` (hole), `f_holes` (hole). Notes `Material S235JR`, `Deburr all edges`. `expected.bbox = (80, 50, 25)`, Bohrungen Ø16 bei (0,0,0) und 4× Ø6.6 bei (±30, ±15, 0), Achse (0,0,1). Review `rv1`: refs `[t10]`, issue `missing`, `mark_near` `[[35,0,0],[35,0,10]]`.
    - `tests/fixtures/demo_ops.json`: (1) extrude rect 80×50, `corner_radius` 5 auf XY, distance 10, refs `profile.w→d80`, `profile.h→d50`, `profile.corner_radius→r5`, `distance→t10`; (2) extrude circle Ø30 auf XY offset 10, distance 15, refs `profile.d→d30`, `plane.offset→t10`; (3) holes d 16 auf XY offset 25 bei (0,0), durchgehend, refs `d→d16`; (4) holes d 6.6 auf XY offset 10 bei (±30, ±15), refs `d→d66`.
    - Abbildung `op` → Tool: `extrude`→`extrude`, `revolve`→`revolve`, `holes`→`add_holes`, `edge_finish`→`edge_finish`, `script`→`run_script`. Ablauf über die Tools: `submit_spec`, alle Ops, `export_step` → `ok == True`, `.step` existiert und enthält `COLOUR_RGB`, `review.md` enthält `All checks passed: yes`, eine Zeile mit `t10` unter `## Assumptions and open issues` und den Wert 15 unter `## Values without dimension reference`.
- [ ] **Step 2:** TEST-Befehl → FAIL.
- [ ] **Step 3:** Implementieren.
- [ ] **Step 4:** TEST-Befehl `tests/` (komplett) → alle grün.
- [ ] **Step 5:** Commit `feat(server): MCP tools and model instructions`.

**Dauer:** ca. 2,5 h

---

### Task 9: Isolierte Teile-Läufe (außerhalb des Repos)

**Files:** nichts im Repo. Create `/Users/abu/d2c-run/mcp.json`, `/Users/abu/d2c-run/run_part.sh`

Zweck: Teile werden in einer Sitzung umgesetzt, die nur die MCP-Tools sieht. Keine Datei-Tools, kein Shell-Zugriff, keine Referenz-STEPs.

- [ ] **Step 1:** `mcp.json`: Server `drawing2cad`, Befehl `docker`, Argumente `run -i --rm --network none -v /Users/abu/hackathon/drawings:/data:ro -v /Users/abu/hackathon/tables:/tables:ro -v /Users/abu/hackathon/results:/app/results d2c:prod`. `d2c:prod` ist ein Tag auf einen geprüften Stand (`docker tag d2c d2c:prod` nach grünem Testlauf), damit laufende Code-Änderungen keine Teile-Läufe stören.
- [ ] **Step 2:** `run_part.sh <pdf relativ zu drawings/> <teilname>` ruft im Ordner `/Users/abu/d2c-run` den Headless-Client auf (verifiziert: ohne Tools sieht die Sitzung nichts):
  - `claude -p "<Auftrag>" --model claude-sonnet-5-5 --mcp-config mcp.json --strict-mcp-config --tools "" --allowedTools "mcp__drawing2cad" --output-format stream-json --verbose --no-session-persistence --setting-sources ""`
  - Auftrag: „Convert the drawing `<pdf>` into a validated STEP model following the server instructions. Use part name `<teilname>`.“
  - Log nach `/Users/abu/d2c-run/logs/<teilname>.jsonl`.
- [ ] **Step 3:** Rauchtest mit der Demo-Zeichnung (`drawings/Demo/demo_drawing.pdf` als Kopie der Fixture): `export_step` liefert `ok: true`, `results/demo_bracket/review.md` nennt die angenommene Dicke. Zusätzlich prüfen: Ein Aufruf von `render_drawing` mit `pdf="Fuss/Fuss.stp"` wird abgewiesen.
- [ ] **Step 4:** Kein Commit (nichts im Repo).

**Dauer:** ca. 20 min

---

### Task 10: Auswertungs- und Replay-Skripte

**Files:** Create `scripts/eval_refs.py`, `scripts/replay.py`, `tests/test_scripts.py`

**Interfaces – Consumes:** `metrics` (Task 4), `run_worker` (Task 5). **Produces:**
- `eval_refs.py`:
  - vergleicht jedes `<results_root()>/<T>/<T>.step` mit der einzigen `*.stp` ohne `_PMI` im Ordner `<D2C_DATA>/<erste Pfadkomponente von spec.drawing>/`
  - eine ungültige Referenz (Komplexe Zeichnung 2) wird trotzdem verglichen, die Spalte MATCH zeigt dann `Referenz ungültig`
  - Ausgabe: Markdown-Tabelle mit den Spalten Teil | ΔV % | ΔBBox max mm | Ø fehlend | Ø zusätzlich | MATCH
  - MATCH nach Spec Abschnitt 5
  - Exit-Code 0 immer, die Tabelle ist reine Information
  - schreibt die Tabelle immer auch nach `<results_root()>/EVAL.md` und die Zeilen als `<results_root()>/EVAL.json` (Liste von Objekten mit denselben Spalten plus `volume`, `bbox_sorted`, `ref_volume`, `ref_bbox_sorted`)
  - Referenzordner kommt aus `D2C_REF_DATA` (Standard `/app/data`), bei jedem Aufruf gelesen
- `replay.py [--export] [teil ...]`: baut jedes `<results_root()>/*/ops.json` (oder nur die genannten Teile) mit `expected` aus `spec.json` neu → eine Zeile je Teil mit `ok`. Exit-Code 1, wenn ein Teil nicht `ok` ist. Mit `--export` läuft stattdessen `Session().export(teil)` (frische Session, lädt von der Platte). So bekommen früh erzeugte Teile spätere Export-Funktionen (GLB, PMI, Toleranzmitte), ohne das Modell erneut zu befragen.

- [ ] **Step 1: Tests schreiben:**
  - Alle Referenzen erzeugen die Tests selbst in tmp (CadQuery-Box mit Bohrung als STEP), keine BCT-Daten.
  - `test_eval_identical_is_match` (Referenz gegen eine Kopie ihrer selbst)
  - `test_eval_detects_missing_diameter` (Ergebnis ohne Bohrung → Ø fehlend nennt den Durchmesser)
  - `test_eval_resolves_folder_with_spaces` (Ordner `Komplexe Zeichnung 3` mit `1 763 1487 0.stp` und Köder `1 763 1487 0_PMI.stp`; `spec.drawing = "Komplexe Zeichnung 3/1 763 1487 0.pdf"` → nimmt die Datei ohne `_PMI`)
  - `test_replay_fails_on_bad_part`
  - `test_replay_export_rewrites_step` (Demo-Teil aus den Fixtures per Session exportieren, `.step` löschen, `replay.py --export demo_bracket` → `.step` existiert wieder, Exit-Code 0)
  - `test_eval_bct_fuss_reference` mit `@pytest.mark.bct` (`metrics` der Referenz `Fuss/Fuss.stp`: Volumen 317209.8 ±0.5)
- [ ] **Step 2:** TEST-Befehl → FAIL.
- [ ] **Step 3:** Implementieren.
- [ ] **Step 4:** TEST-Befehl → `6 passed`.
- [ ] **Step 5:** Commit `feat(scripts): reference evaluation and replay`.

**Dauer:** ca. 1 h

---

### Task 11: Demo-Befehl und MCP über HTTP

**Files:** Create `d2c/demo.py`, `tests/test_demo.py`; Modify `d2c/server.py`, `tests/test_server.py`

**Interfaces – Consumes:** `Session` (Task 7), `tests/fixtures/demo_spec.json` und `demo_ops.json` (Task 8). **Produces:**
- `python -m d2c.demo [--out DIR]` (Standard `/tmp/d2c-demo`): setzt `D2C_RESULTS=DIR`, lädt die beiden Fixtures relativ zum Repo (`Path(__file__).resolve().parents[1] / "tests/fixtures"`), ruft `submit_spec`, alle Ops über `apply` und `export` auf. Ausgabe auf stdout: je Prüfung eine Zeile `PASS`/`FAIL` mit Soll und Ist, die Annahmen aus der Review-Liste, die geschriebenen Dateien, zum Schluss `All checks passed: yes|no`. Exit-Code 0 genau dann, wenn der Export `ok` ist. Kein LLM, kein Netz: Das ist der Nachweis „läuft“ für den KI-Prüfer.
- `python -m d2c.server [--http HOST:PORT]`: ohne Option stdio wie bisher, mit Option MCP über streamable HTTP unter dem Pfad `/mcp`. Die passende API in mcp 2.3 vorher im Container nachsehen (`MCPServer.run` und die Host-/Port-Einstellungen) und im Report belegen.

- [ ] **Step 1: Tests schreiben:**
  - `test_demo_cli_ok` (Subprozess `python -m d2c.demo --out <tmp>` → Exit-Code 0, `<tmp>/demo_bracket/demo_bracket.step` existiert, stdout enthält `All checks passed: yes`)
  - `test_server_http_lists_tools` in `tests/test_server.py` (Server als Subprozess auf freiem Port, Client über `mcp.client.streamable_http`, `list_tools` liefert dieselben 12 Namen, Server danach beenden; Wartezeit auf den Start höchstens 20 s)
- [ ] **Step 2:** TEST-Befehl → FAIL.
- [ ] **Step 3:** Implementieren.
- [ ] **Step 4:** TEST-Befehl `tests/` → alle grün.
- [ ] **Step 5:** Commit `feat: demo command and HTTP transport for the MCP server`.

**Dauer:** ca. 45 min

---

### Task 12: Toleranzen (Erweiterung X1)

**Files:** Create `d2c/tolerances.py`, `tests/test_tolerances.py`, `tests/fixtures/tables/isolim_subset.xml`, `tests/fixtures/tables/toltabs_subset.xml`; Modify `d2c/session.py`, `d2c/review.py`, `d2c/server.py`, `d2c/instructions.md`

Die Felder `tol_upper`, `tol_lower`, `fit` und `general_tolerance` gibt es seit Task 2. Hier kommen Grenzwerte, Toleranzmitte, Konformitätsprüfung und die Export-Variante dazu.

**Interfaces – Produces:**
- Tabellen aus `D2C_TABLES` (Standard `/tables`, bei jedem Aufruf gelesen): die erste Datei `*isolim*.xml` und die erste `*toltabs*.xml` im Ordner. Format wie die BCT-Dateien (Kodierung aus dem XML-Kopf, ISO-8859-1): in `isolim` ein Knoten je Toleranzklasse mit Wertzeilen, in `toltabs` `toltable entry="DIN ISO 2768 (medium/mittel)"` usw. Bereichsattribute `over`/`to` und `from`/`up_to` werden beide gelesen. Ein Wert gehört zum Bereich mit over < Nennmaß ≤ to; bei `from` gilt ≤ auch unten.
- Die Test-Fixtures sind eigene, kleine Tabellen im selben Format (nicht die BCT-Dateien), mit öffentlich bekannten ISO-Werten: `H7` 10–18 mm 0/+0.018, `h10` 3–6 mm −0.048/0, `H10` 3–6 mm 0/+0.048, ISO 2768-m Längen 6–30 mm ±0.2 und 30–120 mm ±0.3. Das genaue XML-Format aus `tables/bct_isolim.xml` und `tables/bct_toltabs.xml` übernehmen.
- `limits(dim: Dimension, general: str | None) -> tuple[float, float, str]` → (unteres Abmaß, oberes Abmaß, Quelle `"explicit"|"fit"|"general"|"none"`). Explizit vor Passung vor Allgemeintoleranz. Allgemeintoleranz gilt nur für `kind` `length`, `diameter`, `radius`.
- `mid_value(dim, general) -> float` = Nennmaß + (oben + unten) / 2.
- `apply_mode(ops: list[dict], spec: PartSpec, mode: Literal["nominal","mid"]) -> tuple[list[dict], list[dict]]`: Kopie der Ops, in der bei `mid` jeder `refs`-Pfad, dessen Maß eine Toleranz hat, den Mittelwert bekommt (`set_path` aus Task 3). Zweite Rückgabe: Änderungen `{op_index, path, dim_id, nominal, mid}`.
- `compliance(spec, ops, report, mode) -> list[dict]` je toleriertem Maß: `{dim_id, text, nominal, lower, upper, source, values, in_tolerance}`. `values` sind alle per `refs` gebundenen Op-Werte und, falls ein `ExpectedHole` das Maß nennt, der gemessene Zylinder-Ø aus dem Report. `in_tolerance` ist wahr, wenn alle Werte in [Nennmaß + unten, Nennmaß + oben] liegen (±1e-6).
- `Session.export(part, variant: Literal["nominal","mid"] = "nominal")`: `mid` baut mit `apply_mode` und schreibt `<name>_mid.step` und `report_mid.json`. Beide Varianten schreiben `compliance` in den Report.
- `review.md` bekommt `## Tolerances` (Maß, Text, Nennmaß, unteres/oberes Abmaß, Mitte, Quelle, eingehalten nominal, eingehalten mid).
- Tool `export_step(part, variant="nominal")` bekommt den Parameter. `instructions.md`: Toleranzen wie gedruckt erfassen (`tol_upper`/`tol_lower` bzw. `fit`, `general_tolerance` aus dem Schriftfeld) und Werte per `refs` an Maße binden.

- [ ] **Step 1: Tests schreiben** (`D2C_TABLES` zeigt auf `tests/fixtures/tables`):
  - `test_fit_h10_6` (6 h10 → (−0.048, 0.0, "fit"))
  - `test_fit_H10_4` (4 H10 → (0.0, +0.048, "fit"))
  - `test_iso2768_m_25` (25 mm, mittel → ±0.2, "general")
  - `test_range_boundary_inclusive` (6.0 liegt im Bereich 3–6)
  - `test_explicit_beats_fit`
  - `test_mid_asymmetric` („31 -0,1“ → 30.95)
  - `test_apply_mode_substitutes_refs` (Demo-Ops: `d16` mit `H7` → Op 3 `d` = 16.009, Änderungsliste nennt `d16`)
  - `test_compliance_flags_nominal_outside` (Maß 31 mit −0.1/−0.3: nominal nicht eingehalten, mid 30.8 eingehalten)
  - `test_export_mid_variant` (Demo-Teil → `demo_bracket_mid.step` existiert, Report zeigt für `d16` gemessenen Ø 16.009 und `in_tolerance` wahr)
  - `test_bct_tables_h10_6` mit `@pytest.mark.bct` (echte Tabellen aus `/app/data/../tables` bzw. `D2C_TABLES=/app/tables`: 6 h10 → −0.048/0)
- [ ] **Step 2:** TEST-Befehl → FAIL.
- [ ] **Step 3:** Implementieren (`xml.etree.ElementTree`).
- [ ] **Step 4:** TEST-Befehl `tests/` → alle grün.
- [ ] **Step 5:** Commit `feat(tolerances): ISO 286 fits, ISO 2768 general tolerances, mid-tolerance export and compliance`.

**Dauer:** ca. 2,5 h

---

### Task 13: Textebene lesen (`read_drawing_text`)

**Files:** Create `d2c/text.py`, `tests/test_text.py`; Modify `d2c/server.py`, `d2c/instructions.md`, `tests/test_server.py`

Machbarkeit belegt (R&D `/private/tmp/claude-501/-Users-abu-hackathon/35627516-c582-4294-afac-04893f3a49ec/scratchpad/cx/d3_dims.py`): Die drei komplexen Zeichnungen haben eine echte Textebene. In Zeichnung 3 kommen alle 12 tolerierten Maße, 6 Passungen und 10 Toleranzrahmen korrekt heraus. Symbole stecken in Symbolschriften, die Zuordnung ist am Bild geprüft. Die 18 übrigen Zeichnungen haben Text als Pfade, dort liefert das Tool nichts (das ist ein gültiges Ergebnis).

**Interfaces – Produces:**
- `read_text(pdf_path, page=1, region=None) -> list[dict]` über `pdftohtml -xml -i -f <p> -l <p>` (liefert Fontnamen je Textstück) als Argumentliste. Je Eintrag: `text` (mit ersetzten Symbolen), `x0, y0, x1, y1` als Bruchteile der **angezeigten** Seite (Ursprung oben links, wie `crop` in Task 6; Seitendrehung beachten, z. B. A3 quer als gedrehtes Hochformat 842 × 1191 pt), `font`, `size`, `vertical`, `parsed`.
- Symbolzuordnung nach Fontfamilie (nur in diesen Fonts ersetzen, denn `L` ist in normaler Schrift ein Schnittbuchstabe):
  - `ISO1Symbols`: `O`→`Ø`, `u`→`±`, `n`→`⊥`, `l`→`⌖`, `i`→`∥`, `r`→`▱`, `a`→`◎`, `d`→`⌯`, `^`→`↗`
  - `GDTSymbols`: `L`→`Ⓔ`
- `parse_dimension_text(text) -> dict | None` für gängige Formen, Rückgabe `{prefix, count, nominal, tol_upper, tol_lower, fit, envelope, thread}` mit Komma als Dezimaltrenner: „Ø6 h10 Ⓔ“, „87,5 -0,2“, „37,5 +0,1“, „32±0,08“, „55 ±,1“ (führende Null fehlt), „R 0,3“, „M10x0,75“, „4x Ø6,6“, „Ø10,5 +1,3“. Einseitiges Abmaß: das andere ist 0. Nicht erkannt → `None`.
- MCP-Tool `read_drawing_text(pdf: str, page: int = 1, region: list[float] | None = None)` mit Pfadprüfung über `resolve_drawing` (Task 6). Gibt höchstens 300 Einträge zurück, sonst einen Hinweis, eine Region zu wählen. Bei 0 Einträgen kommt der Text „no text layer (text is vector outlines): read dimensions from the rendered image“ zurück.
- `instructions.md`: Pro Seite zuerst `read_drawing_text`. Hat die Seite Text, sind die gedruckten Werte daraus maßgeblich; das Bild dient nur der Zuordnung zur Geometrie. Bekannte Fallen als kurze Liste: gestapelte Abmaße stehen als eigene Einträge in der Nähe; Schrägtext kann zerlegt oder gekürzt sein („(20,147)“ → „20,1“), deshalb nie aus einem Fragment schließen, sondern im Bild prüfen.

- [ ] **Step 1: Tests schreiben:**
  - `test_demo_text_items` (Demo-Zeichnung: Einträge `Ø16 H7` mit `parsed.fit == "H7"`, `4x Ø6,6` mit `count == 4` und `nominal == 6.6`, Koordinaten in 0..1)
  - `test_region_filter` (Region um das Schriftfeld → enthält `Scale 1:1`, nicht `Ø30`)
  - `test_parse_dimension_text_cases` (alle Beispiele oben, inklusive `55 ±,1` → ±0.1 und `Ø10,5 +1,3` → oben 1.3, unten 0)
  - `test_symbol_mapping_only_in_symbol_fonts` (synthetische `pdftohtml`-XML-Zeichenkette: `L` in `ISO1Symbols` bleibt `L`, in `GDTSymbols` wird `Ⓔ`; Helvetica-`O` bleibt `O`)
  - `@pytest.mark.bct` `test_kz3_fits_and_envelope` (`Komplexe Zeichnung 3/1 763 1487 0.pdf`: mindestens 5 Einträge mit `fit` aus {h10, H10}, mindestens einer mit `envelope`, `Ø17` mit `tol_lower == -0.2`)
  - `@pytest.mark.bct` `test_vector_text_drawing_returns_empty` (`Fuss/Fuss_dwg.pdf` → 0 Einträge)
  - `test_lists_13_tools` ersetzt die Zählung in `tests/test_server.py`
- [ ] **Step 2:** TEST-Befehl → FAIL.
- [ ] **Step 3:** Implementieren (nur Standardbibliothek und poppler).
- [ ] **Step 4:** TEST-Befehl `tests/` → alle grün.
- [ ] **Step 5:** Commit `feat(text): read the drawing text layer with symbol fonts and dimension parsing`.

**Dauer:** ca. 1,5 h

---

### Task 14: Fehlende Maße aus der Vektorgeometrie messen (`measure_drawing`)

**Files:** Create `d2c/vector.py`, `tests/test_vector.py`; Modify `pyproject.toml` (`pymupdf==1.28.2`), `d2c/server.py`, `d2c/instructions.md`, `tests/test_server.py`

Machbarkeit belegt (R&D-Code `/private/tmp/claude-501/-Users-abu-hackathon/35627516-c582-4294-afac-04893f3a49ec/scratchpad/vector/measure.py`, 29/29 Prüfwerte ≤ 0,0003 mm Abweichung): Kreise und Bögen der Ansichten sind Bézierkurven, deren Mittelpunkt aus den Kontrollpunkt-Tangenten exakt folgt. Die Sensoraufnahme-Breite misst 20,0000 mm bei 2:1. Beim 3-Loch-Hebel steht im Schriftfeld 1:1, gezeichnet ist 2:1; `suggest_scale` erkennt das mit 9 von 9 Stimmen.

**Interfaces – Produces** (Übernahme des R&D-Codes, bereinigt; Seiten **1-basiert** wie in Task 6; `import pymupdf`, nicht `fitz`):
- `extract(pdf_path, page=1, region=None, scale=1.0, edge_width="auto") -> dict` mit `scale_used`, `styles` (Strichklassen), `extent_mm`, `extent_basis`, `circles` (`cx, cy, d_mm`), `arcs` (`cx, cy, r_mm, sweep`), `lines`, `contours` (BBox, Fläche). `region` in Seitenbruchteilen (x0, y0, x1, y1), Ursprung oben links, wie `crop` in `render`.
- `verify(res, claims, tol=0.05) -> list[dict]`, Claims als `"d=19"`, `"r=10"`, `"L=49"`; je Claim `measured_mm`, `deviation_mm`, `status` (`ok`/`MISMATCH`/`no_candidates`), `n_candidates_within_tol`.
- `suggest_scale(pdf_path, printed_values, page=1, region=None) -> list[dict]` (`scale`, `votes`), bester zuerst.
- MCP-Tool `measure_drawing(pdf: str, page: int = 1, region: list[float] | None = None, scale: float | None = None, printed_dims: list[float] = [], expect: list[str] = [], edge_width: str | float = "auto")`: Pfadprüfung über `resolve_drawing` (Task 6). Gibt kompaktes JSON zurück: `scale_used`, `scale_suggestion` (aus `printed_dims`, falls gegeben), `extent_mm`, die 12 größten Kreise und Bögen, `verify` für `expect`, und `notes`. `notes` meldet zum Beispiel „title-block scale disagrees with geometry“, wenn `scale` gesetzt ist und die beste Stimme abweicht. Docstring mit Beispiel: fehlende Breite messen.
- `instructions.md` bekommt diese Regeln:
  - Fehlt ein Maß, wird es mit `measure_drawing` in der Region der Ansicht und mit dem Maßstab aus dem Schriftfeld gemessen. Das Maß gilt dann als `assumed=true` mit `assumption_basis` „measured from drawing vector geometry: <Wert> mm (view <id>, scale <s>)“ und bekommt einen Review-Eintrag `missing`.
  - Gelesene Hauptmaße mit `expect` gegenprüfen. Ein `MISMATCH` wird zu einem Review-Eintrag `conflict`.
  - Weicht `scale_suggestion` vom Schriftfeld ab, entsteht ein Review-Eintrag `conflict`.

- [ ] **Step 1: Tests schreiben:**
  - `test_demo_front_view_thickness` (eigene Demo-Zeichnung, Region der Vorderansicht, Maßstab 1 → `verify(["L=10", "L=80", "L=25"])` alle `ok`)
  - `test_demo_top_view_circles` (Region der Draufsicht → Kreise Ø30, Ø16, 4× Ø6.6 innerhalb 0.01)
  - `test_region_filters` (Region ohne Geometrie → keine Kreise, `extent_mm` leer bzw. `None`)
  - `test_measure_tool_rejects_outside_data` (`../../etc/passwd` → `ToolError`)
  - `@pytest.mark.bct` `test_bct_sensoraufnahme_width` (Region (0.10, 0.08, 0.97, 0.45), Maßstab 2 → `L=20` und `L=49` ok, Abweichung ≤ 0.05)
  - `@pytest.mark.bct` `test_bct_hebel_scale_suggestion` (gedruckte Werte 10, 12, 22, 110, 51.8, 40.1 → beste Stimme 2.0)
  - `@pytest.mark.bct` `test_bct_fuss_holes` (Region (0.10, 0.46, 0.53, 0.90), Maßstab 1 → `d=19`, `d=33`, `d=57`, `r=22`, `L=115`, `L=71` ok)
  - `test_lists_14_tools` ersetzt die Zählung in `tests/test_server.py` (12 + `measure_drawing` + `read_drawing_text` aus Task 13)
- [ ] **Step 2:** TEST-Befehl → FAIL.
- [ ] **Step 3:** Code aus dem R&D-Skript übernehmen. Die BCT-Pfade aus `CASES` wandern als `@pytest.mark.bct`-Tests in `tests/test_vector.py`. Kein CLI, kein Selbsttest im Modul. Die Demo-Zeichnung muss Kreise als vier kubische Béziers zeichnen (Task 6); falls nicht, Generator anpassen und PDF neu erzeugen.
- [ ] **Step 4:** TEST-Befehl `tests/` → alle grün; zusätzlich mit gemounteten BCT-Daten die drei `bct`-Tests.
- [ ] **Step 5:** Commit `feat(vector): measure missing dimensions from PDF vector geometry`.

**Dauer:** ca. 2 h

---

### Task 15: Export für NX und Web: AP242 mit semantischem PMI, Farben, GLB

**Files:** Create `d2c/export.py`, `tests/test_export.py`; Modify `d2c/checks.py` (`step_roundtrip` nutzt `export.write_step`), `d2c/worker.py`, `d2c/session.py`, `d2c/review.py`, `d2c/instructions.md`

Machbarkeit belegt (R&D `/private/tmp/claude-501/-Users-abu-hackathon/35627516-c582-4294-afac-04893f3a49ec/scratchpad/pmi/`: `ap242_pmi_roundtrip.py`, `asm_pmi.py`, `glb_export.py`, `pmi_dump.py`). Was BCT vorgibt: In `Sensoraufnahme_PMI.stp` ist die fehlende Breite ein **semantisches PMI-Maß** (`DIMENSIONAL_LOCATION` 20 mm zwischen den Flächen y = −10 und y = +10), ohne Notiz. Blau (0.2/0.4/0.8) liegt dort nur auf den Kosmetik-Gewindekreisen. Die Referenzen der komplexen Zeichnungen färben Gewindeflächen grün (0.396/0.941/0.451).

**Interfaces – Produces:**
- `write_step(shape, path, *, name: str, marks: list[dict], pmi: list[dict], threads: list) -> dict` schreibt **AP242** über XCAF:
  - `Interface_Static.SetCVal_s("write.step.schema", "AP242DIS")` erst nach `STEPControl_Controller.Init_s()`, `write.stepcaf.subshapes.name = 1`. Wurzel als `cq.Compound.makeCompound([solid])`, sonst liefert `AddSubShape` Null-Labels.
  - Farben: Körper Stahl (0.6, 0.67, 0.69); Flächen aus Review-Markierungen Orange (1.0, 0.5, 0.0); Gewindeflächen (aus `kind="tapped"`) Grün (0.396, 0.941, 0.451) wie in den BCT-Referenzen.
  - Markierte Flächen heißen `CHECK <review-id>` und liegen auf dem Layer `ASSUMED_CHECK`.
  - Semantisches PMI je Eintrag in `pmi`: `{"type": "diameter", "face": f, "value", "tol_upper", "tol_lower", "fit", "text"}` → `DIMENSIONAL_SIZE` (Durchmesser) mit `PLUS_MINUS_TOLERANCE` bzw. `LIMITS_AND_FITS`; `{"type": "distance", "faces": [f1, f2], "value", ..., "description"}` → `DIMENSIONAL_LOCATION`. Die Beschreibung landet als `DESCRIPTIVE_REPRESENTATION_ITEM` (die XCAF-Notiz-API wird nicht exportiert).
  - Workaround OCCT 7.9.3: Der Passungsgrad wird um 2 zu hoch geschrieben (`IT7` → `'9'`). Deshalb `DimensionGrade(n - 1)` übergeben, abgesichert durch einen Test, der `LIMITS_AND_FITS('H','hole','7','')` im Dateitext erwartet.
  - Rückgabe `{"path", "schema": "AP242DIS", "pmi_written": n, "colored_faces": n}`.
- `pmi_from(spec, ops, shape, report) -> list[dict]` erzeugt die PMI-Einträge:
  - je `ExpectedHole`, dessen Maß gefunden wurde: Durchmesser an der gefundenen Zylinderfläche, mit Toleranz bzw. Passung des Maßes;
  - je Review-Eintrag `missing` mit genau einem angenommenen Längenmaß, dessen `mark_near` zwei parallele ebene Flächen trifft: Abstandsmaß mit Beschreibung `ASSUMED: <assumption> - <reason> - please check`. Das ist genau BCTs Muster bei der Sensoraufnahme, plus Kennzeichnung als Annahme.
- `write_glb(shape, path, marks, threads) -> dict` über `cq.Assembly(...).export(path)` mit Endung `.glb`; danach Material-Patch (`metallicFactor` 0.0, `roughnessFactor` 0.8) im JSON-Chunk, nur Standardbibliothek. Neben der GLB eine `marks.json` (Materialfarbe → Review-ids), denn glTF übernimmt keine Flächennamen.
- `read_pmi(path) -> dict` (XCAF-Reader; Iteration über `TDF_AttributeIterator` statt `FindAttribute`, das unter OCP kein Handle füllt): Schema, Maße mit Wert, Toleranz und Beschreibung, Farben, Layer. Dient als automatische PMI-Prüfung auf dem Mac (C2-Ersatz) und füllt `pmi.json`.
- `step_roundtrip` (Task 4) schreibt über `write_step` und prüft wie bisher den Re-Import mit `cq.importers.importStep`. Der Report bekommt `roundtrip.pmi = {"written": n, "read_back": m}`; `ok` verlangt `m == n`.
- `Session.export` schreibt zusätzlich `<name>.glb`, `marks.json` und `pmi.json`. `review.md` bekommt `## PMI in the STEP file` (Typ, Wert, Toleranz, Flächen, Beschreibung).

- [ ] **Step 1: Tests schreiben** (Demo-Teil aus den Fixtures):
  - `test_ap242_schema_header` (Dateitext enthält `AP242_MANAGED_MODEL_BASED_3D_ENGINEERING_MIM_LF`)
  - `test_hole_fit_written_as_h7` (Ø16 H7 → `DIMENSIONAL_SIZE` und `LIMITS_AND_FITS('H','hole','7','')`)
  - `test_assumed_thickness_as_semantic_distance` (Review `rv1` → `DIMENSIONAL_LOCATION` 10 mm zwischen z = 0 und z = 10, Beschreibung beginnt mit `ASSUMED:`; `read_pmi` liefert sie zurück)
  - `test_mark_and_thread_colors` (orange markierte Flächen = 2, Flächenname `CHECK rv1`; Teil mit M5-Gewindeloch → Zylinderfläche grün)
  - `test_glb_materials` (GLB gültig: Magic `glTF`, 2 bis 3 Materialien, `metallicFactor` 0.0, `marks.json` nennt `rv1`)
  - `test_reimport_valid_and_volume` (Re-Import des AP242 gültig, |ΔV|/V ≤ 1e-6)
  - `@pytest.mark.bct` `test_read_bct_getriebedeckel_pmi` (`read_pmi` auf `Getriebedeckel (optional PMI)/Getriebedeckel_PMI.stp` → mindestens 15 numerische Maße, eins mit Passung H7)
- [ ] **Step 2:** TEST-Befehl → FAIL.
- [ ] **Step 3:** Implementieren, R&D-Skripte als Vorlage.
- [ ] **Step 4:** TEST-Befehl `tests/` → alle grün. Zusätzlich `python scripts/replay.py --export` für alle schon erzeugten Teile.
- [ ] **Step 5:** Commit `feat(export): AP242 with semantic PMI, review colors, GLB for the viewer`.
- [ ] **Step 6 (Rolle QA, Windows):** die finalen AP242-Dateien durch den NIST STEP File Analyzer 5.51 schicken (`github.com/usnistgov/SFA`, Ordner `Release`; Windows 10 und Excel nötig; erster Start installiert IFCsvr). Status-Tab ohne rote Meldungen → Screenshot für Deck und README (C2).

**Dauer:** ca. 3 h

---

### Task 16: Modellunabhängiger Agent (`d2c.agent`)

**Files:** Create `d2c/agent.py`, `tests/test_agent.py`, `.env.example`

Zweck: Der Server ist schon modellunabhängig. Der Agent zeigt es: Er treibt den Server mit jedem OpenAI-kompatiblen Endpunkt (OpenRouter, Ollama, LM Studio, vLLM) und trennt Lese- und Bauphase.

**Interfaces – Consumes:** Server (Task 8, Task 11 für HTTP). **Produces:**
- `async def run_agent(pdf: str, part: str, *, model: str, base_url: str, api_key: str | None = None, build_model: str | None = None, server: str = "stdio", max_turns: int = 80, on_event: Callable[[dict], None] | None = None) -> dict`
  - `server`: `"stdio"` startet `python -m d2c.server` als Subprozess (gleiche Umgebung). Eine URL `http://…/mcp` verbindet über streamable HTTP. Ein String, der mit `docker ` beginnt, wird als stdio-Befehl gestartet.
  - Systemprompt = `instructions` aus der MCP-Initialisierung plus drei Agent-Regeln: nur über Tools handeln; nach jedem Report die Regeln aus den Instructions anwenden; fertig ist das Teil erst nach `export_step` mit `ok: true`.
  - Tools: `list_tools` → OpenAI-Format `{"type": "function", "function": {"name", "description", "parameters"}}`. `parameters` ist das `inputSchema` mit aufgelösten `$ref`/`$defs` (`inline_refs(schema) -> dict`), denn viele Endpunkte und kleine Modelle verarbeiten `$ref` schlecht.
  - HTTP mit `httpx` an `<base_url>/chat/completions`, `temperature` 0, `tool_choice` `"auto"`. Header `Authorization: Bearer <api_key>`, wenn gesetzt.
  - Tool-Ergebnisse: Text → Tool-Nachricht. Bild → Tool-Nachricht „image attached in the next message“ und danach eine User-Nachricht mit `{"type": "image_url", "image_url": {"url": "data:image/png;base64,…"}}`. In der Bauphase werden Bilder weggelassen.
  - Ungültiges JSON in Tool-Argumenten oder ein `ToolError` geht als Tool-Nachricht mit der Fehlermeldung zurück, die Schleife läuft weiter.
  - Zwei Phasen: Ist `build_model` gesetzt und `submit_spec` erfolgreich, beginnt ein neuer Verlauf mit `build_model`: Systemprompt, die eingereichte Spec als JSON, nur die Bau-Tools (ohne `render_drawing`). 
  - Ende: `export_step` mit `ok: true` → `{"ok": true, "part", "turns", "files"}`. `max_turns` erreicht oder dreimal derselbe fehlschlagende Aufruf → `{"ok": false, "reason"}`.
  - `on_event` bekommt `{"type": "phase"|"tool_call"|"tool_result"|"message"|"done", ...}` (für die Web-Oberfläche und Logs).
- CLI `python -m d2c.agent <pdf> --part NAME [--model M] [--build-model M2] [--base-url URL] [--server S] [--max-turns N] [--events FILE.jsonl]`. Standardwerte aus der Umgebung: `D2C_LLM_BASE_URL`, `D2C_LLM_API_KEY`, `D2C_LLM_MODEL`, `D2C_LLM_BUILD_MODEL`.
- `.env.example` mit zwei kommentierten Varianten: OpenRouter (`https://openrouter.ai/api/v1`) und Ollama lokal (`http://host.docker.internal:11434/v1`). Keine echten Keys.

- [ ] **Step 1: Tests schreiben.** Das LLM ist ein Skript über `httpx.MockTransport` (kein Netz). Der MCP-Server läuft echt per stdio.
  - `test_inline_refs_removes_refs` (Schema von `extrude` enthält danach kein `$ref`, die Profil-Varianten sind erhalten)
  - `test_agent_scripted_run_exports` (Skript: `submit_spec` mit der Demo-Spec, die vier Demo-Ops, `export_step` → Ergebnis `ok`, Ereignisse enthalten `tool_call`, `tool_result`, `done`)
  - `test_image_result_becomes_user_image` (Skript ruft `render_drawing` der Demo-Zeichnung auf → die nächste Anfrage enthält eine User-Nachricht mit `data:image/png;base64,`)
  - `test_bad_json_arguments_reported` (Argumente `"{not json"` → Tool-Nachricht mit Fehlertext, Lauf geht weiter)
  - `test_two_phase_switches_model` (nach erfolgreichem `submit_spec` nutzen die Anfragen `build_model` und enthalten kein `render_drawing`-Tool)
  - `test_stops_after_max_turns`
- [ ] **Step 2:** TEST-Befehl → FAIL.
- [ ] **Step 3:** Implementieren.
- [ ] **Step 4:** TEST-Befehl `tests/` → alle grün.
- [ ] **Step 5:** Commit `feat(agent): model-agnostic agent loop for OpenAI-compatible endpoints`.
- [ ] **Step 6 (Messung, kein Code):** Bauphase mit lokalem Modell über Ollama am Demo-Teil und an einem BCT-Teil mit fertiger Spec; Ergebnis (Modell, Läufe ok/gesamt, Dauer) in `docs/models.md`. Welche Modelle, entscheidet die Machbarkeitsprüfung der lokalen Modelle.

**Dauer:** ca. 3 h

---

### Task 17: Web-Oberfläche und Compose

**Files:** Create `d2c/web/__init__.py`, `d2c/web/app.py`, `d2c/web/static/index.html`, `d2c/web/static/app.js`, `d2c/web/static/style.css`, `d2c/web/static/vendor/` (3D-Viewer, lokal eingebunden, kein CDN), `docker-compose.yml`, `tests/test_web.py`

**Interfaces – Consumes:** Ergebnisordner (Task 7, 10, 12, 15), `run_agent` (Task 16). **Produces:**
- Starlette-App (kommt mit `mcp`, keine neue Abhängigkeit), Start mit `python -m d2c.web [--port 8080]`:
  - `GET /` liefert die Oberfläche.
  - `GET /api/parts` → Liste aus `results_root()`: Name, Titel, `all_ok`, Anzahl Review-Einträge, Zeile aus `EVAL.json` (falls vorhanden), vorhandene Dateien.
  - `GET /api/parts/{name}` → `spec.json`, `review.json`, `report.json`, Eval-Zeile.
  - `GET /files/{name}/{file}` → Dateien aus `results/<name>/`. Nur Namen ohne `/` und `..`, sonst 404.
  - `GET /api/parts/{name}/drawing.png` → erste Seite der Zeichnung über `render` (Task 6), 100 dpi.
  - `POST /api/runs` (Multipart: PDF, Teilname, optional Modell) → speichert unter `<D2C_DATA>/uploads/<teil>.pdf`, startet `run_agent` als Hintergrund-Task, Antwort `{"run_id"}`. Die Agent-Funktion ist injizierbar (Tests).
  - `GET /api/runs/{id}/events` → Server-Sent Events aus `on_event`, endet mit `done`.
- Oberfläche (eine Seite, Vanilla-JS, ohne Build-Schritt): links die Teileliste mit Status; rechts Zeichnung, 3D-Ansicht (GLB, markierte Flächen in der Markierungsfarbe), Reiter Review (Annahmen hervorgehoben), Validierung, Rückverfolgung, Toleranzen, Benchmark, Download-Knöpfe (STEP, GLB, review.md). Oben ein Upload-Feld mit Live-Protokoll der Tool-Aufrufe. Sprache Englisch. Klare, ruhige Gestaltung (Designvorgaben aus `design-taste-frontend` beachten).
- `docker-compose.yml`:
  - Netz `sandbox` mit `internal: true`.
  - Dienst `mcp`: Image `d2c`, `python -m d2c.server --http 0.0.0.0:8765`, nur im Netz `sandbox`, Volumes `./drawings:/data:ro`, `./tables:/tables:ro`, `./results:/app/results`.
  - Dienst `app`: Image `d2c`, `python -m d2c.web --port 8080`, Netze `sandbox` und `default`, Port `8080:8080`, `env_file: .env` (optional), `D2C_MCP_URL=http://mcp:8765/mcp`, Volumes `./results:/app/results`, `./drawings:/data` (Uploads), `extra_hosts: host.docker.internal:host-gateway` (lokales Ollama).

- [ ] **Step 1: Tests schreiben** (Starlette `TestClient`, tmp-Ergebnisordner mit dem exportierten Demo-Teil):
  - `test_parts_list_and_detail`
  - `test_file_download_and_traversal_rejected` (`../spec.json` → 404)
  - `test_run_streams_events` (injizierte Fake-Agent-Funktion sendet drei Ereignisse → SSE liefert sie in Reihenfolge, letztes `done`)
  - `test_upload_saved_under_uploads`
- [ ] **Step 2:** TEST-Befehl → FAIL.
- [ ] **Step 3:** Implementieren. Danach `docker compose up -d`, im Browser `http://localhost:8080` öffnen und mit `claude-in-chrome` prüfen: Teileliste, 3D-Ansicht des Demo-Teils mit markierter Fläche, Downloads. Screenshot in den Report.
- [ ] **Step 4:** TEST-Befehl `tests/` → alle grün.
- [ ] **Step 5:** Commit `feat(web): results browser, live agent runs, compose setup`.

**Dauer:** ca. 3,5 h

---

### Task 18: Teile umsetzen (Benchmark über alle 21 BCT-Teile)

Startet, sobald Task 10 abgenommen ist, und läuft parallel zu den Tasks 11–17 (kein Code, nur `results/`).

Ausführender ist das KI-Modell über die MCP-Tools in der isolierten Sitzung aus Task 9. **Keine** Python-Datei wird für ein einzelnes Teil von Hand geschrieben. Bis zu drei Teile laufen gleichzeitig (eigene Container, eigene Teilnamen).

**Ablauf pro Teil:**
- [ ] **a:** `run_part.sh "<pdf>" <teil>`.
- [ ] **b:** `export_step` liefert `ok: true`.
- [ ] **c:** `docker run --rm --network none -v "$PWD":/app d2c python scripts/eval_refs.py`.
  - MATCH: Teil fertig.
  - Abweichung: Ursache bestimmen (Lesefehler oder echte Unklarheit der Zeichnung).
    - Lesefehler: in einer neuen Sitzung nur sagen „Maß X prüfen“, **ohne** Referenzwert. Dann neu bauen und exportieren.
    - Echte Unklarheit: Es muss ein Review-Eintrag existieren, der sie erklärt.
- [ ] **d:** Menschliche Stichprobe (Rolle QA): `review.md` gegen die Zeichnung lesen. Fehler gehen als „Maß X prüfen“ zurück an eine neue Sitzung.
- [ ] **e:** Zeile in `docs/results.md` (Teil, MATCH/Abweichung, Review-Einträge, Laufzeit). `results/` bleibt unversioniert.

**Reihenfolge:** zuerst der Pflicht-Meilenstein M1 (Sensoraufnahme, Fuss, Welle), dann nach Schwierigkeit:

| # | Teil | Achte auf |
|---|---|---|
| M1 | Sensoraufnahme | Maßstab 2:1. Breite nicht bemaßt → aus Bogenradius = halbe Breite ableiten, `assumed` + Review `missing` mit `mark_near` auf beiden Seitenflächen. Abnahme zusätzlich: Breite im Modell 20, Seitenflächen markiert. Langloch 5/15 mit Breite 5,5; M8 als `tapped` (Ø6.8) |
| M1 | Fuss | Verdeckte Kanten der Seitenansicht: Ø33 von oben bis zur Plattenoberkante (z 19), darunter Ø19 durch. Hohlkehle R9.5 per `edge_finish` |
| M1 | Welle | Nut: `slot` auf `YZ` mit Offset 14 (= 20 − 6), `angle=90`, `center_distance` 80, Breite 12. Einstich Ø28 × 2,5 und Fasen als `revolve`-Punkte. Die Zeichnung bemaßt R2 und 1×45° nur einmal, sie gelten an weiteren Absätzen → `assumed` + Review |
| 1 | Achse | Maßstab 2,5:1. `revolve`: Flansch Ø13 × 1,1 (= 17,1 − 16), Schaft Ø10 h6, Nut Ø9,6 h10, Fase 0,3×45°. M6 als `tapped`, Bohrtiefe 14, Gewindetiefe 9. Bohrspitze 118° als `revolve` mit `mode="cut"` → `assumed` + Review |
| 2 | Schnittmenge | Schriftfeld 1:1, gezeichnet ≈ 0,75 → Review `conflict`. Schnitt zweier Extrusionen (`mode="intersect"`, Task 3b). Langlochlänge 36 = 40 − 2·2 nur abgeleitet → `assumed` + Review |
| 3 | 3-Loch-Hebel | Kontur aus drei Augen R9/R14,5 mit Stegen 18 breit, Winkel 50°, R10-Übergänge per `fillets`. Fasen 1×45° an allen Bohrungen beidseitig |
| 4 | Haken | Platte 20 dick (z ±10), Ring Ø152 30 dick (z ±15) laut Schnitt A-A. Kontur als `path` mit scharfen Ecken plus `fillets` für R35, R35, R16 |
| 5 | Rotation | Titel „Drehteil“ ≠ Ordnername → Review. Maßstab 1:2. Fase 5×45°, Detail B (2:1) mit „1“. 6× Ø12 auf Ø50 als `polar` |
| 6 | Flansch | Maßstab 2:1. Wände (5) tangential zwischen den Naben, Steg 6: Tasche schneiden, dann die Naben wieder ansetzen. Ø2,5 und Ø3,5 mit Tiefe 10; ob Gewinde → Review. Bohrspitzen werden nicht modelliert |
| 7 | Trägerplatte | Sammelangabe R=20 → für jede betroffene Ecke `assumed` + Review (`path` + `fillets`). M5 als `tapped`, Senkungen Ø11/Ø6,6 und Ø10,5/Ø5,5. Wanddicke 6 gegenüber 6,5 in den Schnitten → Review `conflict` |
| 8 | Dreistern | Arme unter 120°, Anzugswinkel 102°, R20 und R1. Gewölbte Oberseite eventuell per `run_script` |
| 9 | Befestigung | Gabel R30/R40, 3× Ø12 unter 45°, schräge Rippe. Ebenen aus der Seitenansicht |
| 10 | Maschinenteil | 12× Ø10 auf Ø76 mit 25,5° Teilung. Detail A (2:1). M10 außen als Ø10 + Review. Sammelangabe R=1 |
| 11 | Getriebedeckel | Maßstab 2:1. `revolve` mit `profile` (R6, R1), Ringnut der Flanschunterseite, 4× Ø6,6 H7 auf Ø55 (`polar`). Abmaße Ø68 +0,2/0, Ø28 0/−0,05, 16 0/−0,1: Vorzeigeteil für Toleranzmitte (X1) und für den PMI-Vergleich mit BCTs `Getriebedeckel_PMI.stp` (C1) |
| 12 | Lagerschaft | Entformungsschräge 2° (`taper`, Task 3b), neutrale Ebene am Fuß → `assumed` + Review. Hülle um Nabe und Augen als `hull`-Profil (Task 3b). R2 per `edge_finish` |
| 13 | Fixierung | Rohr Ø30/Ø24 unter 45° auf `custom`-Ebene, Querbohrung Ø5 entlang freier Achse. „3x Senkbohrung für M4“ ohne Maße → Normwerte annehmen + Review. Sammelnotiz Fasen 0,5×45° → je Kante `assumed` |
| 14 | Splint | Schriftfeld 1:1, gezeichnet 2:1 → Review `conflict`. Halbrunddraht: Schenkel per `extrude` mit `path`, Auge per `revolve` mit `profile`, Hals notfalls `run_script`. Augen-Innen-Ø nicht gedruckt → `assumed` |
| 15 | Grundplatte | Schriftfeld 1:1, gezeichnet 1:2 → Review `conflict`. Formwanne mit 3°-Schrägen, Wand 3, rund 100 Rundungen aus Sammelnotizen. Zuletzt; Teilergebnis mit vollständiger Review-Liste ist akzeptabel |
| 16 | Komplexe Zeichnung 3 | Echte Textebene: zuerst `read_drawing_text`. Hauptansichten 2:1, Einzelheit W 5:1. 12 Abmaße, 6 Passungen mit Ⓔ, 10 Form- und Lagetoleranzen → alle in die Review-Liste. Innengewinde mit `thread_core="minor"` (Konvention dieser Referenzen) |
| 17 | Komplexe Zeichnung 1 und 2 | Nur wenn Zeit bleibt. Mehrseitig, 39 bzw. 15 Durchmesser; Referenz von 2 ist ungültig. Sonst unter Limitations mit ehrlichen Zahlen |

Die Hinweise in dieser Tabelle stammen teils aus dem Referenzvergleich (Zeichnungskatalog). Sie sind nur für QA und Auswertung bestimmt und gehen nie in eine Modell-Sitzung. Allgemein gilt: Kantenrundungen erzeugen Zylinderflächen. Deren Ø zählen im MATCH-Vergleich mit, jede Rundung muss also stimmen.

**Abnahme M1 (Gate G2):** In `review.md` der Sensoraufnahme steht die Breite als Annahme, die Seitenflächen sind im STEP markiert. Drei Zeilen in `results/EVAL.md`, jede mit MATCH oder einer Abweichung, die ein Review-Eintrag erklärt. `python scripts/replay.py` liefert Exit-Code 0.

---

### Task 19: README, Architektur, CI

**Files:** Create/Modify `README.md`, `docs/architecture.md`, `docs/results.md`, `docs/models.md`, `.github/workflows/ci.yml`

- [ ] **Step 1:** `README.md` (Englisch), Reihenfolge:
  1. Ein Satz Zweck, ein Bild (Zeichnung → markiertes 3D-Modell).
  2. **Quickstart** mit genau diesen Befehlen, jeder im frischen Klon geprüft: `docker build -t d2c .` · `docker run --rm d2c pytest -q` · `docker run --rm d2c python -m d2c.demo` · `docker compose up` (Web-Oberfläche, für neue Zeichnungen LLM-Endpunkt in `.env`) · Nutzung als MCP-Server mit beliebigem Client (`docker run -i --rm --network none -v ./drawings:/data:ro -v ./results:/app/results d2c`).
  3. **How it works:** Architekturdiagramm (Mermaid), die Pipeline in fünf Schritten.
  4. **MCP tools:** Tabelle Name, Zweck, wichtigste Parameter.
  5. **Validation and review:** Auszug aus der Review-Liste des Demo-Teils, Erklärung der Markierungsfarbe.
  6. **Results:** Benchmark-Tabelle aus `docs/results.md` (Zahlen, keine BCT-Dateien).
  7. **Requirement coverage:** Matrix R1–R10, M1–M3, C1–C2, X1 → Modul → Test → Beleg.
  8. **Model independence:** getestete Modelle aus `docs/models.md`.
  9. **Security:** Sandbox-Schichten, keine Secrets im Repo.
  10. **Limitations:** ehrlich, mit konkreten Teilen.
  11. **Project layout** und **Running with the BCT sample data** (Ordner `data/`, `drawings/`, `tables/` anlegen).
- [ ] **Step 2:** `docs/architecture.md`: Schichten, Datenfluss, die Kernentscheidungen aus der Spec (Englisch), Sicherheitsmodell.
- [ ] **Step 3:** `.github/workflows/ci.yml`: auf `push` und `pull_request`, `ubuntu-latest`, `docker build -t d2c .`, `docker run --rm d2c pytest -q`, `docker run --rm d2c python -m d2c.demo`.
- [ ] **Step 4:** Frischer Klon in ein tmp-Verzeichnis, dort alle Quickstart-Befehle ausführen, zusätzlich `docker buildx build --platform linux/amd64 -t d2c-amd64 --load .` und `docker run --rm --platform linux/amd64 d2c-amd64 pytest -q`. Alles grün.
- [ ] **Step 5:** Prüfen, dass kein Secret, keine BCT-Datei und kein Hinweis auf Entwicklungswerkzeuge im Baum steht: `git grep -n -i -E 'sk-or-|api_key=|co-authored|generated with'` ist leer, `git ls-files | grep -E '\.(stp|step|prt|jt)$'` ist leer.
- [ ] **Step 6:** Commit `docs: README, architecture, results and CI`.

**Dauer:** ca. 2 h

---

### Task 20: Pitch-Deck und Video (Rolle Pitch, Unterstützung durch Core)

- [ ] **Step 1 (Sa bis 18:00):** Storyline für 5 Minuten: Problem (Altzeichnungen, Nachkonstruktion kostet Stunden) → Lösung in einem Satz → Demo Sensoraufnahme (fehlende Breite wird erkannt, angenommen, im STEP markiert) → Zahlen aus dem Benchmark → Extras (Toleranzmitte, PMI, lokales Modell) → Nutzen für BCT und Kunden (Daten bleiben im Haus, NX-fähiges STEP, Review statt Blindvertrauen) → Ausblick.
- [ ] **Step 2 (Sa bis 22:00):** Deck mit 8–10 Folien als PDF (Bilder aus der Web-Oberfläche, Benchmark-Tabelle, Architektur). Jede Folie verständlich ohne Sprecher, weil die Jury vorab liest.
- [ ] **Step 3 (So bis 09:00):** Backup-Video (60–90 s, Upload bis markiertes STEP, beschleunigt) und Generalprobe mit Stoppuhr, zweimal.
- [ ] **Step 4 (So bis 11:00):** Finales PDF auf der Plattform hochladen (Team-Seite, Bereich Pitch-Deck).

---

### Task 21: Abschluss und Abgabe

- [ ] **Step 1 (So 09:00, Feature-Freeze):** keine neuen Funktionen mehr. Nur noch Fehlerbehebung.
- [ ] **Step 2:** Kompletter Lauf: TEST-Befehl über `tests/`, `scripts/replay.py`, `scripts/eval_refs.py`, Frisch-Klon-Prüfung aus Task 19 Step 4.
- [ ] **Step 3:** `dev` lokal nach `main` mergen (fast-forward), Tag `v1.0`.
- [ ] **Step 4 (nur mit Freigabe des Teams):** `git push origin main --tags`. CI muss grün sein.
- [ ] **Step 5 (spätestens 11:15):** Abgabeformular: Repo-URL, Branch `main`, Tag `v1.0`, volle SHA aus `git rev-parse v1.0^{commit}`, README-Text (Quickstart-Abschnitt).
