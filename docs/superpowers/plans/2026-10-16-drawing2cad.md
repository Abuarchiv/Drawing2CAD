# Drawing2CAD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ein lokal laufender MCP-Server (Docker, CadQuery), über den ein beliebiges multimodales KI-Modell technische 2D-Zeichnungen in validierte STEP-Modelle mit Review-Liste umsetzt.

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
- Zwei Datenordner, beide nicht versioniert:
  - `data/` ist die vollständige Kopie mit Referenz-STEPs. Nur Tests und `scripts/eval_refs.py` nutzen sie.
  - `drawings/` enthält nur die `*_dwg.pdf`. Nur dieser Ordner wird für den MCP-Server als `/data` eingehängt (read-only).
- Ergebnisse liegen unter `/app/results`. `D2C_DATA` und `D2C_RESULTS` überschreiben die Pfade, beide werden bei jedem Aufruf gelesen.
- Sandbox-Grenzwerte:
  - `D2C_TIMEOUT` (Standard 60 s) ist die Wanduhr-Grenze über `subprocess.run(timeout=…)`.
  - RLIMIT_AS 4 GiB, RLIMIT_FSIZE 200 MiB.
  - RLIMIT_CPU = 4·⌈Timeout⌉ + 10 s, nur als Rückfallgrenze. Grund: `import cadquery` allein braucht ca. 2 s CPU in 1,2 s Wanduhrzeit (12 Threads). Ein CPU-Limit gleich dem Timeout würde den Worker vorher per SIGKILL beenden (gemessen).
- Toleranzen: linear 0.01 mm, Achsparallelität |cos| ≥ 0.9999, Roundtrip |ΔV|/V ≤ 1e-6.
- Review-Pflicht: Jedes Maß mit `assumed=true` oder `confidence < 0.8` steht in mindestens einem `ReviewItem.refs`.
- Kernloch-Tabelle für `kind="tapped"` (Innengewinde → Kernloch-Ø): M2 1.6, M2.5 2.05, M3 2.5, M4 3.3, M5 4.2, M6 5.0, M8 6.8, M10 8.5, M12 10.2.
- **TEST-Befehl** (gilt für jeden Task): `docker run --rm --network none -v "$PWD":/app d2c pytest -q <pfad>`
- Das Modell darf weder die Referenz-STEPs noch die Spec-Tabelle mit Referenzwerten erreichen. Dafür sorgen der Mount nur von `drawings/` und eine Session außerhalb des Repos ohne Datei-Tools (Task 9).

## Review Focus

1. **Komma als Dezimaltrennzeichen** („76,2“ als 762 gelesen): `Dimension.text` und `value` müssen übereinstimmen. Test `test_text_value_mismatch_rejected` in Task 2.
2. **Rundung oder Fase trifft keine oder ungewollte Kanten**: Keine Kante gewählt ist ein Fehler, die Anzahl gewählter Kanten steht im Report. Tests `test_fillet_no_edge_errors` und `test_fillet_reports_edge_count` in Task 3.
3. **Feature schwebt neben dem Grundkörper** (2 Solids): Der Report meldet `solids=2, ok=false`. Test `test_two_solids_not_ok` in Task 4.
4. **Endlosschleife im Fallback-Skript**: Der Prozess wird nach dem Timeout beendet, die Operation wird nicht angehängt. Tests `test_timeout_kills` (Task 5) und `test_failed_build_not_appended` (Task 7).
5. **Pfad außerhalb von `/data` oder Umlaut im Teilnamen** (`Trägerplatte`): Der Pfad wird abgewiesen, der Umlaut funktioniert. Tests `test_render_rejects_outside_data` (Task 6) und `test_umlaut_part_name` (Task 7).

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
  - `rsync -a /Users/abu/Downloads/Drawing2CAD/ data/`
  - `rsync -a --include '*/' --include '*_dwg.pdf' --exclude '*' /Users/abu/Downloads/Drawing2CAD/ drawings/`
- [ ] **Step 2:** `.gitignore`: `data/`, `drawings/`, `__pycache__/`, `*.egg-info/`, `.pytest_cache/`. `.dockerignore`: `data/`, `drawings/`, `results/`, `.git/`.
- [ ] **Step 3:** `pyproject.toml`:
  - Projekt `d2c`, `requires-python = ">=3.12,<3.13"`
  - Abhängigkeiten `cadquery==2.8.0`, `mcp==2.3.0`
  - Extra `dev = ["pytest==8.*"]`
  - Paketdaten `d2c/instructions.md`
- [ ] **Step 4:** `Dockerfile`:
  - apt-Pakete aus den Global Constraints installieren
  - `COPY . /app`, dann `pip install --no-cache-dir -e /app[dev]`
  - `CMD ["python", "-m", "d2c.server"]`
- [ ] **Step 5:** `tests/conftest.py` mit autouse-Fixture anlegen: `monkeypatch.setenv("D2C_RESULTS", str(tmp_path))` und `monkeypatch.setenv("D2C_DATA", "/app/data")`. So schreibt kein Test in echte Ergebnisordner.
- [ ] **Step 6:** Test schreiben: `tests/test_smoke.py::test_imports` importiert `cadquery`, `MCPServer`, `Image` und prüft, dass `cadquery.__version__ == "2.8.0"`. `test_pdftoppm_available` prüft, dass `shutil.which("pdftoppm")` nicht None ist.
- [ ] **Step 7:** `docker build -t d2c .`, dann den TEST-Befehl mit `tests/test_smoke.py` ausführen. Erwartet: `2 passed`.
- [ ] **Step 8:** Commit `chore: scaffold d2c package and docker image`.

**Dauer:** ca. 30 min

---

### Task 2: PartSpec – Zwischenbeschreibung der Zeichnung

**Files:** Create `d2c/spec.py`, `tests/test_spec.py`

**Interfaces – Produces** (alle `pydantic.BaseModel`, `extra="forbid"`):
- `Source(view: str, cell: str)` – `cell` muss auf `^[A-F][1-8]$` passen (Rasterfeld des A3-Rahmens).
- `Dimension(id: str, kind: Literal["length","diameter","radius","angle","chamfer","thread","count"], value: float, text: str, source: Source | None, confidence: float (0..1), assumed: bool = False, assumption_basis: str | None = None)`
- `View(id: str, kind: Literal["front","top","side","section","detail","iso"], scale: str, note: str = "")`
- `Feature(id: str, type: Literal["base","boss","pocket","hole","slot","fillet","chamfer","thread","revolve","other"], dim_ids: list[str], note: str = "")`
- `ExpectedHole(d: float, at: tuple[float,float,float], axis: tuple[float,float,float], dim_ids: list[str])`
- `Expected(bbox: tuple[float,float,float], holes: list[ExpectedHole] = [])` – `bbox` ist Pflicht (xlen, ylen, zlen in Modellkoordinaten)
- `ReviewItem(id: str, refs: list[str], issue: Literal["missing","ambiguous","low_confidence","conflict","convention"], assumption: str, reason: str)`
- `PartSpec(name: str (Pattern ^[\w-]+$), drawing: str, title: str, scale: str, units: Literal["mm"] = "mm", views: list[View], dimensions: list[Dimension], features: list[Feature], expected: Expected, review: list[ReviewItem])`
- `PartSpec`-Validator. Bei jeder Verletzung wirft er `ValueError` und nennt die betroffene id:
  - (a) ids über Dimensionen, Features, Views und Review-Einträge hinweg eindeutig
  - (b) jede `ref` und jede `dim_id` existiert, jedes `source.view` verweist auf eine vorhandene View-id
  - (c) jedes Maß mit `assumed` oder `confidence < 0.8` steht in einem `ReviewItem.refs`
  - (d) `assumed=true` erfordert eine nicht-leere `assumption_basis`
  - (e) `reason` und `assumption` sind nicht leer
  - (f) Text-Wert-Abgleich: `nums = re.findall(r"\d+(?:[.,]\d+)?", text)`. Ist `len(nums) == 1` oder `kind == "chamfer"` (z. B. „5x45°“), muss `float(nums[0].replace(",", "."))` gleich `value` sein (±1e-9).
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
- [ ] **Step 2:** TEST-Befehl `tests/test_spec.py` → FAIL (`ModuleNotFoundError: d2c.spec`).
- [ ] **Step 3:** Modelle und Validator wie oben in `d2c/spec.py` implementieren.
- [ ] **Step 4:** TEST-Befehl → `10 passed`.
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
- `class BuildError(Exception)`
- `build(ops: list[Op]) -> tuple[cq.Workplane, list[dict]]` – gibt Modell und `notes` zurück, z. B. `{"op_index": i, "edges_selected": n}` oder `{"op_index": i, "drilled_d": 4.2}`. Die erste Operation muss `mode="add"` haben. `cut` vor dem ersten `add` → `BuildError`.

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
- [ ] **Step 2:** TEST-Befehl `tests/test_ops.py` → FAIL (`ModuleNotFoundError: d2c.ops`).
- [ ] **Step 3:** In `d2c/ops.py` implementieren.
  - Jede Operation erzeugt einen eigenen Solid, der per `union` bzw. `cut` mit dem Ergebnis verknüpft wird (`clean=True`).
  - Bohrungen sind Zylinder (plus Senkung oder Kegel), keine `Workplane.hole`-Aufrufe. Grund: `hole` hängt von der aktuellen Fläche ab.
  - Kantenwahl: Kanten aus dem **aktuellen** Solid nehmen (`sel = [e for e in wp.edges().vals() if min(e.distance(cq.Vertex.makeVertex(*p)) for p in near) <= tol]`), dann `wp.newObject(sel).fillet(size)` bzw. `.chamfer(size)`. Kanten aus einer anderen Instanz führen zu `Standard_Failure` (verifiziert).
- [ ] **Step 4:** TEST-Befehl → `20 passed`.
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
- `step_roundtrip(wp, path: str) -> dict` → schreibt mit `cq.exporters.export(wp.val(), path, "STEP")`, liest mit `cq.importers.importStep` → `{"path", "reimport_valid", "solids", "volume_rel_diff", "ok"}`.
- `metrics(shape) -> dict` → `{"volume", "bbox_sorted": [a ≤ b ≤ c], "cyl_diameters": sorted unique, auf 0.01 gerundet}` (genutzt von `eval_refs`).

- [ ] **Step 1: Tests schreiben:**
  - `test_box_solid_ok`
  - `test_two_solids_not_ok` (zwei getrennte Boxen per `add` → `solids == 2`, `ok` falsch)
  - `test_bbox_check_pass_and_fail`
  - `test_hole_found_by_diameter_and_position`
  - `test_hole_wrong_position_fails` (um 0.5 mm versetzt)
  - `test_hole_wrong_diameter_fails`
  - `test_roundtrip_ok` (tmp_path)
  - `test_metrics_cyl_diameters` (Box mit Ø5- und Ø8-Bohrung → `[5.0, 8.0]`)
- [ ] **Step 2:** TEST-Befehl `tests/test_checks.py` → FAIL.
- [ ] **Step 3:** Implementieren.
- [ ] **Step 4:** TEST-Befehl → `8 passed`.
- [ ] **Step 5:** Commit `feat(checks): solid, dimension and STEP roundtrip validation`.

**Dauer:** ca. 2 h

---

### Task 5: Worker und Sandbox (R5)

**Files:** Create `d2c/worker.py`, `d2c/sandbox.py`, `tests/test_sandbox.py`

**Interfaces – Consumes:** `build`, `BuildError` (Task 3), Check-Funktionen (Task 4). **Produces:**
- Worker-Protokoll: stdin `{"ops": [...], "expected": {...} | null, "export_path": str | null}` → stdout genau eine JSON-Zeile:
  - Jeder Report hat immer die Schlüssel `ok, error, solid, dims, notes, roundtrip`. Bei Fehler gilt `error = "<Typ>: <Meldung>"`, die übrigen Felder sind `null` bzw. `[]`.
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

**Files:** Create `d2c/drawing.py`, `tests/test_drawing.py`

**Interfaces – Produces:**
- `data_root() -> Path` liest `D2C_DATA` (Standard `/data`) bei **jedem Aufruf**, damit `monkeypatch.setenv` in Tests wirkt
- `resolve_drawing(pdf: str) -> Path`:
  - relativ zu `data_root()` auflösen
  - nach `resolve()` muss der Pfad unter `data_root()` liegen und auf `.pdf` enden, sonst `ValueError`
  - bei fehlender Datei nennt die Meldung die vorhandenen `*_dwg.pdf`
- `render(pdf: str, dpi: int = 100, crop: tuple[float,float,float,float] | None = None) -> bytes` (PNG):
  - Seitengröße aus `pdfinfo`, `crop` in Seitenbruchteilen (x0, y0, x1, y1), 0 ≤ x0 < x1 ≤ 1
  - effektive dpi = `min(dpi, 400, floor(2000·72 / längste Ausschnittkante in pt))`, damit die längste Bildseite höchstens 2000 px hat
  - Aufruf: `pdftoppm -png -singlefile -r <dpi> [-x -y -W -H] <pdf> <tmp>`

- [ ] **Step 1: Tests schreiben.** `D2C_DATA` = `/app/data` kommt aus `tests/conftest.py`.
  - `test_render_full_page_size` (dpi 100 → PNG-Breite 1654 ±1, aus dem IHDR-Header gelesen)
  - `test_render_crop_size`
  - `test_render_caps_long_side_2000`
  - `test_render_rejects_outside_data` (`../../etc/passwd`)
  - `test_missing_lists_available`
- [ ] **Step 2:** TEST-Befehl → FAIL.
- [ ] **Step 3:** Implementieren (nur Standardbibliothek und `subprocess`, kein Pillow).
- [ ] **Step 4:** TEST-Befehl → `5 passed`.
- [ ] **Step 5:** Commit `feat(drawing): render drawing pages and crops via pdftoppm`.

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
    - baut `ops + [op]` per `run_worker` mit `expected`
    - bei `error` (Build-Fehler oder Timeout) wird die Op **nicht** angehängt
    - sonst wird sie angehängt (auch bei `ok=false`), `ops.json` wird geschrieben
    - Rückgabe: Report mit `op_index`
  - `edit_op(part, index, op) -> dict`, `delete_op(part, index) -> dict` – gleiche Regeln: Der Zustand ändert sich nur, wenn der Build ohne `error` durchläuft.
  - `move_op(part, index, new_index) -> dict` – gleiche Regel. Wird gebraucht, wenn eine Rundung erst vor späteren Schnitten gültig ist.
  - Ist ein Teil nicht im Speicher, aber `results/<name>/spec.json` vorhanden, lädt die Session `spec.json` und `ops.json` nach. So überleben Ops einen Server-Neustart.
  - `state(part) -> dict` → `{"spec_summary", "ops", "last_report"}`
  - `export(part) -> dict`:
    - baut mit `export_path = results/<name>/<name>.step`
    - verweigert den Export, wenn `ok=false`: Rückgabe `{"ok": false, "error": "validation failed", "report": ...}`, nichts wird geschrieben bzw. eine halb geschriebene Datei wird gelöscht
    - schreibt `report.json` und `review.md`
    - Erfolg: `{"ok": true, "files": {"step", "report", "review", "ops", "spec"}, "report": ...}`
- Unbekanntes Teil (weder im Speicher noch auf der Platte) → `KeyError("unknown part '<name>'; call submit_spec first")`.
- `review.render(spec: PartSpec, report: dict) -> str` – Markdown mit:
  - Kopf (Titel, Zeichnung, Maßstab)
  - Tabelle „Annahmen und Unklarheiten“ (id, Maß/Feature, Problem, Annahme, Begründung, Quelle)
  - Tabelle „Werte ohne Maßbezug“: Größenparameter der Ops (`d w h distance size corner_radius width center_distance depth pitch_d cbore_d cbore_depth csk_d` sowie jedes `r` in `revolve.points`), die keinem `Dimension.value` entsprechen (±0.01). Abgeleitete Werte wie 57.2 = 76.2 − 19 stehen hier absichtlich, damit ein Prüfer sie sieht.
  - Tabelle „Validierung“ (Prüfung, Soll, Ist, ok)
  - Ergebniszeile `Alle Prüfungen bestanden: ja/nein`

- [ ] **Step 1: Tests schreiben** (`D2C_RESULTS` kommt aus `conftest.py`):
  - `test_apply_appends_on_success`
  - `test_failed_build_not_appended` (cut als erste Op)
  - `test_invalid_geometry_appended_but_not_ok` (zwei getrennte Bodies)
  - `test_edit_delete_move_op`
  - `test_export_writes_files` (`<name>.step`, `report.json`, `review.md`, `ops.json`, `spec.json`)
  - `test_export_refuses_when_not_ok` (keine `.step`-Datei vorhanden)
  - `test_review_lists_every_assumed_dimension`
  - `test_umlaut_part_name` (`Trägerplatte` → Dateien existieren)
  - `test_unknown_part_error`
  - `test_review_lists_unreferenced_op_values`
  - `test_reload_from_disk` (neue `Session`-Instanz findet Spec und Ops)
- [ ] **Step 2:** TEST-Befehl → FAIL.
- [ ] **Step 3:** Implementieren.
- [ ] **Step 4:** TEST-Befehl → `11 passed`.
- [ ] **Step 5:** Commit `feat(session): op-list sessions, persistence and review list`.

**Dauer:** ca. 1,5 h

---

### Task 8: MCP-Server und Tool-Beschreibungen

**Files:** Create `d2c/server.py`, `d2c/instructions.md`, `tests/test_server.py`, `tests/fixtures/fuss_spec.json`, `tests/fixtures/fuss_ops.json`

**Interfaces – Consumes:** `Session` (Task 7), `render` (Task 6), Modelle aus Task 2 und 3. **Produces:** `server = MCPServer("drawing2cad", instructions=<instructions.md>)` mit genau diesen 12 Tools. Jeder Docstring enthält einen Satz zum Zweck, die Einheiten, die Konvention für Ebene und Richtung und ein Minimalbeispiel.

| Tool | Signatur | Rückgabe |
|---|---|---|
| `render_drawing` | `(pdf: str, dpi: int = 100, crop: list[float] \| None = None)` | `Image` (png) |
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

`d2c/instructions.md` legt den Ablauf fest, nummeriert:
1. Ganzseite mit 100 dpi rendern. Ansichten, Maßstab und Sammelangaben bestimmen.
2. Jede Ansicht als Ausschnitt mit 300 dpi rendern.
3. Jede Maßzahl mit `text` wie gedruckt, `source.cell` und `confidence` erfassen. Was in keiner Ansicht bemaßt ist, mit `assumed=true` und `assumption_basis` erfassen.
4. `expected` füllen: Gesamt-BBox in Modellkoordinaten, jede Bohrung mit Position.
5. `submit_spec`.
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
  - `test_render_returns_png` (ImageContent mit `mime_type == "image/png"`)
  - `test_bad_args_tool_error` (`ToolError`)
  - `test_unknown_part_message` (`get_state(part="nope")` → `ToolError`, Meldung enthält `call submit_spec first`)
  - `test_fuss_end_to_end`: Pipeline-Fixture, **nicht** das finale Teil. `tests/fixtures/fuss_spec.json` und `fuss_ops.json`. Die Ops enthalten Platte 115×115×19 mit R22 (XY), Zylinder Ø57 von z 19 bis 76.2, Bohrung Ø19 durchgehend in der Mitte, 4× Ø19 auf 71×71. Die Spec setzt `expected.bbox = (115, 115, 76.2)` und 5 `ExpectedHole`s. Abbildung `op` → Tool: `extrude`→`extrude`, `revolve`→`revolve`, `holes`→`add_holes`, `edge_finish`→`edge_finish`, `script`→`run_script`. Ablauf über die Tools: `submit_spec`, alle Ops, `export_step` → `ok == True`, `.step` existiert, `review.md` enthält „Alle Prüfungen bestanden: ja“.
- [ ] **Step 2:** TEST-Befehl → FAIL.
- [ ] **Step 3:** Implementieren.
- [ ] **Step 4:** TEST-Befehl `tests/` (komplett) → alle grün.
- [ ] **Step 5:** Commit `feat(server): MCP tools and model instructions`.

**Dauer:** ca. 2,5 h

---

### Task 9: Anbindung an den MCP-Client

**Files:** Create `run/.mcp.json`

- [ ] **Step 1:** `run/.mcp.json` anlegen. Server `drawing2cad`, Befehl `docker` mit den Argumenten `run -i --rm --network none -v /Users/abu/hackathon/drawings:/data:ro -v /Users/abu/hackathon/results:/app/results d2c`.
- [ ] **Step 2:** `docker build -t d2c .`, Ordner `/Users/abu/d2c-run` anlegen und `run/.mcp.json` hineinkopieren. Dort `claude mcp list` ausführen. Beim ersten Start fragt Claude Code, ob der Projekt-Server zugelassen werden soll: zulassen. Erwartet: `drawing2cad … ✓ Connected`.
- [ ] **Step 3:** In `/Users/abu/d2c-run` die Session starten mit `claude --disallowedTools "Bash,Read,Grep,Glob,Edit,Write,WebFetch,WebSearch,Agent"`. Dann `render_drawing` mit `pdf="Fuss/Fuss_dwg.pdf"` aufrufen. Erwartet: Das Bild wird angezeigt. Ein Versuch mit `pdf="Fuss/Fuss.stp"` wird abgewiesen.
- [ ] **Step 4:** Commit `chore: MCP client config for isolated part sessions`.

**Dauer:** ca. 20 min

---

### Task 10: Auswertungs- und Replay-Skripte

**Files:** Create `scripts/eval_refs.py`, `scripts/replay.py`, `tests/test_scripts.py`

**Interfaces – Consumes:** `metrics` (Task 4), `run_worker` (Task 5). **Produces:**
- `eval_refs.py`:
  - vergleicht jedes `<results_root()>/<T>/<T>.step` mit `<D2C_DATA>/<T>/<T>.stp`
  - Ausgabe: Markdown-Tabelle mit den Spalten Teil | ΔV % | ΔBBox max mm | Ø fehlend | Ø zusätzlich | MATCH
  - MATCH nach Spec Abschnitt 5
  - Exit-Code 0 immer, die Tabelle ist reine Information
  - schreibt die Tabelle immer auch nach `<results_root()>/EVAL.md`
- `replay.py`: baut jedes `<results_root()>/*/ops.json` mit `expected` aus `spec.json` neu → eine Zeile je Teil mit `ok`. Exit-Code 1, wenn ein Teil nicht `ok` ist.

- [ ] **Step 1: Tests schreiben:**
  - `test_eval_identical_is_match` (Referenz gegen sich selbst, über eine kopierte Datei in tmp)
  - `test_eval_detects_missing_diameter`
  - `test_replay_fails_on_bad_part`
- [ ] **Step 2:** TEST-Befehl → FAIL.
- [ ] **Step 3:** Implementieren.
- [ ] **Step 4:** TEST-Befehl → `3 passed`.
- [ ] **Step 5:** Commit `feat(scripts): reference evaluation and replay`.

**Dauer:** ca. 1 h

---

### Task 11: Teile umsetzen – Pflicht-Meilenstein M1 (Fuss, Welle, Haken)

Ausführender ist das KI-Modell über die MCP-Tools, nach `d2c/instructions.md`. **Keine** Python-Datei wird für ein einzelnes Teil von Hand geschrieben.

**Ablauf pro Teil** (gilt auch für Task 12):
- [ ] **a:** Isolierte Session wie in Task 9 Step 3 starten. Der Auftrag lautet: „Setze `<Teil>/<Teil>_dwg.pdf` nach den Server-Instructions um.“
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
| Haken | Platte 20 dick (z ±10), Ring Ø152 30 dick (z ±15) laut Schnitt A-A. Kontur als `path` mit scharfen Ecken plus `fillets` für R35, R35, R16 |

Allgemein gilt: Kantenrundungen erzeugen Zylinderflächen. Deren Ø zählen im MATCH-Vergleich mit, jede Rundung muss also stimmen.

**Abnahme M1:** 3 Zeilen in `results/EVAL.md`. Jede Zeile hat MATCH, oder jede Abweichung ist durch einen Review-Eintrag erklärt und im README-Abschnitt „Grenzen“ genannt. `python scripts/replay.py` liefert Exit-Code 0.

**Dauer:** ca. 3–4 h

---

### Task 12: Weitere Teile (Reihenfolge nach Schwierigkeit)

Gleicher Ablauf a–d wie in Task 11.

| # | Teil | Achte auf |
|---|---|---|
| 1 | Rotation | Titel „Drehteil“ ≠ Ordnername → Review. Maßstab 1:2. Fase 5×45°, Detail B (2:1) mit „1“. 6× Ø12 auf Ø50 als `polar` |
| 2 | Flansch | Maßstab 2:1. Wände (5) tangential zwischen den Naben, Steg 6: Tasche schneiden, dann die Naben wieder ansetzen. Ø2,5 und Ø3,5 mit Tiefe 10; ob Gewinde → Review. Die Bohrspitzen werden nicht modelliert, sie ändern MATCH nicht |
| 3 | Trägerplatte | Sammelangabe R=20 → für jede betroffene Ecke `assumed` + Review (`path` + `fillets`). M5 als `tapped`, Senkungen Ø11/Ø6,6 und Ø10,5/Ø5,5. Wanddicke 6 gegenüber 6,5 in den Schnitten → Review `conflict` |
| 4 | Dreistern | Arme unter 120°, Anzugswinkel 102°, R20 und R1. Gewölbte Oberseite eventuell per `run_script` |
| 5 | Befestigung | Gabel R30/R40, 3× Ø12 unter 45°, schräge Rippe. Ebenen aus der Seitenansicht |
| 6 | Maschinenteil | 12× Ø10 auf Ø76 mit 25,5° Teilung. Detail A (2:1). M10 außen als Ø10 + Review. Sammelangabe R=1 |

**Abnahme:** Jedes umgesetzte Teil erfüllt die Kriterien aus Task 11. Teile, die nicht fertig werden, stehen mit Grund im README-Abschnitt „Grenzen“.

**Dauer:** ca. 1–2 h pro Teil

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

## Danach (eigener Plan, erst wenn M1–M3 erfüllt sind)

- **X1 Toleranzen:** `Dimension` um `tol_upper`, `tol_lower` und `fit` erweitern. Für das Ändern bestehender Modelle reicht `edit_op`, da Ops nach einem Neustart von der Platte geladen werden.
- **C1/C2 AP242 + PMI:** Export über OCP-XDE (`STEPCAFControl_Writer`, `Interface_Static.SetCVal("write.step.schema", "AP242DIS")`, `XCAFDoc_DimTolTool`). Prüfung mit dem NIST SFA unter Windows.

## Zeitbudget

| Block | Tasks | Stunden |
|---|---|---|
| Infrastruktur | 1–10 | ca. 15,5 |
| Pflicht-Meilenstein M1 | 11 | 3–4 |
| Weitere Teile | 12 | 6–12 |
| Abgabe | 13 | 2 |
