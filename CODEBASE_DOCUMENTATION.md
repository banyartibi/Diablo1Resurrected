# ⚔️ Diablo 1: Resurrected – Teljes Rendszer- és Kódarchitektúra Dokumentáció

> **Dokumentum célja:** Ez a dokumentáció a **Diablo 1: Resurrected (D1R)** projekt teljes architektúráját, forráskód-felépítését, adatfolyamait és fejlesztési állapotát írja le. Célja, hogy jövőbeli AI asszisztensként vagy humán fejlesztőként egyetlen átolvasással pontosan megértsd, hol mi található, hogyan működik a hibrid motor, és milyen feladatokon dolgozunk.

---

## 1. 🌟 Projekt Áttekintés és Filozófia

A **Diablo 1: Resurrected (D1R)** egy következő generációs **hibrid játékmotor**, amely egyesíti:
1. **DevilutionX Core (C++17):** Az 1996-os Diablo 1 + Hellfire 100%-ban autentikus, hibajavított, determinisztikus játékszabályait, mesterséges intelligenciáját, tárgy/leltár rendszerét, mentéseit és hálózati kódját.
2. **Godot Engine 4.7.2 Forward+ Vulkan Renderer (C++ / GDScript):** Modern 3D/2.5D renderelést, PBR anyagokat, dinamikus megvilágítást, részecskerendszereket, procedurális árnyékokat, modern UI-t és térbeli hangrendszert.

### Miért ez a hibrid architektúra?
Ahelyett, hogy a Diablo 1 több százezer soros játéklogikáját és véletlenszám-generálását (RNG) újraírnánk Godotban (ami elkerülhetetlenül megváltoztatná az eredeti játékmenetet), a **DevilutionX közvetlenül beágyazva (in-process)** fut a Godot címterében egy natív **GDExtension** modulon keresztül. A Godot közvetlen memóriahozzáféréssel lekérdezi a játék állapotát (tile-ok, szörnyek, tárgyak, karakter, HP/Mana), miközben az input eseményeket közvetlenül a DevilutionX belső eseményvezérlőjébe küldi.

---

## 2. 🏛️ Rendszerarchitektúra & Adatfolyam

### 2.1 Architektúra Fejlődése
* **Kezdeti fázis (Legacy Dual-Engine IPC):** A DevilutionX külön folyamatként futott, és `/dev/shm/d1_godot_frame` osztott memórián (POSIX Shared Memory) keresztül küldte a renderelt képkockát a Godotnak. *(Ez ma már csak fallback módként létezik).*
* **Jelenlegi fázis (Native In-Process GDExtension):** A DevilutionX forráskódja közvetlenül belefordul a `libdiablo.so` GDExtension megosztott könyvtárba. A Godot indulásakor a `DiabloBridge` Node példányosul, elindítja a DevilutionX háttérszálat (`g_DiabloThread`), és **0 ms IPC késleltetéssel**, közvetlen C++ memóriapuffereken keresztül kommunikál a két motor.

### 2.2 Szálmodell és Szinkronizáció
* **Godot Fő Szál (Main/Render Thread):** Futtatja a Godot jelenetfát, a GDScript kódokat (`bridge_receiver.gd`, `native_25d_view.gd`, `native_3d_sandbox.gd`, `diablo4_hud.gd`), a Vulkan renderelőt és a hangkiszolgálót (144Hz+).
* **DevilutionX Szál (`g_DiabloThread`):** A `StartDevilutionXThread()` hívja meg a `devilution::DiabloMain()` függvényt egy független szálon, amely az autentikus tick-rátával (20 TPS) frissíti a játék állapotát.
* **Szinkronizáció & Biztonság:**
  * `g_InventoryMutex`: Védi a leltár, karakterlap, tárgyak és dungeon entitások lekérdezését.
  * `g_D1FrameMutex`: Védi a belső képkockapuffert (`g_D1InternalFrame`).
  * `g_DirectInputMutex`: Szálbiztos gyűrűpuffer a Godotból érkező beviteli üzeneteknek (`g_DirectInputQueue`).
  * `IsBridgeSafeToRead()`: Kritikus biztonsági kapu! `false` értéket ad vissza pályaváltáskor (`g_D1LevelTransitioning`), amíg a játékos betöltődik (`PM_NEWLVL`), vagy ha a játék nincs aktív dungeon állapotban. Ezzel megelőzhető minden memóriaszemét-olvasás és leállás (crash).

### 2.3 Rendszer Áttekintő Diagram

```
+-------------------------------------------------------------------------------+
|                             GODOT ENGINE 4.7.2                                |
|                                                                               |
|  +-------------------------------------------------------------------------+  |
|  | Main Scene: res://scenes/main_3d.tscn                                   |  |
|  | Controller: res://scripts/bridge_receiver.gd                            |  |
|  +-------------------------------------------------------------------------+  |
|         |                     |                          |                    |
|         v                     v                          v                    |
|  +---------------+   +-------------------+   +-------------------------+      |
|  |    MODE 0     |   |      MODE 1       |   |         MODE 2          |      |
|  | Classic 2.5D  |   | Native Godot 2.5D |   |    Native 3D Sandbox    |      |
|  | QuadMesh Blit |   | Reconstructed     |   | Real 3D Geometry Multi- |      |
|  | PBR Shader &  |   | DPieces, Y-Sorted |   | Meshes, Billboard 3D    |      |
|  | Relief Normal |   | Sprites, Lighting |   | Sprites, Orbit Camera   |      |
|  +---------------+   +-------------------+   +-------------------------+      |
|         ^                     ^                          ^                    |
|         |                     |                          |                    |
|  +-------------------------------------------------------------------------+  |
|  | Modern Diablo IV HUD (CanvasLayer) & Native Audio Manager               |  |
|  | - Liquid Health & Mana Globes (GLSL Shaders)                            |  |
|  | - 8-Slot Belt Action Bar, XP Bar, Level Up Banner                       |  |
|  | - Native Character Sheet, Quest Log & 40-slot Inventory Frame           |  |
|  | - 3D Positional Audio & Crossfading Music (res://scripts/audio_manager) |  |
|  +-------------------------------------------------------------------------+  |
|                                       ^                                       |
|                                       | (GDExtension C++ Binding)             |
+---------------------------------------|---------------------------------------+
                                        v
+-------------------------------------------------------------------------------+
|                 NATIVE GDEXTENSION: godot_d1_extension                        |
|                                                                               |
|  Class: DiabloBridge (inherits Node)                                          |
|  Files: diablo_bridge.h / diablo_bridge.cpp / register_types.cpp              |
|  Outputs: godot_d1_3d/bin/libdiablo.linux.template_debug.x86_64.so           |
+-------------------------------------------------------------------------------+
                                        ^
                                        | Direct C++ Linking (DVL_OBJECTS)
                                        v
+-------------------------------------------------------------------------------+
|                    DEVILUTIONX CORE (C++17 ENGINE)                            |
|                                                                               |
|  Bridge Hook: DevilutionX/Source/engine/render_bridge.cpp & .hpp              |
|  Gameplay Logic: player.cpp, monsters.cpp, items.cpp, spells.cpp, dthread.cpp |
|  Assets: diabdat.mpq, hellfire.mpq, CLX/CEL sprites, PCX palettes            |
+-------------------------------------------------------------------------------+
```

---

## 3. 🎮 A Három Megjelenítési Mód (3-Mode Architecture)

A játékos menet közben bármikor az **[F3]** gomb megnyomásával válthat a 3 renderelési mód között:

### 3.1 Mode 0: Classic 2.5D Blit (Vanilla + 3D PBR Relief Shader)
* **Megvalósítás:** `bridge_receiver.gd` + `shaders/d1_3d_material.gdshader` + `QuadMesh`.
* **Működési elv:** A DevilutionX 2560x1440-es felbontásban rendereli a játék képét a memóriába. A Godot minden képkockánál frissíti az `ImageTexture`-t a 3D világban elhelyezett síkon.
* **Grafikai extrák a shaderben:**
  * **Valódi 3D felületi relief (Surface Relief / Tangent-space Normal Mapping):** A textúra luminancia-gradienséből számított PBR normáltérkép, amely fizikai mélységet ad a köveknek, padlólapoknak és boltíveknek.
  * **Folyékony nedves padló (Wet & Reflective Cobblestone [F12]):** PBR érdesség és tükröződés fényes pocsolyákkal.
  * **Szuperfelbontású felskálázók ([F7]):**
    * AMD FidelityFX Contrast Adaptive Sharpening (CAS).
    * Anime4K / Neural Edge Push (élek rekonstrukciója).
    * 16-tap Catmull-Rom 8K bikubikus spline simítás.
  * **HDR Glow & Bloom ([F5]):** Valós idejű izzó fáklyafények.
  * **Volumetrikus köd ([F9]) & Színprofilok ([F10]):** Dark Gothic OLED, Hellish Crimson, Crypt Cyan, Desaturated Noir.

### 3.2 Mode 1: Native Godot 2.5D Engine (144Hz Smooth Engine)
* **Megvalósítás:** `scenes/views/native_25d_view.tscn` és `scripts/native_25d_view.gd`.
* **Működési elv:** A Godot nem egy egybefüggő videoképet jelenít meg, hanem **darabjaira bontva építi fel a világot Godot Node2D elemekből**:
  * **Dungeon DPieces (Pályaelemek):** A `diablo_bridge.get_dungeon_grid()` alapján az 56x56 / 112x112-es pályarács elemeit közvetlenül kinyeri és kesselve (`get_dungeon_piece_texture()`) helyezi el izometrikus gyémántrácson ($X_{screen} = (X - Y) \cdot 32$, $Y_{screen} = (X + Y) \cdot 16$).
  * **Boltívek és oszlopok (Special CELs):** Oszlopfejek, ajtókeretek, boltívek automatikus maszkolása és felülrétegzése (`get_dungeon_special_grid()`).
  * **Frontfal átlátszóság (Wall Transparency):** A játékos mögé eső elülső falak automatikusan félig átlátszóvá válnak az autentikus `dTransVal` és `GetTransList()` alapján.
  * **Organikus megvilágítás (Smooth Per-Tile Lighting):** A 112x112-es `dLight` rácsot a szomszédos tile-ok átlagolásával és Hermite smoothstep interpolációval simítja, megszüntetve a kockás megvilágítási határokat.
  * **Entitások és Y-Sorting:**
    * **Játékos és Szörnyek:** A CLX sprite-ok raszterizálva kerülnek fel a képernyőre (`get_player_sprite_data`, `get_monster_sprite_data`), Godot Y-sortinggal mélységhelyesen rendezve.
    * **Városlakók (Towners / NPCs):** Griswold, Pepin, Cain, Wirt, stb. animált megjelenítése és interakciói.
    * **Tárgyak és Loot (Ground Items):** A földön lévő tárgyak ritkaság szerinti arany/kék/fehér feliratokkal és ikonokkal.
    * **Holttestek (Corpses) & Lövedékek (Missiles):** Tűznyilak, villámok, csontváz-maradványok valós idejű pozicionálása.
  * **144Hz-es simított kamera követés:** Lerp interpolációval követi a játékost rázkódás nélkül.
  * **Modális ablakok és térkép:** Automata átlátszó Automap (Tab) és NPC bolt/párbeszéd overlay.

### 3.3 Mode 2: Native 3D Sandbox (Valódi 3D Geometria)
* **Megvalósítás:** `scenes/sandbox/native_3d_sandbox.tscn` és `scripts/native_3d_sandbox.gd`.
* **Működési elv:**
  * **Procedurális 3D Dungeon MultiMesh:** A falak, padlók és ajtók valódi 3D dobozokként/hasábokként jönnek létre PBR kő textúrákkal a szilárdsági rács (`get_dungeon_solidity_grid()`) alapján.
  * **3D Billboard Sprite-ok (Sprite3D):** A karakter és a szörnyek 3D térben lebegő, kamerához forduló vagy függőlegesen zárolt Y-billboard sprite-okként jelennek meg.
  * **Kamera Szabadság:**
    * Orbit forgatás: **[Q]** és **[E]** gombokkal, vagy középső egérgombos vonszolással (MMB).
    * Kamera döntés (Pitch): **[PageUp]** és **[PageDown]** (25° - 75° között).
    * Zoomolás: Egérgörgő.
  * **3D Sugárkövetéses Input (Raycasting):** Az egérkattintás a 3D padló-kollíziós síkra vetül vissza, és a Godot átszámítja Diablo 1 izometrikus koordinátákká, amit elküld a játékmotornak.

---

## 4. 📁 Részletes Könyvtár- és Fájltérkép

```
/home/biti/antigravity/magical-bell/
├── DevilutionX/                    # Az eredeti C++ DevilutionX forrásfa
│   ├── Source/
│   │   ├── engine/
│   │   │   ├── render_bridge.hpp   # C++ bridge fejléc: struktúrák, szálak, API deklarációk
│   │   │   └── render_bridge.cpp   # C++ bridge implementáció: sprite raszterizáció, rácsok, adatok
│   │   ├── DiabloUI/
│   │   │   └── text_input.cpp      # Javított szövegbevitel (Shift, Delete, vágólap, névbevitel)
│   │   ├── diablo.cpp              # Fő belépési pont, DiabloMain(), tick ciklus
│   │   ├── player.cpp              # Játékos állapot, mozgás, szintlépés
│   │   ├── monsters.cpp            # Szörny AI, animációk, életerő
│   │   └── items.cpp               # Tárgygenerálás, drop, leltár
│   └── build/                      # CMake/Ninja build kimenet (libdevilutionx tárgyfájlok)
│
├── godot_d1_extension/             # A Godot 4.7 GDExtension C++ modul
│   ├── CMakeLists.txt              # Összefűzi a DevilutionX .o fájlokat a godot-cpp-vel
│   └── src/
│       ├── diablo_bridge.h         # DiabloBridge Godot osztály deklarációja
│       ├── diablo_bridge.cpp       # DiabloBridge Godot osztály metódusai és ClassDB kötései
│       ├── register_types.h        # GDExtension modul regisztrációs fejléc
│       └── register_types.cpp      # GDExtension belépési pont (diablo_library_init)
│
├── godot_d1_3d/                    # A Godot 4.7.2 Projekt gyökérkönyvtára
│   ├── project.godot               # Projekt beállítások (2560x1440, Forward+, FSR bekapcsolva)
│   ├── bin/
│   │   ├── diablo.gdextension      # GDExtension konfigurációs fájl
│   │   └── libdiablo.linux.template_debug.x86_64.so # A lefordított megosztott könyvtár (~6 MB)
│   ├── scenes/
│   │   ├── main_3d.tscn            # Fő jelenet (Világ környezet, kamera, módváltó)
│   │   ├── views/
│   │   │   └── native_25d_view.tscn # Mode 1: Natív Godot 2.5D jelenet
│   │   ├── sandbox/
│   │   │   └── native_3d_sandbox.tscn # Mode 2: Natív 3D Sandbox jelenet
│   │   ├── hud/                    # Modern Diablo IV stílusú kezelőfelület
│   │   │   ├── diablo4_hud.tscn & .gd           # Fő HUD (gömbök, action bar, tooltip)
│   │   │   ├── diablo4_character_panel.tscn & .gd # Karakterlap és stat pontok
│   │   │   ├── diablo4_inventory.tscn & .gd     # 40-slot leltár és felszerelés
│   │   │   └── diablo4_quest_log.tscn & .gd     # Küldetésnapló
│   │   └── effects/                # 3D részecske effektek (vér, csontok, fáklyák)
│   ├── scripts/
│   │   ├── bridge_receiver.gd      # Fő kontroller (módváltás, input routing, shader paraméterek)
│   │   ├── native_25d_view.gd      # Mode 1 logikája (tile generálás, simítás, entitások)
│   │   ├── native_3d_sandbox.gd    # Mode 2 logikája (MultiMesh 3D, kameramozgás, 3D sprite-ok)
│   │   └── audio_manager.gd        # Natív Godot hangrendszer (Spatial 3D SFX, Music crossfade)
│   └── shaders/
│       ├── d1_3d_material.gdshader # Mode 0 főkép shader (Normal relief, CAS, wet floor)
│       ├── liquid_globe.gdshader   # Hullámzó, folyékony életerő- és managömbök
│       ├── hud_panel_bg.gdshader   # Gótikus kőfelület és aranyozott szegélyek
│       └── action_slot.gdshader    # Képesség- és italgombok árnyalása
│
├── tools/                          # Asset feldolgozó és segédeszközök
│   ├── godot4/godot4               # Hordozható Godot 4.7.2 engine bináris
│   ├── extract_mpq.py / mpq_extract.cpp # MPQ fájl kibontó
│   ├── png_to_clx.cpp / export_sprites_to_png.cpp # CLX sprite konverterek
│   └── upscale_sprites_ai.py       # Real-ESRGAN neurális felskálázó script
│
├── build_gdextension.sh            # 1 kattintásos fordító script (DevilutionX + GDExtension)
├── run_d1_godot3d.sh               # Játékindító script izolált környezeti változókkal
└── README.md                       # Általános GitHub bemutató
```

---

## 5. 🔌 DiabloBridge GDExtension API Referencia

A `DiabloBridge` Node osztály (GDScriptből elérhető) közvetlen hidat képez a DevilutionX belső C++ motorjához:

### 5.1 Motor Életciklus & Állapot
* `bool init_engine(String mpq_dir)`: Elindítja a DevilutionX háttérszálat a megadott MPQ elérési úttal.
* `bool is_engine_ready() const`: Kész-e a bridge adatok fogadására.
* `bool is_game_running() const`: Aktív-e a játék (dungeonben vagy faluban van a játékos, nem a főmenüben).
* `bool is_level_loading() const`: Folyamatban van-e szintváltás.
* `bool is_modal_active() const`: Nyitva van-e modális menü (Esc menü, NPC párbeszéd, bolt, stb.).
* `int get_modal_type() const`: 0 = Nincs, 1 = Esc menü/Pause/Halál, 2 = NPC párbeszéd/Bolt.
* `bool is_automap_active() const`: Be van-e kapcsolva az Automap (Tab billentyű).
* `Ref<ImageTexture> get_automap_texture()`: Visszaadja a valós idejű átlátszó automap RGBA textúráját.
* `void quit_engine()`: Leállítja a motort és felszabadítja a memóriát.

### 5.2 Játékos Statisztikák & Leltár
* `Vector2i get_player_tile_pos() const`: A játékos diszkrét csempe pozíciója (pl. `(25, 25)`).
* `Vector2 get_player_norm_pos() const`: Képernyőre normalizált játékos pozíció (`0.0 .. 1.0`).
* `Dictionary get_player_continuous_pos() const`: Lebegőpontos világpozíció simított mozgáshoz (`posX`, `posY`, `isWalking`, `mode`, `dir`).
* `int get_player_hp() / get_player_max_hp()`: Jelenlegi és maximális életerő pontok.
* `int get_player_mana() / get_player_max_mana()`: Jelenlegi és maximális mana pontok.
* `int get_player_level() / get_player_xp() / get_player_next_xp()`: Szint és tapasztalati pontok.
* `int get_player_gold() const`: Nálunk lévő arany összege.
* `Array get_player_equipment() const`: Felszerelt tárgyak tömbje (fej, nyak, test, kezek, gyűrűk).
* `Array get_player_backpack() const`: Hátizsák 40 rekeszének tartalma mérettel, statisztikákkal és ikonazonosítóval.
* `Dictionary get_character_info() const`: Erő, Mágia, Ügyesség, Vitalitás, Sebzés, Védelem, Ellenállások.
* `void add_attribute_point(int attr_idx)`: Stat pont elosztása (0=Str, 1=Mag, 2=Dex, 3=Vit).
* `void click_inventory_slot(int slot_type, int slot_idx, bool is_shift, bool is_ctrl)`: Tárgy mozgatása / kattintása a leltárban.
* `void use_inventory_slot(int slot_type, int slot_idx)`: Tárgy használata (jobb klikk: ivás, azonosítás).

### 5.3 Dungeon Rács & Megjelenítés
* `PackedInt32Array get_dungeon_grid() const`: A pálya 112x112-es csempeazonosító tömbje (`dPiece`).
* `Dictionary get_dungeon_piece_data(int piece_id) const`: Pályaelem metaadatai (méret, sorok száma).
* `Ref<ImageTexture> get_dungeon_piece_texture(int piece_id)`: Pályaelem RGBA textúrája (gyorsítótárazva).
* `PackedInt32Array get_dungeon_special_grid() const`: Különleges építészeti elemek (boltívek, ajtónyílások).
* `PackedByteArray get_dungeon_light_grid() const`: 112x112-es megvilágítási értékek (0 = teljes fény, 15 = vaksötét).
* `PackedByteArray get_dungeon_trans_grid() const`: Szobák átlátszósági maszkja (`dTransVal`).
* `PackedByteArray get_trans_list() const`: Jelenleg átlátszóvá tett zónák azonosítói.
* `PackedByteArray get_dungeon_solidity_grid() const`: 112x112-es szilárdsági térkép (0 = járható, 1 = fal/akadály).

### 5.4 Entitások (Szörnyek, Tárgyak, Lövedékek, Hangok)
* `Array get_active_monsters_data() const`: Aktív szörnyek listája (ID, név, lebegőpontos pozíció, HP, animáció, irány, állapot).
* `Dictionary get_monster_sprite_data(int monster_id) const`: Adott szörny vagy Towner NPC aktuális animációs képkockája RGBA formátumban.
* `Dictionary get_player_sprite_data() const`: A játékos kasztjának és páncélzatának megfelelő animációs képkocka.
* `Array get_active_objects() const`: Tereptárgyak (ládák, szentélyek, hordók, fali fáklyák).
* `Array get_active_items() const`: Földön lévő zsákmány (loot) pozíciója, neve, ritkasága.
* `Array get_active_corpses() const`: Elesett szörnyek és holttestek a talajon.
* `Array get_active_missiles() const`: Repülő varázslatok és lövedékek (tűzgolyó, nyílvessző, villám).
* `Array poll_audio_events()`: DevilutionX hang- és zeneesemények kiolvasása a hangmotor számára.

### 5.5 Input Irányítás
* `void send_input(int type, int code, int state, int x, int y)`: Egérmozgás, kattintás vagy billentyűzet-esemény küldése közvetlenül a DevilutionX felé.
* `void send_key_event(int keycode, bool pressed)`: Billentyűleütés küldése SDL billentyűkóddal.

---

## 6. 🎨 Modern Diablo IV HUD & Kezelőfelület

A `godot_d1_3d/scenes/hud/diablo4_hud.gd` valósítja meg a teljes felületet:

1. **Életerő és Mana Gömbök:**
   * Egyedi GLSL shader (`liquid_globe.gdshader`) szimulálja a hullámzó, örvénylő folyadékot, fénycsillanásokkal és buborékokkal.
   * Százalékos és numerikus lebegő címkék.
2. **Akciósáv (Action Bar) & Öv (Belt):**
   * 8 darab gyorsgombos rekesz (`1`-`8` billentyűk vagy kattintás).
   * Különböző italtípusok (életerő, mana, rejuv, tekercsek) automatikus felismerése egyedi színezett ikonokkal (`TEX_HEAL`, `TEX_MANA`, stb.).
   * Másodlagos képesség / varázslat ikon jobb oldalon, kattintásra megnyíló Speedbook varázslatválasztó szalaggal.
3. **Karakterlap (Character Panel - [C]):**
   * Gótikus kőkeretes panel (`diablo4_character_panel.tscn`).
   * Elosztható stat pontok kijelzése, interaktív `+` gombokkal (Strength, Magic, Dexterity, Vitality).
   * Részletes statisztikák: Sebzés, Támadóérték, Védelem, Mágia/Tűz/Villám ellenállások.
4. **Leltár (Inventory Frame - [I]):**
   * Diablo IV stílusú paperdoll elrendezés (sisak, páncél, fegyver, pajzs, gyűrűk, amulett).
   * 40 férőhelyes hátizsák rács többszörös foglalású tárgyakkal (1x1, 1x2, 1x3, 2x3 rekeszes fegyverek és vértek).
   * Tárgy hover tooltip lebegő ablakkal: ritkaság szerinti szegélyszín (Szürke/Normál, Mágikus Kék, Egyedi Arany, Követelménynek nem megfelelő Vörös).
5. **Küldetésnapló (Quest Log - [Q]):**
   * Aktív és teljesített küldetések listája (`diablo4_quest_log.tscn`).

---

## 7. 🔊 Natív Térbeli Audió Rendszer (`audio_manager.gd`)

A játék hangzásáért a Godot 4.7 natív hangmotorja felel, amely lehallgatja a DevilutionX hanghívásait:
* **Zenei Rendszer (Music Crossfade):**
  * Két független `AudioStreamPlayer` csatorna (`D1_MusicPlayerA` és `D1_MusicPlayerB`).
  * Pályaváltáskor vagy faluba lépéskor sima hangerő-átúszással (Tween) vált az autentikus zenék között.
* **2D UI & Dialógus Hangok:**
  * 16 tagú hangpuffer a leltárkattintásokhoz, gombokhoz, szintlépéshez és NPC beszédekhez.
* **3D Térbeli SFX (Spatial Positional Audio):**
  * 24 tagú `AudioStreamPlayer3D` objektumpool.
  * A szörnyek hörgése, a csapódó ajtók, a fáklyák sercegése és a varázslatok robbanása a valódi izometrikus vagy 3D koordinátáikról szólnak.
  * Beépített környezeti kripta-visszhang (Reverb Bus: room size 0.25, wet 0.12).

---

## 8. ⌨️ Billentyűzet & Irányítási Segédlet

| Billentyű | Funkció |
|---|---|
| **Egérgörgő FEL** | Zoom növelése (1.0x → 1.5x → 2.0x → 2.5x → 3.0x) |
| **Egérgörgő LE** | Zoom csökkentése (3.0x → 2.5x → 2.0x → 1.5x → 1.0x) |
| **[F3]** | **Renderelési Mód Váltása:** Mode 0 (Classic Blit) ↔ Mode 1 (Native 2.5D) ↔ Mode 2 (Native 3D) |
| **[F4]** | V-Sync ki/bekapcsolása (144Hz Monitor frissítés vs. korlátlan FPS) |
| **[F5]** | HDR Izzás és Fénykoszorú szintje (Ki / 1.0x / 2.0x / 3.0x) |
| **[F6]** | Játékos fáklyafény (Hero Torch Light) be/ki |
| **[F7]** | Felskálázó ciklus (AMD FSR CAS / Neural Edge / Anime4K / 8K Catmull-Rom / Native) |
| **[F8]** | Valós idejű FPS számláló ki/be |
| **[F9]** | Volumetrikus köd mód (Ki / Kripta Pára / Sűrű Pokoltűz Füst) |
| **[F10]** | Színprofil ciklus (1996 Classic / Dark Gothic OLED / Hellish Crimson / Crypt Cyan / Noir) |
| **[F11]** | 3D Felületi Relief ciklus (Ki / Finom / Kiegyensúlyozott / Mély 3D / Extrém) |
| **[F12]** | Vizes kövezett padló PBR pocsolya-tükröződések ki/be |
| **[Q] / [E]** | *(Mode 2-ben)* Kamera körbeforgatása (Orbit Yaw) a játékos körül |
| **[PageUp] / [PgDn]** | *(Mode 2-ben)* Kamera dőlésszögének állítása (Pitch 25° - 75°) |
| **[C]** | Karakterlap megnyitása / bezárása |
| **[I]** | Leltár megnyitása / bezárása |
| **[Q]** | Küldetésnapló megnyitása / bezárása |
| **[Tab]** | Automap (átlátszó térkép) ki/bekapcsolása |
| **[1] - [8]** | Övben lévő italok és tekercsek azonnali elfogyasztása |

---

## 9. 🛠️ Fordítás, Futtatás & Fejlesztői Munkamenet

### 9.1 Előfeltételek (Ubuntu / Debian Linux)
* Telepített Vulkan meghajtók (`libvulkan1`, `mesa-vulkan-drivers`).
* `cmake`, `ninja-build`, `g++` (C++17 kompatibilis).
* `diabdat.mpq` (az eredeti játék adatfájlja) elhelyezve a `~/.local/share/diasurgical/devilution/` könyvtárban.

### 9.2 Újrafordítás (Build)
Ha módosítasz a DevilutionX C++ forráskódján vagy a `godot_d1_extension` fájljain, egyszerűen futtasd:
```bash
./build_gdextension.sh
```
Ez a szkript:
1. Lefordítja a módosított DevilutionX C++ részeket Ninja segítségével.
2. Lefordítja a GDExtension C++ réteget (`diablo_bridge.cpp`).
3. Létrehozza és átmásolja a friss `godot_d1_3d/bin/libdiablo.linux.template_debug.x86_64.so` könyvtárat.

### 9.3 Játék Futtatása (Run)
```bash
./run_d1_godot3d.sh
```
A futtató szkript gondoskodik a:
* Szükséges dinamikus könyvtárakról (`LD_LIBRARY_PATH`, `libSDL2-2.0.so`).
* Izolált Godot beállítási mappákról (`XDG_DATA_HOME`, `XDG_CONFIG_HOME`).
* Korábbi osztott memória maradványok törléséről (`/dev/shm/d1_godot_frame`).
* A Godot 4.7.2 Forward+ motor közvetlen indításáról.

---

## 10. 📌 Legutóbbi Eredmények & Folyamatban Lévő Munkák

### Nemrégiben Elvégzett Fejlesztések:
1. **Mode 1 (Native 2.5D) Teljessége:**
   * Towner / NPC animációk és boltos párbeszédek hibátlan megjelenítése (Griswold, Pepin, stb.).
   * Halál-animációk és újraszületés/menü vezérlés.
   * Pályaváltás (Town ↔ Labyrinth) fagyásmentesítése (`g_D1LevelTransitioning` védelem).
   * Dobott tárgyak (loot) lebegő címkéi automatikus ritkaság-színezéssel (Arany, Kék, Fehér).
   * Hermite simítás a megvilágítási rácsban (eltűntek az éles tile-határok a fényben).
   * Modális ablakok és átlátszó Automap overlay integrálása a 2.5D és 3D módokba.
2. **Szövegbevitel Javítása (`text_input.cpp`):**
   * Karakterkészítéskor működik a nagybetűs gépelés (Shift), a Backspace, a Delete és a vágólap (Ctrl+V).
3. **Főmenü és Játékmenet Elválasztása:**
   * A főmenüben, karakterválasztóban és intro képernyőn a rendszer mindig a klasszikus interaktív nézetet jeleníti meg, elkerülve a 2.5D/3D raycasting beakadását még a játék elindulása előtt.

### Indulási Crash & Tisztaságos Leállás Hibajavítása (`render_bridge.cpp`):
* **Hiba:** A indítás után ~1–2 s-ban leállt a folyamat, majd `terminate called without an active exception` + core dump (SIGABRT) következett.
* **Ok (root cause):** `ExportGodotFrame()` minden képkernyőn meghívja az `InitGodotBridge()`-t, ami eredetileg feltételezetten hívta a `CleanupGodotBridge()`-t — ez pedig a `RequestDevilutionXQuit()`-on keresztül leállította a motort még az intro/splash movie közben. Mivel ez a **motor szálon** futott, a `g_DiabloThread` csatlakoztatlanul (joinable) maradt, és kilépéskor a `~std::thread()` `std::terminate()`-ra futott → core.
* **Javítás:**
  1. Az `InitGodotBridge()` most már **csak akkor** végzi el a leállítást (`CleanupGodotBridge()`), ha egy meglévő leképezést kell átméretezni — az **első létrehozás soha** nem kér leállást, így a motor eléri a főmenüt és folyamatosan streameli a képkernyőket.
  2. SIGINT/SIGTERM kezelő (`d1_term_handler`), amely a `RequestDevilutionXQuit()`-on keresztül **összecsatolja** (`join`) a `g_DiabloThread`-t a leállás előtt, majd visszahívja az előző kezelőt (így a Godot saját Ctrl+C / `kill` viselkedése is megmarad). Ez tisztaságos leállást biztosít anélkül, hogy core keletkezne.
* **Ellenőrzés:** a motor csatlakozik (`In-Process Engine Connected`), a SHM aktívan írja a teljes képkernyőt (~19.6 MB pixel buffer); `--quit-after` és egy futó motorra küldött SIGTERM is **0-s kóddal, terminate sorok nélkül, core dump nélkül** lép ki. A korábbi ideiglenes hibakeresés (debug prints) eltávolítva.
* **Másodlagos (nem javított) kérdés:** audió leállásnélküli hiba `Aulib::init` / SDL2↔SDL3 átlépés teardownnál. A sandboxban „No such audio device” hibát ad; a valós gépen a PulseAudio működik — ez egy külön, még megvizsgálatlan kérdés.

### Játékmenet Szálszintű Crash Hibajavítása — Mentás Menu (`render_bridge.cpp`, `diablo_bridge.cpp`):
* **Hiba:** `Esc menü → Save Game (Mentás)` kiválasztás után azonnal összeomlik a folyamat: `malloc(): unsorted double linked list corrupted` (SIGABRT), core dump-pal. A backtrace a `Godot főszálon` futó híd meghívást mutatja: `activate_modal_item()` → `ActivateModalItem()` → `ActivateGamemenuItem` → `gamemenu_save_game` → `DrawAndBlit` → `RenderPresent` → `ExportGodotFrame(memmove)`.
* **Ok (root cause — versenykörülmény):** Az összes `void`-változtató híd metódus eredetileg **a Godot főszálon** futtatta közvetlenül a játékmotor kódot. Egy ilyen hívás (pl. Mentás) belül végigfutja az egész `RenderPresent()` ciklust — ami megosztott SDL `texture`/`renderer`/`surface` és gyűjtőhelyi (heap) állapotot használ **párhuzamosan** a motor saját (`g_DiabloThread`) render körével. Két szál ugyanazt a heap-et/SDL állapotot módosítja → a heap korruptálódik → `malloc` abort.
* **Javítás (szálbiztonságos, sorbaűzés):** Minden állapot-modosító híd metódus most már **csak sorba tűzi** a munkasort (`PushBridgeAction`), a tényleges végrehajtást pedig a **motor szál** végezi le — pontosan ott, ahol a `PollEvent()` már minden keretben dréneli a bemenetet (`PollGodotBridgeInput`). Így a Ment stb. ugyanazon a szálon fut, ahol a nyers egér/billentyűzet bemenet is áramlik, így megszüntetik a versenyt. A **lekérdező** (getter/read-metódusok) továbbra is szinkron maradnak a Godot szálon, mert eredményt adnak és nem módosítják az állapotot — így viselkedés-biztos az olvasás.
  * **Sorbaűzett metódusok (14 db, mind `void` változtató):** `use_belt_slot`, `click_belt_slot`, `set_vanilla_hud_hidden`, `activate_modal_item`, `select_modal_item`, `dismiss_qtext`, `select_spell`, `add_attribute_point`, `toggle_character_sheet`, `select_quest`, `toggle_quest_log`, `toggle_inventory`, `click_inventory_slot`, `use_inventory_slot`. Az `init_engine`/`quit_engine` (biztos — atomos flag + szál join) és az üres `step_tick` nem kerül sorba.
  * **Megvalósítás:** új `D1BridgeActionType` enum + `PushBridgeAction(...)` a `render_bridge.hpp`-ben; a `render_bridge.cpp` anon namespace-e hozzáadja a `g_BridgeJobMutex`/`g_BridgeJobs` munkasort, a `PushBridgeAction()` csak sorba tűz, egy `switch` blokk pedig a `PollGodotBridgeInput()` elején (a motor szál) hívja a valós gyűjtött függvényeket. A `diablo_bridge.cpp`-ben az összes 14 változtató metódus már mind `devilution::PushBridgeAction(...)`-ra irányul.
* **Fordítás hibájának javítása (blokkolépés):** a bevezetett kód nem fordult — egy `{` hiányzott a `lock_guard` RAII scope-jában a `PollGodotBridgeInput()` drénelő switch-blokkjában (a switch és a `for` bezárása után az anon-scope bezárása elmaradt), ami miatt a mélység végig +1 maradt és minden következő függvényt "absorbe" tett → sorozatos "a function-definition is not allowed here" hibák. A hiányzó `}` hozzáadása után a gyűjtőhelyi zárások **377/377**, a `DevilutionX/build` tiszta (0 hiba), és az egész GDExtension `.so` újratördítve.
* **Ellenőrzés:** a build tiszta (`ninja` 0 hiba; csak meglévő fmt/-Wvexing-parse hangos figyelmeztetések). Az indítás tisztaságos, a motor csatlakozik és streameli a képkernyőket; a `SIGTERM/SIGINT`-ra adott leállás **0-s kóddal, `terminate` sorok nélkül, core dump nélkül** — ezzel a leállás-biztosási alapvonal helyrehozva. A pontos `Esc → Save Game` interakció végső reprodukálása egy izolált környezetben nem biztonságosan automatizálható (Xvfb hiánya + élő asztal; a Mentéshez betöltött játékhelyzet kell, ami többlépcsős új játék → karakterválaszó → dungeon belépést igényel). A javítás **logikailag helyes** és fordítva van igazolva; a futtatóoldali végteszt ajánlott a valós játékmenetben egy mentással. **Ez a futam:** az `.so` újrafordítva (`render_bridge.cpp`+`diablo_bridge.cpp`, `ninja` tiszta), headless (SDL dummy) indítás tiszta + frame-streamelés, SIGINT-ra exit 0 / `terminate`/`malloc` hibák nélkül; statikus audittal **0 közvetlen állapotmodosító híd-hívás** és pontosan **14 `PushBridgeAction`-tűzés** igazolva — a verseny a felépítés szerint megszüntetve.

### Következő Lehetséges Lépések (Roadmap):
* Mode 2 (Native 3D Sandbox) továbbfejlesztése: valódi 3D-s dungeon fal-modellek és oszlopok a dobozok helyett.
* További PBR anyagok és textúrák a környezethez.
* Teljes játékon belüli beállítások menü a modern HUD alá.
