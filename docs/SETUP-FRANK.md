# Puesta en marcha de rea-video en esta VM

Notas de una verificación hecha el 2026-11-08 sobre el fork sincronizado con el commit upstream `6d67d8479a0ca178c14cfcc36dc565f55b83d28c` (`6d67d84`, mensaje: «剪辑包装跟着台词走»). No se llamó a ningún modelo de pago ni se ejecutó `remake-run`. El código de upstream no se modificó: lo único nuevo es este documento y `scripts/smoke_offline.sh`.

## Versión y dependencias

| Dato | Valor en el repo | Lo que había en la VM |
|---|---|---|
| Paquete | `rea-video` **0.1.0** (`pyproject.toml`) | editable install desde este checkout |
| Python | `>=3.10` | **3.12.3** |
| Sistema | `ffmpeg` y `ffprobe` | **6.1.1** (`6.1.1-3ubuntu5`) |
| Licencia | Apache-2.0 | `LICENSE` + `NOTICE` (Copyright 2026 JuneYaooo) |

Dependencias Python declaradas: `numpy`, `opencv-python-headless` (`>=4.8,<5`), `Pillow`, `PyYAML`, `onnxruntime`. Extra `ocr`: `rapidocr-onnxruntime`. Extra `dev`: `pytest`, `jsonschema`.

`CLAUDE.md` solo reenvía a `AGENTS.md`. El changelog de la punta es el de la detección de cortes y de la capa de empaquetado alineada con el diálogo (`CHANGELOG.md`).

## Instalación que funcionó

En Ubuntu el `python3 -m venv` del sistema falló la primera vez: `ensurepip` no estaba. Se instaló el paquete `python3.12-venv` y se recreó el entorno.

```bash
sudo apt-get install -y python3.12-venv ffmpeg
python3 -m venv .venv
.venv/bin/python -m pip install -U pip
.venv/bin/python -m pip install -e ".[ocr,dev]"
# rapidocr arrastra opencv-python (con GUI) y pisa el cv2 headless.
# install_skill.sh hace este paso solo; un pip manual no.
.venv/bin/python -m pip uninstall -y opencv-python
.venv/bin/python -m pip install --force-reinstall --no-deps "opencv-python-headless>=4.8,<5"
.venv/bin/rea-video --help
```

Después de ese paso, `import cv2` resuelve **4.14.0** desde `opencv-python-headless`, y `rapidocr_onnxruntime` sigue importando. Antes del dedupe, `cv2` era **5.0.0.93** (`opencv-python`). Los tests pasaron en los dos estados; el dedupe deja la pila que el proyecto declara (`headless >=4.8,<5`).

`.venv/` está en `.gitignore`. No hace falta `scripts/install_skill.sh` para usar el CLI; ese script además enlaza el skill a `~/.claude`, `~/.codex` o `~/.agents`.

`pip` avisa de que `project.license` como tabla TOML está deprecado en setuptools nuevos. Es un aviso de empaquetado, no un fallo de instalación. No se tocó `pyproject.toml`.

## Tests

```bash
.venv/bin/python -m pytest -q
```

| Corrida | OpenCV importado | Resultado |
|---|---|---|
| Antes del dedupe | `opencv-python` 5.0.0.93 | **168 passed** en 52.30 s |
| Después del dedupe | `opencv-python-headless` 4.14.0.94 | **168 passed** en 51.05 s |

No hubo fallos que diagnosticar en la suite. No se ejecutó `rea-video eval` sobre `eval/labels.yaml`: eso mide el clasificador contra el conjunto etiquetado, y esta pasada solo cubre la suite y el camino local.

## Prueba offline (hecha de verdad)

`scripts/smoke_offline.sh` genera un mp4 de 6 s, 640×360, 30 fps, con tres planos de luminancia distinta (blanco 0–2 s, negro 2–4 s, azul con un bloque blanco 4–6 s), un seno de 440 Hz y un pitido de 1760 Hz a los 4.5 s. Luego corre:

```bash
rea-video decompose clip.mp4 -o out --no-vlm --lang en
```

con `REA_VLM_*`, `VIDEO_ANALYSIS_*` y `GEMINI3_*` quitadas del entorno, y `REA_VIDEO_HOME` apuntando a un directorio de la propia corrida para no leer preferencias que activen el VLM.

Resultado de la corrida de verificación (7.5 s, modelo de stems ya en caché):

- **3 planos**, cortes en 2.000 s y 4.000 s, `transition_in=cut`, `boundary_score=1.0`.
- `analysis.vlm`: `{"used": false, "requested": false, "status": "off"}`.
- Stems escritos: `stems/original.wav`, `vocals.wav`, `music.wav` (~1.1 MB cada uno, duración 6.014 s). `stems.ok=true`, modelo `UVR-MDX-NET-Inst_HQ_3.onnx`. Niveles: mezcla −24.0 dB, voces −66.2 dB, música −24.0 dB. El tono se fue al stem instrumental; la pista de voz queda casi en silencio. Eso es la separación, no una llamada a una API.
- El transitorio del pitido sale como un SFX `pop` a **t=4.47 s** (confianza baja; el propio informe dice que la lista completa de efectos la completaría un VLM).
- También aparecen `report.html`, `report.md`, `breakdown.json`, `storyboard.jpg`, `audio.png`, `shots/shot_00N.jpg` y `packaging/timeline.json`.

El veredicto «code / template render 100%» y el BPM 101.3 sobre un seno sintético no demuestran el clasificador de producción ni la detección de música. Los planos son campos planos congelados; el detector de tempo ve periodicidad donde no hay una canción. La prueba cubre cortes, extracción y separación, no la etiqueta de «cómo se hizo».

### Un corte que esta versión no ve

Un clip anterior, rojo → verde → azul, con cajas en movimiento y luminancia parecida entre el rojo (`~107`) y el verde (`~104`), solo partió en **2 planos** (0–4 s y 4–6 s). En el frame 60 (t=2.00) el histograma de color salta a 1.0, pero la diferencia de gris es 0.012 y `changed=0`. En `rea_video/shots.py`, el corte duro exige que cambie una fracción grande del frame en gris (`chg > 0.25`, o las variantes de salto). Un cambio de tono con la misma luma no pasa esa puerta. El corte a 4 s sí pasó porque el azul es más oscuro (`luma ~73`, `changed=1`). El script de humo usa blanco/negro/azul a propósito. No se cambió el detector.

### Descargas de la primera corrida (gratis, sin clave)

No son APIs de pago. Hacen falta red una vez; el checksum está fijado en el código.

| Archivo | Origen | Tamaño medido |
|---|---|---|
| `UVR-MDX-NET-Inst_HQ_3.onnx` | `github.com/TRvlvr/model_repo` releases | 66 759 214 bytes |
| `face_detection_yunet_2023mar.onnx` | `github.com/opencv/opencv_zoo` (commit fijado en `faces.py`) | 232 589 bytes |

El OCR chino/inglés usa los modelos que trae `rapidocr-onnxruntime`. El modelo japonés (`--ocr-lang ja`) sí se baja de ModelScope (`overlay.py`) y no se usó.

Repetir:

```bash
bash scripts/smoke_offline.sh
# o: bash scripts/smoke_offline.sh /tmp/rea-smoke
```

Imprime un JSON con `ok: true` y la línea `PASS`. La salida cae en `out/smoke-offline/` (gitignored) salvo que pases otro directorio.

## Qué es local y qué puede cobrar

| Camino | ¿Se ejecutó? | ¿Cobra? |
|---|---|---|
| `decompose` sin `--vlm`: cortes, frames, OCR local, stems ONNX, informe | Sí | No. Solo CPU y, la primera vez, las dos descargas de arriba |
| `probe`, `summary`, `tiles`, `review` / `apply-review` (el agente mira fotos locales) | `summary` sí, el resto no en esta pasada | No |
| `decompose --vlm` | No | Sí, si hay clave. POST a `{BASE_URL}/chat/completions`. El precio lo pone el proveedor (Gemini, GPT-4o, Doubao, Qwen-VL, u otro compatible con OpenAI) |
| `remake-plan` | No | No llama a la red. Escribe un plan que nombra motores de capsule-cinema |
| `remake-run` sin `--dry-run` | No | Sí. Importa `UniversalVideoGenerationTool` de un checkout de [capsule-cinema](https://github.com/JuneYaooo/capsule-cinema) y genera vídeo con las claves de ese proyecto. `--dry-run` solo imprime |
| `capsule-draft` | No | Depende de capsule-cinema; no está instalado aquí |
| `eval` | No | Local si no pasas `--vlm` |

`decompose` sigue aunque pidas `--vlm` y no haya configuración: el estado pasa a `not_configured` y no hay HTTP. En esta pasada ni siquiera se pidió (`--no-vlm`).

## Variables de entorno

Claves, todas opcionales. Sin ellas el análisis local funciona.

| Variable | Para qué | ¿Cobra si está puesta? |
|---|---|---|
| `REA_VLM_BASE_URL`, `REA_VLM_API_KEY`, `REA_VLM_MODEL` | VLM OpenAI-compatible. `REA_VLM_MODEL` admite varios modelos separados por comas | Solo si se corre con `--vlm` (o `prefs vlm on` y sin `--no-vlm`) |
| `REA_VLM_TIMEOUT`, `REA_VLM_MEDIA` (`both` / `video` / `frames`) | Tiempo y tipo de medio del VLM | Igual que arriba |
| `VIDEO_ANALYSIS_BASE_URL`, `VIDEO_ANALYSIS_API_KEY`, `VIDEO_ANALYSIS_MODEL_NAME`, `VIDEO_ANALYSIS_TIMEOUT_SECONDS` | Respaldo, nombres que usa capsule-cinema | Igual |
| `GEMINI3_BASE_URL`, `GEMINI3_API_KEY`, `GEMINI3_MODEL_NAME` | Segundo respaldo. Si el endpoint y la clave coinciden con el anterior, sus modelos se añaden como fallback | Igual |
| `REA_VIDEO_HOME` | Preferencias y correcciones. Default `~/.rea-video` | No |
| `REA_VIDEO_MODELS` | Caché de ONNX. Default `~/.cache/rea-video/models` | No |
| `REA_OCR_LANG`, `REA_OCR_REC_MODEL` | Idioma OCR y, en japonés, ruta local para no descargar | No |
| `CAPSULE_CINEMA_ROOT`, `CAPSULE_CINEMA_PYTHON` | Dónde está capsule-cinema | El gasto ocurre al ejecutar generación, no al apuntar el path |
| `--env-file` | Carga un `.env` sin commitearlo (`util.py` no pisa variables ya definidas) | Según lo que contenga |

No existe `ELEVENLABS_API_KEY`, `HIGGSFIELD_API_KEY`, ni ningún otro nombre de esas dos marcas en el código.

## Inventario de servicios

Cliente HTTP de modelos dentro de este repo: solo `rea_video/vlm.py` (`urllib` a `/chat/completions`). El resto de red son descargas de pesos o un puente a otro repositorio.

1. **VLM genérico** (opcional, de pago según el host). Documentado en `skills/rea-video/references/setup.md` y `docs/cli.md`.
2. **Pesos UVR** (TRvlvr en GitHub) y **YuNet** (opencv_zoo). Locales después de la primera descarga. Sin clave.
3. **OCR japonés** en ModelScope. Solo con `--ocr-lang ja`. Sin clave. El OCR por defecto no sale a la red.
4. **capsule-cinema** (`rea_video/integrations/run_remake.py`, `to_capsule.py`, `capsule_cinema.py`). Opcional y externo. `run_remake.py` carga el `.env` de ese repo y llama a su herramienta de generación de vídeo. Los motores que este repo nombra por defecto en el plan son `seedance2.0` y `minimax-h3` (`plan.py`, `CAPSULE_ENGINES`). Eso es de pago en cuanto se genera. No está clonado en esta VM.
5. **Mapa de capacidades** (`rea_video/capabilities/models/*.yaml`, `routing.yaml`). Es un catálogo para elegir ruta de remake (vídeo, imagen, audio, 3D, análisis, render). No hay cliente de Kling, Veo, Runway, Luma, Sora, Suno, MiniMax, ElevenLabs, ByteDance, etc. Los campos `cost` son notas para el plan, no tarifas que este proceso cobre. `python3 scripts/validate_capabilities.py --matrix` solo valida el YAML.

Proveedores que aparecen en el catálogo (ninguno se invocó): Google, ByteDance / Seed, Twelve Labs, Alibaba, Kuaishou, MiniMax, OpenAI, Black Forest Labs, Lightricks, Sync Labs, FASHN, Shengshu, PixVerse, Tencent, Runway, Luma, Hyper3D, Tripo, Topaz, Suno, ElevenLabs, más entradas de código abierto (Remotion, Blender, ffmpeg, Demucs, WhisperX, FunASR, PaddleOCR, SAM, YuNet/OpenCV, UVR). Varios de análisis (`pyscenedetect`, `transnetv2`, `demucs`, `whisperx`) están en el mapa y **no** son el implementador real: los cortes los hace `shots.py`, los stems `stems.py`.

## Higgsfield y ElevenLabs

Comprobado en el árbol, no asumido.

- **Higgsfield.** La única mención es `rea_video/capabilities/README.md`: «尚未收录» (aún no incluido), junto a HeyGen, Pika y otros. Cero coincidencias en `*.py`, cero URL, cero variable de entorno. No hay integración nativa.
- **ElevenLabs.** Dos fichas de catálogo, nada más: `elevenlabs-v3` (TTS y clonación, `audio.yaml`, nota de coste ~100 USD por millón de caracteres) y `elevenlabs-sfx` (efectos, máximo 30 s). `routing.yaml` los pone en `prefer` de A01 (narración; la nota dice que el inglés emotivo prioriza ElevenLabs) y A04 (efectos, detrás de HunyuanVideo-Foley). `MATRIX.md` repite esas fichas. `grep` en `rea_video/**/*.py` no encuentra el nombre. No hay SDK, host `api.elevenlabs.io`, ni clave. Una ficha en el mapa no llama al servicio.

## NOTICE y Apache-2.0

`NOTICE` dice:

```text
rea-video
Copyright 2026 JuneYaooo

Licensed under the Apache License, Version 2.0.
```

Obligaciones prácticas al redistribuir este fork (Apache-2.0, secciones 4(a)–4(d)):

- Conservar el texto de la licencia y los avisos de copyright que ya van en los fuentes.
- Marcar los ficheros que se cambien.
- Si se distribuye el trabajo, incluir una copia legible de las atribuciones de `NOTICE`. Este documento no sustituye a `NOTICE`.
- El apéndice de `LICENSE` atribuye el copyright 2026 a JuneYaooo. Los dos ficheros añadidos aquí (este doc y el script) son trabajo encima de ese upstream; no retiran esa atribución.
- No se vendió garantía ni se usó la marca del autor para otra cosa.

## Dónde enchufar Higgsfield y ElevenLabs (diseño, sin código)

El análisis (`decompose`) tiene que seguir pudiendo correr sin claves. Un adaptador nuevo no debería vivir dentro de `pipeline.py` ni de `vlm.py`.

1. **Catálogo.** Higgsfield entraría como fichas en `rea_video/capabilities/models/video.yaml` (el README ya señala el hueco). ElevenLabs ya tiene ficha; no hace falta otra para que el plan lo nombre. Añadir un `id` a `routing.yaml` `prefer` solo cambia el texto del plan de remake. Sigue sin haber HTTP.
2. **Ejecutor, al lado de capsule-cinema.** `plan.py` marca los planos generativos con `executor: capsule_cinema`. `cli.py` → `integrations/run_remake.py` es el único sitio que hoy dispara generación, y solo si existe el checkout externo. Un adaptador propio sería otro executor, por ejemplo `rea_video/integrations/higgsfield.py` y `rea_video/integrations/elevenlabs.py`, elegido por el campo `executor` del job. Lectura de clave solo ahí (`HIGGSFIELD_API_KEY`, `ELEVENLABS_API_KEY`, o `--env-file`). Sin la clave, el comando sale con un error y no intenta la red. Un `--dry-run` imprime el payload y vuelve, igual que `remake-run --dry-run`.
3. **No reutilizar el cliente VLM.** `VLMConfig` habla chat completions para juzgar planos. Higgsfield genera vídeo; ElevenLabs sintetiza voz o efectos. Mezclarlos en `REA_VLM_*` cobraría en el paso de análisis y mezclaría dos contratos distintos.
4. **Audio, después de los stems.** El tiempo del efecto y de la voz ya sale en `breakdown.json` (`audio.sfx.events`, `stems/vocals.wav`). Un adaptador de ElevenLabs consumiría esa línea de tiempo (rutas A01 y A04), no sustituiría a UVR.
5. **Puerta de la CLI.** El flag nuevo colgaría de `remake-run` (o de un subcomando hermano), nunca de `decompose`. Así `scripts/smoke_offline.sh` sigue siendo la prueba de que el camino gratis no se rompió.
