# Drawing2CAD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ein lokal laufender MCP-Server (Docker, CadQuery), über den ein beliebiges multimodales KI-Modell technische 2D-Zeichnungen in validierte STEP-Modelle umsetzt. Dazu gibt es eine Review-Liste, und die unklaren Stellen sind im STEP farbig markiert.

**Architecture:** Das Modell ist eine Liste von Operationen. Jede Änderung baut alle Operationen in einem Sandbox-Subprozess neu und gibt einen maschinenlesbaren BuildReport zurück (Solid gültig, Maße gegen Spec, STEP-Roundtrip). `export_step` schreibt das geprüfte STEP nach `results/` und erzeugt `review.md`. Die Zeichnung erreicht das Modell als Bild über das Tool `render_drawing`, die Maße kommen als validierte `PartSpec` zurück.

**Tech Stack:** Python 3.12, cadquery 2.8.0, mcp 2.3.0 (`MCPServer`), pydantic 2, pytest, poppler-utils, Docker (aarch64).

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
| `d2c/server.py` | `MCPServer` mit den Tools als dünne Schicht über `session` |
| `d2c/instructions.md` | Arbeitsanweisung an das KI-Modell (wird als `instructions` mitgegeben) |
| `scripts/eval_refs.py` | Vergleich `results/*/*.step` gegen Referenzen, gibt eine Markdown-Tabelle aus |
| `scripts/replay.py` | Baut alle `results/*/ops.json` neu und prüft sie |
| `run/.mcp.json` | Startet den Server für die Teile-Session per `docker run -i` |
| `tests/` | Je Modul eine Testdatei, `tests/conftest.py`, `tests/fixtures/fuss_spec.json` und `fuss_ops.json` |

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
- `SketchPlane(name: Literal["XY","XZ","YZ"], offset: float = 0.0)` → `cq.Workplane(cq.Plane.named(name))`, um `offset` entlang der Normalen verschoben.
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
  - `RevolveOp(op="revolve", points: list[(r,z)], angle: float=360, mode="add")` – Profil auf `XZ`, Achse = globale Z. Alle `r ≥ 0`, sonst Fehler.
  - `HolesOp(op="holes", plane, positions: list[(u,v)] = [], polar: PolarPattern | None = None, d: float, depth: float | None = None, kind: Literal["plain","cbore","csk","tapped"]="plain", cbore_d, cbore_depth, csk_d, csk_angle: float = 90, thread: str | None = None, flip: bool = False)` – bohrt ab der Ebene in **−Normale** (`flip=True`: +Normale). `depth=None` heißt durchgehend (Bohrlänge = BBox-Diagonale + 1). Bei `kind="tapped"` ist `thread` Pflicht (z. B. „M5“) und der gebohrte Ø kommt aus der Kernloch-Tabelle. `d` muss dann dem Nenndurchmesser des Gewindes entsprechen, sonst Fehler.
  - `PolarPattern(center: (u,v), pitch_d: float, count: int, start_angle: float = 0)` – Positionen bei `start_angle + i*360/count`. Genau eins von beiden ist Pflicht: `positions` nicht leer **oder** `polar` gesetzt. Sonst `ValueError`.
  - `EdgeFinishOp(op="edge_finish", kind: Literal["fillet","chamfer"], size: float, near: list[(x,y,z)], tol: float = 0.5)` – wählt alle Kanten, deren Abstand zu einem `near`-Punkt ≤ `tol` ist. Nahtkanten werden nicht gezählt: Kante `e` ist Naht, wenn `BRep_Tool.IsClosed_s(e.wrapped, f.wrapped)` für eine angrenzende Fläche `f` gilt. 0 Treffer → `BuildError("no edge within tol of near points")`.
  - `ScriptOp(op="script", code: str)` – führt den Code mit `result` (aktuelles `cq.Workplane`), `cq` und `math` aus. Danach muss `result` ein `cq.Workplane` sein.
- `Op = Annotated[Union[ExtrudeOp, RevolveOp, HolesOp, EdgeFinishOp, ScriptOp], Field(discriminator="op")]`
- Jede Operation erbt von `OpBase(BaseModel, extra="forbid")` mit `refs: dict[str, str] = {}`. Ein Eintrag ordnet einen Zahlenparameter der Operation einer `Dimension.id` aus der PartSpec zu, z. B. `{"d": "d3", "profile.w": "d7", "plane.offset": "d2", "positions.1.0": "d9"}`. Schlüssel sind Punkt-Pfade in `model_dump()`, Listenindizes als Zahl. Ein `model_validator` prüft, dass jeder Pfad auf eine Zahl (`int`/`float`, nicht `bool`) zeigt, sonst `ValueError` mit dem Pfad. `build()` ignoriert `refs`. Zweck: Rückverfolgbarkeit jedes Modellwerts auf ein Zeichnungsmaß und automatischer Umbau auf Toleranzmitte (Task 14). Dazu gibt es `get_path(d: dict, path: str)` und `set_path(d: dict, path: str, value: float)` als Modulfunktionen.
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
  - `test_refs_valid_paths` (`ExtrudeOp` mit `refs={"profile.w": "d1", "plane.offset": "d2", "distance": "d3"}` ist gültig; `get_path`/`set_path` lesen und schreiben `profile.w`)
  - `test_refs_bad_path_rejected` (`refs={"profile.q": "d1"}` → Fehler; `refs={"mode": "d1"}` → Fehler, kein Zahlenwert)
- [ ] **Step 2:** TEST-Befehl `tests/test_ops.py` → FAIL (`ModuleNotFoundError: d2c.ops`).
- [ ] **Step 3:** In `d2c/ops.py` implementieren.
  - Jede Operation erzeugt einen eigenen Solid, der per `union` bzw. `cut` mit dem Ergebnis verknüpft wird (`clean=True`).
  - Bohrungen sind Zylinder (plus Senkung oder Kegel), keine `Workplane.hole`-Aufrufe. Grund: `hole` hängt von der aktuellen Fläche ab.
  - Kantenwahl: Kanten aus dem **aktuellen** Solid nehmen (`sel = [e for e in wp.edges().vals() if min(e.distance(cq.Vertex.makeVertex(*p)) for p in near) <= tol]`), dann `wp.newObject(sel).fillet(size)` bzw. `.chamfer(size)`. Kanten aus einer anderen Instanz führen zu `Standard_Failure` (verifiziert).
- [ ] **Step 4:** TEST-Befehl → `22 passed`.
- [ ] **Step 5:** Commit `feat(ops): operation models and CadQuery build`.

**Dauer:** ca. 5 h

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
- `replay.py`: baut jedes `<results_root()>/*/ops.json` mit `expected` aus `spec.json` neu → eine Zeile je Teil mit `ok`. Exit-Code 1, wenn ein Teil nicht `ok` ist.

- [ ] **Step 1: Tests schreiben:**
  - Alle Referenzen erzeugen die Tests selbst in tmp (CadQuery-Box mit Bohrung als STEP), keine BCT-Daten.
  - `test_eval_identical_is_match` (Referenz gegen eine Kopie ihrer selbst)
  - `test_eval_detects_missing_diameter` (Ergebnis ohne Bohrung → Ø fehlend nennt den Durchmesser)
  - `test_eval_resolves_folder_with_spaces` (Ordner `Komplexe Zeichnung 3` mit `1 763 1487 0.stp` und Köder `1 763 1487 0_PMI.stp`; `spec.drawing = "Komplexe Zeichnung 3/1 763 1487 0.pdf"` → nimmt die Datei ohne `_PMI`)
  - `test_replay_fails_on_bad_part`
  - `test_eval_bct_fuss_reference` mit `@pytest.mark.bct` (`metrics` der Referenz `Fuss/Fuss.stp`: Volumen 317209.8 ±0.5)
- [ ] **Step 2:** TEST-Befehl → FAIL.
- [ ] **Step 3:** Implementieren.
- [ ] **Step 4:** TEST-Befehl → `5 passed`.
- [ ] **Step 5:** Commit `feat(scripts): reference evaluation and replay`.

**Dauer:** ca. 1 h

---

### Task 11: Teile umsetzen – Pflicht-Meilenstein M1 (Sensoraufnahme, Fuss, Welle)

Sensoraufnahme kommt zuerst. Sie ist einfach und enthält genau den Prüffall, den BCT für M3 und R10 vorbereitet hat: Die Breite fehlt absichtlich.

Ausführender ist das KI-Modell über die MCP-Tools, nach `d2c/instructions.md`. **Keine** Python-Datei wird für ein einzelnes Teil von Hand geschrieben.

**Ablauf pro Teil** (gilt auch für Task 12):
- [ ] **a:** Isolierte Session wie in Task 9 Step 3 starten. Der Auftrag lautet: „Setze `<Pfad der PDF>` nach den Server-Instructions um.“
- [ ] **b:** `export_step` liefert `ok: true`.
- [ ] **c:** Im Repo: `docker run --rm --network none -v "$PWD":/app -e D2C_DATA=/app/data d2c python scripts/eval_refs.py`.
  - Zeile MATCH: Teil fertig.
  - Abweichung: Ursache bestimmen (Lesefehler oder echte Unklarheit in der Zeichnung).
    - Lesefehler: in derselben isolierten Session nur sagen „Maß X prüfen“, **ohne** Referenzwert. Dann neu bauen und exportieren.
    - Echte Unklarheit: Es muss ein Review-Eintrag existieren, der sie erklärt.
- [ ] **d:** Commit `feat(parts): <Teil> STEP with review list` mit `results/<Teil>/`.

**Bekannte Stolperstellen**, aus der Zeichnung abgeleitet, nicht aus der Referenz:

| Teil | Achte auf |
|---|---|
| Fuss | Verdeckte Kanten der Seitenansicht: Ø33 von oben bis zur Plattenoberkante (z 19), darunter Ø19 durch. Hohlkehle R9.5 per `edge_finish` |
| Welle | Nut: `slot` auf `YZ` mit Offset 14 (= 20 − 6), `angle=90`, `center_distance` 80, Breite 12. Einstich Ø28 × 2,5 und Fasen als `revolve`-Punkte. Die Zeichnung bemaßt R2 und 1×45° nur einmal, sie gelten an weiteren Absätzen → `assumed` + Review |
| Sensoraufnahme | Maßstab 2:1. Breite nicht bemaßt → aus Bogenradius = halbe Breite ableiten, `assumed` + Review `missing` mit `mark_near` auf beiden Seitenflächen. Abnahme zusätzlich: Breite im Modell 20, Seitenflächen orange markiert. Langloch 5/15 mit Breite 5,5; M8 als `tapped` (Ø6.8) |

Allgemein gilt: Kantenrundungen erzeugen Zylinderflächen. Deren Ø zählen im MATCH-Vergleich mit, jede Rundung muss also stimmen.

**Abnahme M1:** In `review.md` der Sensoraufnahme steht die Breite als Annahme, die Seitenflächen sind im STEP markiert. Außerdem 3 Zeilen in `results/EVAL.md`. Jede Zeile hat MATCH, oder jede Abweichung ist durch einen Review-Eintrag erklärt und im README-Abschnitt „Grenzen“ genannt. `python scripts/replay.py` liefert Exit-Code 0.

**Dauer:** ca. 3–4 h

---

### Task 12: Weitere Teile (Reihenfolge nach Schwierigkeit)

Gleicher Ablauf a–d wie in Task 11.

Reihenfolge nach Flächenzahl der Referenz, das ist ein grobes Maß für den Aufwand. Hinweise stehen nur bei Zeichnungen, die bereits gesichtet sind. Die übrigen werden beim Umsetzen in Schritt a gesichtet.

| # | Teil | Achte auf |
|---|---|---|
| 0a | Achse | – |
| 0b | Fixierung | – |
| 0c | Splint | – |
| 0d | 3-Loch-Hebel | Kontur aus drei Augen R9/R14,5 mit Stegen 18 breit, Winkel 50°, R10-Übergänge per `fillets`. Fasen 1×45° an allen Bohrungen beidseitig |
| 0e | Haken | Platte 20 dick (z ±10), Ring Ø152 30 dick (z ±15) laut Schnitt A-A. Kontur als `path` mit scharfen Ecken plus `fillets` für R35, R35, R16 |
| 1 | Rotation | Titel „Drehteil“ ≠ Ordnername → Review. Maßstab 1:2. Fase 5×45°, Detail B (2:1) mit „1“. 6× Ø12 auf Ø50 als `polar` |
| 2 | Flansch | Maßstab 2:1. Wände (5) tangential zwischen den Naben, Steg 6: Tasche schneiden, dann die Naben wieder ansetzen. Ø2,5 und Ø3,5 mit Tiefe 10; ob Gewinde → Review. Die Bohrspitzen werden nicht modelliert, sie ändern MATCH nicht |
| 3 | Trägerplatte | Sammelangabe R=20 → für jede betroffene Ecke `assumed` + Review (`path` + `fillets`). M5 als `tapped`, Senkungen Ø11/Ø6,6 und Ø10,5/Ø5,5. Wanddicke 6 gegenüber 6,5 in den Schnitten → Review `conflict` |
| 4 | Dreistern | Arme unter 120°, Anzugswinkel 102°, R20 und R1. Gewölbte Oberseite eventuell per `run_script` |
| 5 | Befestigung | Gabel R30/R40, 3× Ø12 unter 45°, schräge Rippe. Ebenen aus der Seitenansicht |
| 6 | Maschinenteil | 12× Ø10 auf Ø76 mit 25,5° Teilung. Detail A (2:1). M10 außen als Ø10 + Review. Sammelangabe R=1 |
| 7 | Lagerschaft, Getriebedeckel, Schnittmenge | – |
| 8 | Grundplatte | 188 Flächen in der Referenz, viele Bohrungen → Lochmuster nutzen |
| 9 | Komplexe Zeichnung 3, 1, 2 | Industriezeichnungen mit Form- und Lagetoleranzen, Passungen, Einzelheiten im Maßstab 5:1, mehreren Seiten. Symbole sind teils nicht lesbar → Review. Die Referenz von Nr. 2 ist ungültig. Das sind Bonus-Teile |

**Abnahme:** Jedes umgesetzte Teil erfüllt die Kriterien aus Task 11. Teile, die nicht fertig werden, stehen mit Grund im README-Abschnitt „Grenzen“.

**Dauer:** ca. 0,5–1 h für die einfachen Teile (0a–0e), 1–2 h für die übrigen, die komplexen Zeichnungen offen

---

### Task 13: Externe Prüfung (M2) und Abgabe

**Files:** Create `README.md`, `scripts/freecad_check.py`

- [ ] **Step 1:** `brew install --cask freecad`.
- [ ] **Step 2:** `scripts/freecad_check.py` schreiben. Es lädt jedes `results/*/*.step` mit `Part.read`, prüft `isValid()` und gibt eine Zeile pro Teil aus. Aufruf: `/Applications/FreeCAD.app/Contents/Resources/bin/freecadcmd scripts/freecad_check.py`. Erwartet: jede Zeile `OK`.
- [ ] **Step 3:** `README.md`: Zweck, Architekturskizze (aus der Spec), Setup (`docker build`, `.mcp.json`), Tool-Liste, Ergebnistabelle (`results/EVAL.md` eingebunden), Grenzen.
- [ ] **Step 4:** Modellunabhängigkeit belegen (R9): Fuss mit einem zweiten MCP-Client und einem anderen Modell umsetzen, z. B. Codex CLI mit demselben `docker run`-Befehl, nach `D2C_RESULTS=/app/results-alt`. Ignoriert der Client die Server-`instructions`, wird `d2c/instructions.md` als Prompt mitgegeben. Erwartet: `export_step` liefert `ok: true`. Ergebnis kommt ins README.
- [ ] **Step 5:** Abschlusslauf: kompletter TEST-Befehl über `tests/`, `scripts/replay.py`, `scripts/eval_refs.py`. Alles grün.
- [ ] **Step 6:** Commit `docs: README, external STEP check, second-model run`.
- [ ] **Step 7:** Die STEP-Dateien am BCT-Stand in NX öffnen lassen (M2 „öffnet fehlerfrei in NX“).

**Dauer:** ca. 2 h

---

### Task 14: Toleranzen (Erweiterung X1)

Erst beginnen, wenn M1–M3 und R10 erfüllt sind.

**Files:** Create `d2c/tolerances.py`, `tests/test_tolerances.py`; Modify `d2c/spec.py`, `d2c/checks.py`, `d2c/review.py`, `d2c/instructions.md`, `run/.mcp.json` (zusätzlich `-v /Users/abu/hackathon/tables:/tables:ro`)

**Interfaces – Produces:**
- `Dimension` erhält `tol_upper: float | None = None`, `tol_lower: float | None = None`, `fit: str | None = None` (Pattern `^[A-Za-z]{1,2}\d{1,2}$`, z. B. `H10`, `h10`).
- `PartSpec` erhält `general_tolerance: Literal["ISO 2768-f","ISO 2768-m","ISO 2768-c","ISO 2768-v"] | None = None` und `nominal_mode: Literal["nominal","mid"] = "nominal"`.
- `limits(dim: Dimension, general: str | None) -> tuple[float, float, str]` → (unteres Abmaß, oberes Abmaß, Quelle `"explicit"|"fit"|"general"|"none"`).
  - Explizit vor Passung vor Allgemeintoleranz.
  - Tabellen aus `D2C_TABLES` (Standard `/tables`): `bct_isolim.xml` (Knoten = Toleranzklasse) und `bct_toltabs.xml` (`toltable entry="DIN ISO 2768 (medium/mittel)"` usw.). Bereichsgrenzen: Attribute `over`/`from` und `to`/`up_to` werden beide gelesen. Der Wert gehört zu dem Bereich mit over < Nennmaß ≤ to. Für `from` gilt ≤ als untere Grenze.
- `mid(dim, general) -> float` = Nennmaß + (oben + unten)/2.
- `submit_spec` gibt zusätzlich für jedes tolerierte Maß `{id, nominal, lower, upper, mid, source}` zurück. Instruktion: Bei `nominal_mode="mid"` nutzen die Ops die `mid`-Werte.
- Maßprüfung: `ExpectedHole.dim_ids` mit Toleranz → `ok`, wenn d_ist im Bereich [d + unten, d + oben] liegt (bei `mid`) bzw. d_ist = Nennmaß ± 0.01 ist (bei `nominal`). Der Report zeigt je Maß `in_tolerance`.
- `review.md`: Tabelle „Toleranzen“ (Maß, Nennmaß, unteres/oberes Abmaß, Mitte, Quelle, eingehalten).

- [ ] **Step 1: Tests schreiben:**
  - `test_fit_h10_6` (6 h10 → (−0.048, 0.0, "fit"))
  - `test_fit_H10_4` (4 H10 → (0.0, +0.048, "fit"))
  - `test_iso2768_m_25` (25 mm, mittel → ±0.2)
  - `test_range_boundary_inclusive` (6.0 liegt im Bereich 3–6)
  - `test_explicit_beats_fit`
  - `test_mid_asymmetric` („31 -0,1“ → 30.95)
  - `test_hole_in_tolerance_mid_mode`
- [ ] **Step 2:** TEST-Befehl → FAIL.
- [ ] **Step 3:** Implementieren (`xml.etree.ElementTree`, Kodierung ISO-8859-1 aus dem XML-Kopf).
- [ ] **Step 4:** TEST-Befehl über `tests/` → alle grün.
- [ ] **Step 5:** Ein Teil mit Toleranzen erneut umsetzen, mit `nominal_mode="mid"`: Komplexe Zeichnung 3, falls umgesetzt, sonst ein einfaches Teil mit Passung. Erwartet: Die Toleranztabelle in `review.md` ist vollständig.
- [ ] **Step 6:** Commit `feat(tolerances): ISO 286 fits, ISO 2768 general tolerances, mid-tolerance mode`.

**Dauer:** ca. 3 h

---

## Danach (eigener Plan, erst wenn Task 14 steht)

- **Geometrie aus Vektoren messen:** Die PDFs sind Vektorzeichnungen, Bögen liegen aber als ungeordnete Liniensegmente vor. Ein schneller Versuch, daraus Kreise zu rekonstruieren, hat nicht funktioniert. Funktioniert es später, kann ein Tool angenommene Maße exakt nachmessen.
- **C1/C2 AP242 + PMI:** Export über OCP-XDE (`STEPCAFControl_Writer`, `Interface_Static.SetCVal("write.step.schema", "AP242DIS")`, `XCAFDoc_DimTolTool`). Prüfung mit dem NIST SFA unter Windows.

## Zeitbudget

| Block | Tasks | Stunden |
|---|---|---|
| Infrastruktur | 1–10 | ca. 15,5 |
| Pflicht-Meilenstein M1 | 11 | 3–4 |
| Weitere Teile | 12 | 10–20 (je nachdem, wie viele) |
| Abgabe | 13 | 2 |
| Toleranzen (X1) | 14 | 3 |
