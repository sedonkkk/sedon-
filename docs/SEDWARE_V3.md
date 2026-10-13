# SEDWARE V3 — Performance & Tracking

V3 conserva la GUI Pink Edition y el proyecto existente. Esta entrega es una **versión candidata**, comprobada con Luau CLI y dobles explícitos de APIs. La ejecución de Roblox Studio, la apariencia del ESP y la física real siguen pendientes. No se ha verificado en Da Hood.

## Diagnóstico y correcciones

| Área | Evidencia verificable | Cambio |
|---|---|---|
| Prediction X/Y | V2 validaba 0..0.6 e interpretaba los valores como segundos; 13.15 se rechazaba. | Escala visible independiente con una única calibración explícita. |
| Fly / Speed | `MovementAccess.allowed` rechazaba la activación sin declaración o atributos de autorización. Era una restricción intencional. | Estado N/A visible y protocolo propio de servidor para experiencias autorizadas. Se conserva el bloqueo en terceros sin autorización. |
| ESP vacío | `ESP=true` con ambas subopciones en false no crea indicadores. Username, distancia, profundidad y raycast también pueden rechazar todos los candidatos. | La GUI explica la dependencia y los diagnósticos cuentan cada rechazo. |
| Caja visual | V2 asociaba SelectionBox al Model completo. No hay captura del renderizador que permita atribuirle el fallo observado por el usuario. | Adornee BasePart concreto: HumanoidRootPart. Es una caja visual de referencia, no la caja de colisión ni el contorno completo del cuerpo. Verificación visual nativa pendiente. |
| Names | Dependía del mismo filtro que las cajas. | Head válido, fallback RootPart, etiqueta 180×28 / 14 px y reaplicación del Adornee tras respawn. |
| Seguimiento | Config/settings se sincronizaban en cada predicción y se creaba un registro de objetivo cada frame. Ediciones de ESP reiniciaban la política automática. | Settings se sincroniza al editar; se reutiliza el registro bloqueado y las ediciones ajenas a predicción conservan el slew. |
| Caché | Sustituir repetidamente Humanoid dejaba conexiones desconectadas acumuladas en la lista de limpieza del personaje. | La conexión de muerte se sustituye y elimina explícitamente. |

No se conoce todavía la causa gráfica exacta del ESP ausente en el cliente del usuario. Los contadores nuevos permiten identificar si el fallo ocurre antes de crear indicadores, al activar sus propiedades o dentro de una API. Crear instancias y activar `Visible`/`Enabled` no prueba que los píxeles aparezcan.

## Calibración visible

```lua
PredictionX = 13.15,
PredictionY = 13.15,
ReferenceScale = 13.15,
ReferenceHorizontalSeconds = 0.1205,
ReferenceVerticalSeconds = 0.0800,
MinScale = 0,
MaxScale = 100,
```

La fórmula provisional de Sedware es:

```
horizontal = PredictionX × ReferenceHorizontalSeconds / ReferenceScale
vertical   = PredictionY × ReferenceVerticalSeconds   / ReferenceScale
```

| Escala | Horizonte X | Horizonte Y |
|---|---:|---:|
| 13.15 | 0.120500 s | 0.080000 s |
| 14.20 | 0.130122 s | 0.086388 s |

Editar X conserva Y. Config valida números finitos y la escala aceptada; los límites físicos `MinPredictionX/Y` y `MaxPredictionX/Y` continúan expresados en **segundos** (0..0.35 inicialmente). El horizonte se limita sin sobrescribir la escala del usuario; `calibrationClamped` informa esta situación. Con un límite alcanzado, aumentar la escala no añade más horizonte. La GUI muestra dos decimales.

Esto es una escala nueva, **no una equivalencia demostrada con el script antiguo**. Un ajuste lineal reproduce exactamente el punto de referencia y resulta identificable; sin observaciones de error no hay evidencia para justificar una conversión no lineal. El laboratorio puede utilizarse para ajustar las referencias físicas, manteniendo la fórmula explícita.

Auto Prediction utiliza `PingReferences` en segundos totales; su curva sustituye al horizonte manual, no se multiplica por la escala ni se suma otra vez RTT/2. El filtro de ping conserva la EMA temporal. La documentación oficial de `Player:GetNetworkPing()` lo define como RTT aislado en segundos. RTT, RTT suavizado y horizonte son cantidades distintas: no se infiere la antigüedad de una posición de personaje a partir del RTT.

En una sesión publicada, `ageSource="LocalReadTime"` y `captureTimeKnown=false`: se conoce cuánto tiempo ha pasado desde la lectura local, pero no cuándo capturó esa posición el servidor. `observationDelaySeconds=nil`. En el laboratorio sí se conoce el timestamp sintético de captura y se integra su edad una sola vez.

## Movimiento en una experiencia propia

Instala [`src/cam_server/MovementServer.server.luau`](../src/cam_server/MovementServer.server.luau) como Script en ServerScriptService. El proyecto Rojo y el demo `.rbxlx` ya lo incluyen. Su función `grant(player)` autoriza a los jugadores de **esa experiencia propia**; adapta esa función a tu política de acceso antes de integrarla en otro proyecto.

El servidor anuncia `SEDWAREMovementProtocolVersion=1` y crea exclusivamente sus propios `SEDWAREMovementControl` (RemoteFunction) y `SEDWAREMovementInput` (RemoteEvent). El cliente no busca remotes de armas ni intercepta comunicaciones de terceros.

- El cliente envía configuración en una tarea separada; `InvokeServer` nunca bloquea el callback de render. Hay estado de espera, respuesta, rechazo y timeout de 3 s; el timeout no anuncia activación.
- El servidor valida autorización, tipos, números finitos, FlySpeed 1..200, WalkSpeed 1..100, FlyMaxForce 1000..10000000, frecuencia y token de sesión. El token separa sesiones; no sustituye a la autorización.
- Fly crea Attachment + LinearVelocity **en el servidor**. El servidor toma la propiedad de red del RootPart, recibe un vector limitado a la velocidad autorizada a 10 Hz y aplica la física. El cliente no crea una segunda restricción.
- Speed asigna WalkSpeed desde el servidor. Fly suspende el Speed aplicado conservando su preferencia. Al desactivar se restaura el valor anterior; no se combate un valor posterior que haya impuesto otro controlador.
- El servidor publica medidas de `AssemblyLinearVelocity` horizontal y vertical a 5 Hz. Son observaciones físicas, separadas de la confirmación de configuración. El protocolo no es un anticheat general ni verifica que cualquier desplazamiento arbitrario sea legítimo.
- Caducidad sin input válido: 0.8 s. Muerte, salida, revocación y descarga restauran estados, restricciones y propiedad de red previa (automática por defecto). El cliente conserva preferencias y solicita autorización/aplicación para el nuevo personaje tras respawn.

Valores iniciales: V / 65 para Fly, G / 24 para Speed, Space para subir y LeftControl para bajar. Las teclas se normalizan y comprueban conflictos; C conserva selección/liberación del objetivo. No se crean conexiones de input adicionales por respawn.

`MovementAuthorized=true` conserva la ruta local para una integración explícitamente autorizada, pero **no instala un servidor, no concede permisos del juego ni garantiza replicación**. La GUI la identifica como modo local no verificado. En Da Hood original no puedes instalar este componente propio: Fly/Speed quedan N/A cuando falta autorización. No se elimina la restricción para hacer que los botones aparenten funcionar.

## ESP y coste

Defaults: `ESP=false`, `Hitboxes=false`, `Names=false`, `ESPUpdateHz=10`, `ESPMaxDistance=350`, `ESPLowPerformanceMode=true`, `ESPOcclusionMode="VisibleOnly"`.

Activa ESP **y** Hitboxes o Names. En All se consideran otros jugadores; Specific Player requiere Username real y Apply. Clear elimina la selección específica; All vuelve a permitir todos. La búsqueda exacta, sin distinguir mayúsculas, usa el índice cacheado al aplicar; no busca nombres cada frame ni utiliza DisplayName.

PlayerRegistry enumera una vez y se actualiza con eventos. Se omiten personajes muertos, incompletos, fuera de alcance, detrás de cámara, fuera de pantalla u ocluidos. El raycast ocurre después de filtros baratos. SelectionBox y BillboardGui se reutilizan y se destruyen al desactivar o eliminar al jugador. Names usa AlwaysOnTop=false; no se fuerza visión a través de paredes. Los toggles no cambian Size, colisiones ni propiedades físicas de personajes.

Diagnósticos (máximo 2 Hz): registrados, evaluados, en rango, en pantalla, rechazados por oclusión/personaje/distancia, visibles, indicadores activos/creados, raycasts y tiempos de CPU. Un fallo de render registra el error, limpia el ESP y deja funcionando la cámara y la GUI.

`DebugMode=true` añade marcadores MicroProfiler `SEDWARE ESP`; el runner nativo también marca el laboratorio. El ESP comparte la actualización central, después de la cámara, pero se limita por Hz. No hay RenderStepped por jugador. Una tarea visual todavía consume parte del presupuesto del frame: no se promete impacto cero.

## Controladores y filtros experimentales

`TrackingMode="Fixed"` permanece por defecto, con la misma respuesta yaw/pitch de V2: τ = 0.12 × Smoothness² y α = 1 − exp(−dt/τ). Todas las variantes reconstruyen la base nivelada con CFrame.fromMatrix; conservan la protección polar, posición viva y CameraSubject/Type/Focus.

`Adaptive` utiliza el error yaw/pitch para cambiar τ suavemente: `g=error/(error+AdaptiveErrorDegrees)`, τ deseado = `(Smoothness/.405)² × (maxTau+(minTau-maxTau)×g)`, limitado a [minTau,maxTau]. Una EMA temporal suaviza el cambio de ganancia. Defaults .008..06 s, escala de error 8°, ganancia .08 s. No se apila otro filtro de posición.

`Critical` integra la solución cerrada de `x''+2ωx'+ω²x=0` para cada setpoint angular constante. `CriticalFrequency` representa ω en s⁻¹, **no ciclos por segundo**; ω efectivo = `CriticalFrequency × .405 / max(Smoothness,.001)`. Defaults: 18 s⁻¹, velocidad máxima 720°/s y aceleración máxima 4000°/s². La saturación y la protección de sobrepaso introducen no linealidad; se miden, no se supone invariancia exacta con FPS cuando actúan los límites.

`MotionFilter="Memory"` conserva el historial y la EMA original de velocidad. Las alternativas opcionales son AlphaBeta y OneEuro. AlphaBeta corrige posición predicha y velocidad con ganancias α/β; OneEuro es un prototipo inspirado en el filtro de Casiez et al., con cutoff adaptativo y discretización exponencial (no una implementación idéntica del filtro RC del artículo). Ambas reinician estado ante saltos de estado, cambios de dirección, gaps y teletransporte. Se mantiene el rechazo de muestras inválidas/obsoletas; aceleración sigue desactivada por defecto.

`SmartSelection=true` es opcional: adquisición mantiene Radius estricto; el objetivo bloqueado tiene una zona de liberación Radius×1.3 y gracia de .2 s para salida de pantalla/oclusión. Durante la gracia se pausa la cámara, en lugar de seguir a través del obstáculo. Después se libera; muerte, cambio de personaje/parte y MaxDistance liberan inmediatamente. Nunca se sustituye al objetivo válido por un jugador más próximo.

## Calibration Lab y resultados

Ejecuta:

```bash
python3 scripts/check_cam.py
python3 scripts/calibrate_cam.py
python3 scripts/check.py
python3 scripts/check_pink.py
```

El laboratorio compara el controlador **V2 real archivado del commit 43612248fc40e2750678873acda642ab41f85c35** con Adaptive/Critical. Usa los mismos horizontes físicos y trayectorias: caminar, correr, saltar, caer, invertir dirección, círculo, parada, distancia larga y escalón angular. Cruza 30/60/120/144 FPS programados, RTT 0/60/120 ms, tres filtros y Manual/Auto: **1944 escenarios sintéticos**. No son 1944 pruebas de Roblox.

Exporta error angular medio/máximo respecto a posición actual y respecto al setpoint predicho, adquisición a <1° del setpoint, tiempo dentro de ese umbral, error de predicción contra futuro analítico X/Z/Y, roll, cambios de signo, sobrepaso tras parada y lag lateral firmado. Lag negativo significa adelanto por predicción. Cambios de signo pueden provenir de ruido/adelanto; no son por sí solos prueba de oscilación de control. Usa edad de captura conocida solo en el experimento. No simula impactos.

Los CSV reproducibles y la tabla comparativa se encuentran en [`SEDWARE_V3_RESULTS.md`](SEDWARE_V3_RESULTS.md). La adquisición se mide en la resolución del FPS programado; el error inicial incluye un giro de cámara de 45°. Las medidas angulares respecto al objetivo actual pueden mejorar simplemente por cancelar adelanto intencional: deben leerse junto al error del setpoint y de predicción.

Resultado práctico: **no hay una técnica universalmente superior**. Adaptive mejora el escalón de adquisición en algunos FPS, pero aumenta el error medio respecto al setpoint móvil. Critical, con estos límites, adquiere más lentamente. OneEuro reduce algunas variaciones y aumenta el error de predicción. Fixed + Memory sigue siendo el valor predeterminado. Las mediciones de CPU con dobles muestran coste añadido por diagnósticos/estado en algunas condiciones; no demuestran una mejora de FPS nativos.

## Verificación real pendiente

Abre [`studio/SedwareCamV3Test.rbxlx`](../studio/SedwareCamV3Test.rbxlx) en Roblox Studio y pulsa Play. El runner contiene el cliente actual y el componente de servidor propio. Prueba GUI, enums de keybind, confirmación de servidor, desplazamiento real con Speed, velocidad vertical real con Fly, mediciones físicas observadas por servidor, restauración, respawns, indicadores y benchmarks con 5/15/30 personajes sintéticos. Compara FPS ON/OFF usando RenderStepped real. Los personajes ESP de benchmark son modelos de prueba; no cuentas reales.

El runner no se ejecutó en este entorno Linux. Los checks de instancias/propiedades de ESP no sustituyen la revisión visual: confirma que se ven las cajas rosadas y nombres, que desaparecen detrás de obstáculos/fuera de rango y que reaparecen tras respawn. Prueba también teclas físicas C/V/G, captura, minimizar y arrastrar después de morir. Usa Test → Start Server con dos clientes para probar el registro de jugadores y la selección real entre clientes. Guarda Output y captura MicroProfiler; no marques como verificados los checks pendientes.

Activa `DebugMode=true` en el header para investigar. Los logs distinguen `Movement`, `ESP DIAGNOSTIC`, `Tracking DIAGNOSTIC` y fallos de inicialización. MAIN/MISC y notificaciones mantienen su identidad; no hay nuevas pestañas. El logo original sigue pendiente de asset ID: se conserva LogoAssetId y el fallback temporal, sin inventar un recurso.

Da Hood original conserva su sistema de armas y validaciones. No hay integración con su Revolver ni remotes protegidos; no se atribuyen verificaciones de Studio al juego original. `PinkDotLock.lua` y `DaHoodPrediction.lua` conservan sus bytes.

## Referencias

- [Roblox Player:GetNetworkPing — documentación oficial](https://create.roblox.com/docs/reference/engine/classes/Player#GetNetworkPing): RTT aislado, lectura del LocalPlayer en cliente; consultada durante esta auditoría.
- [Roblox SelectionBox](https://create.roblox.com/docs/reference/engine/classes/SelectionBox), [BillboardGui](https://create.roblox.com/docs/reference/engine/classes/BillboardGui), [LinearVelocity](https://create.roblox.com/docs/reference/engine/classes/LinearVelocity), [MicroProfiler](https://create.roblox.com/docs/studio/microprofiler).
- [Casiez, Roussel, Vogel: 1€ Filter](https://gerycasiez.github.io/1euro/), CHI 2012, DOI [10.1145/2207676.2208639](https://doi.org/10.1145/2207676.2208639).
- EMA y amortiguación crítica se justifican por las ecuaciones explícitas anteriores; la comparación mide las variantes implementadas, no un controlador abstracto ideal.

## Publicación verificada

Código: commit [`7eeb3d1`](https://github.com/sedonkkk/sedon-/commit/7eeb3d1ce54a59b9fda2c56ab76a80cf79881c9a). HTTP 200 y bytes Raw idénticos al archivo local: 208746 bytes, SHA256 `44a7b9288a17e0ccc7daee89f6b865de3170ce3a21600340313c22e1e3831fe1`. El loader usa este commit nuevo; no reutiliza el de V2.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/sedonkkk/sedon-/7eeb3d1ce54a59b9fda2c56ab76a80cf79881c9a/SedwareCamLock.lua"))()
```

Requiere un host con `game:HttpGet` y `loadstring`; no es un cargador estándar de LocalScript en un cliente publicado. En tu experiencia propia usa el LocalScript incluido en el demo/Rojo, sin ese loader externo. En un host sin estas APIs, CamLoader.lua informa el error. Todo el código cliente está en el payload; el componente de servidor se instala por separado en la experiencia propia.

Para conservar un handle y limpiar la sesión, asigna el resultado a una variable y llama a `sedware.Unload()`:

```lua
local sedware = loadstring(game:HttpGet("https://raw.githubusercontent.com/sedonkkk/sedon-/7eeb3d1ce54a59b9fda2c56ab76a80cf79881c9a/SedwareCamLock.lua"))()
-- Cuando quieras terminar:
sedware.Unload()
```

Descargas Raw verificadas (mismo commit): [script](https://raw.githubusercontent.com/sedonkkk/sedon-/7eeb3d1ce54a59b9fda2c56ab76a80cf79881c9a/SedwareCamLock.lua), [demo propio](https://raw.githubusercontent.com/sedonkkk/sedon-/7eeb3d1ce54a59b9fda2c56ab76a80cf79881c9a/studio/SedwareCamLock.rbxlx), [runner V3](https://raw.githubusercontent.com/sedonkkk/sedon-/7eeb3d1ce54a59b9fda2c56ab76a80cf79881c9a/studio/SedwareCamV3Test.rbxlx), [runner de roll](https://raw.githubusercontent.com/sedonkkk/sedon-/7eeb3d1ce54a59b9fda2c56ab76a80cf79881c9a/studio/SedwareCamRollTest.rbxlx). En GitHub puedes abrir el archivo → Raw; conserva el commit en la URL para fijar esta versión.
