# SEDWARE V3.1 — PINK EDITION

Actualización del proyecto existente, basada en el código, observaciones del usuario y comparación reproducible contra V3. Conserva la GUI y la escala 13.xx. No modifica `PinkDotLock.lua`, `DaHoodPrediction.lua`, armas ni comunicaciones protegidas de Da Hood.

Estado de entrega: código, regresiones CLI/dobles y comparaciones ejecutados; **Roblox Studio, física/render/FPS nativos y Da Hood no verificados**. Se incluye un runner nativo preparado. No se atribuyen disparos fallidos únicamente a la cámara ni se anuncia una corrección del sistema de armas.

Código publicado en el commit [`da44a4c7af3857c1fed22b9fb757c012180650ac`](https://github.com/sedonkkk/sedon-/commit/da44a4c7af3857c1fed22b9fb757c012180650ac). El [Raw nuevo](https://raw.githubusercontent.com/sedonkkk/sedon-/da44a4c7af3857c1fed22b9fb757c012180650ac/SedwareCamLock.lua) devolvió HTTP 200 y coincidió byte por byte con los 230147 bytes probados. CamLoader.lua utiliza ese commit; los cargadores anteriores no reciben esta actualización.

## Uso

El archivo autónomo es [`SedwareCamLock.lua`](../SedwareCamLock.lua); el cargador verificado y fijado al nuevo commit se publica en el [README](../README.md). Al iniciar aparece el menú. Activa Enable en MAIN y pulsa C para seleccionar o liberar; primera persona usa el centro y tercera persona el cursor. Edita Config al principio del script para los parámetros de seguimiento, movimiento y ESP. El modo de movimiento y el alcance extendido se eligen desde esa configuración; la interfaz existente conserva sus controles.

En una experiencia propia de Studio, coloca el archivo como LocalScript en StarterPlayerScripts, o abre el lugar de prueba incluido. El ejemplo con `game:HttpGet` y `loadstring` depende de que el host proporcione esas funciones; no sustituye la instalación normal en Studio. Fly/Speed de servidor necesitan nuestro componente propio, no solo el archivo de cliente. No utilices un cargador fijado a V3 esperando que ejecute V3.1.

## Causas verificables y cambios

| Área | Causa de código | Corrección |
|---|---|---|
| Saltos | Extrapolación Y de velocidad por horizonte+edad, sin política propia para ápice/aterrizaje. | `VerticalControl` clasifica fases y limita horizonte, velocidad usada y desplazamiento predicho. |
| Correcciones bruscas | Fixed/Adaptive no limitaban específicamente pitch en estados de riesgo. | Límites explícitos de velocidad y slew del comando pitch para aire, proximidad y reversals; misma base yaw/pitch sin roll. |
| Reversals | El cambio inmediato de velocidad puede invertir el adelanto; filtros experimentales usaban un producto escalar 3D que podía ocultar reversión lateral durante salto. | Detección horizontal independiente, reducción temporal explícita del horizonte X/Z y recuperación en .08 s. |
| Pérdida aparente | Pausa por predicción/controlador y eliminación del bloqueo no tenían estados claramente separados. | Diagnósticos `TRACKING`, `PAUSED`, `LOST`, `IDLE`, `SEARCHING`, `DISABLED` y motivo de última pérdida. |
| Hit Part temporal | Eliminar brevemente la parte liberaba inmediatamente el objetivo. | Gracia acotada y reanudación del mismo jugador con reinicio del historial de parte. |
| Origen de cámara inválido | Si el origen no era finito y faltaba también la parte local de respaldo, se clasificaba como pérdida del personaje objetivo. | Pausa `CAMERA_ORIGIN_UNAVAILABLE` y reanudación del mismo objetivo al recuperar el origen. Es un caso defensivo distinto de CurrentCamera temporalmente ausente. |
| Fly/Speed | La misma puerta de permiso cubría pruebas locales y protocolo de servidor. | Rutas Local/Server/Auto explícitas y estados de aplicación/física separados. |
| Speed | `active=true` podía permanecer tras una sobrescritura externa de WalkSpeed. | Detecta limitación y deja intacto el valor impuesto externamente. |
| Servidor tardío | Podía comenzar la ruta servidor antes de limpiar Fly/Speed locales. | Limpieza/restauración previa, incluso antes del primer frame; servidor captura la velocidad original correcta. |
| ESP | Alcance inicial 350, un solo modo y frecuencia uniforme de comprobaciones. | Alcance configurado, Unlimited solo para datos cargados en contexto autorizado, modo AlwaysOnTop autorizado y frecuencia lejana reducida. |
| Permiso ESP revocado | Rechazo de cualquier edición impedía desactivar/restablecer combinaciones de opciones. | Se valida entrar/activar modo extendido; se permite desactivar, restablecer y editar cámara sin congelar la GUI. |
| Usuario ESP específico | Reconstruir el manager podía sustituir selección aplicada por texto nuevo todavía sin Apply. | Conserva la selección aplicada durante cambio de modo. |
| Versión | UI contenía `"v2"` literal aunque Branding.Version indicaba v3. | Título `SEDWARE V3.1`, badge `v3.1` desde Branding; misma identidad visual. |

Las observaciones del usuario orientan el problema. Los cambios no demuestran la causa exacta de cada fallo observado en Da Hood. La [auditoría de video disponible](SEDWARE_V31_VIDEO_AUDIT.md) permanece como evidencia histórica; los videos restantes ya no son un requisito, por instrucción posterior del usuario.

## Prediction X/Y y control vertical

Se mantienen:

```lua
PredictionX = 13.15,
PredictionY = 13.15,
ReferenceScale = 13.15,
ReferenceHorizontalSeconds = 0.1205,
ReferenceVerticalSeconds = 0.0800,
```

Conversión única: X×.1205/13.15 y Y×.0800/13.15. 14.20 corresponde a .130122 s horizontal y .086388 s vertical antes de límites. Es una calibración provisional propia de Sedware, no una equivalencia demostrada con otro script. No se escriben nuevos valores visibles automáticamente.

`VerticalControl=true` usa estado Jumping/Freefall/Landed y velocidad de posiciones aceptadas para estimar Grounded, Rising, Apex, Falling y Landing. **Son estimaciones**, no una prueba del estado físico exacto del servidor. Grounded conserva la política existente; Rising limita el horizonte Y a .055 s, Falling a .045 s, Apex a .025 s y Landing lo reduce a cero durante .10 s. Todos son editables. Prediction Y=0 continúa suprimiendo su adelanto solicitado.

La velocidad vertical usada se limita a ±85 studs/s. Cambios anómalos dentro de la misma fase limitan la variación a 450 studs/s²; cambios reales de fase reinician esa continuidad. No se ajusta una parábola ni se supone gravedad, aceleración o momento de salto exactos. Teleports/gaps reinician estimador e historial; muestras inválidas/obsoletas no se convierten en una posición inventada.

El desplazamiento Y **total predicho** en aire/aterrizaje, incluyendo edad local, se limita a ±2.25 studs respecto a la posición observada. `verticalHorizonUsed`, `verticalVelocityUsed`, `verticalTotalLeadSeconds`, `verticalLeadLimited` y `movementPhase` informan la política efectiva. Esto puede sacrificar precisión en caída o red alta: los resultados muestran esa compensación.

En aire la política vertical sustituye el filtro de salida Y previo, evitando apilar dos filtros de posición. X/Z conserva su filtrado salvo la ventana explícita de inversión. La aceleración de predicción sigue desactivada por defecto. Puede compararse la política anterior con `VerticalControl=false`, y la inversión anterior con `ReversalDamping=false`.

`ReversalDamping=true`: horizonte horizontal efectivo empieza en `ReversalScale=.5` tras una inversión válida y recupera el horizonte solicitado linealmente durante `ReversalWindow=.08`. El factor y el horizonte usado aparecen en diagnósticos. No se ocultan multiplicadores ni se cambia la escala visible.

## Cámara y persistencia

Se conserva Fixed por defecto. Adaptive y Critical siguen disponibles como experimentos. Smoothness mantiene la respuesta temporal del controlador; no se elige Adaptive por su nombre. Yaw/pitch siguen separados, se reconstruye la base con CFrame.fromMatrix y referencia Y global, se preserva posición viva, CameraType/Subject/Focus y protección polar de V3.

`AngularSafety=true` limita yaw a AngularMaxSpeed (720°/s inicialmente) y pitch a PitchMaxSpeed (180°/s), con PitchMaxAcceleration=1200°/s² para el slew del comando mientras hay aire, inversión o distancia inferior a CloseSafetyDistance=8. Los límites pueden activarse incluso con Smoothness=0. No se recorta el mundo a una falsa orientación fija: un objetivo realmente encima/debajo puede seguirse hasta el polo con respuesta limitada.

La llegada al setpoint, protección contra sobrepaso y entrada/salida de las guardias pueden interrumpir el slew. **No se promete un máximo global de aceleración de 1200°/s²**; el laboratorio registra la aceleración resultante incluyendo esos eventos. Los límites de orientación son decisiones explícitas de control y se distinguen del roll, que debe permanecer próximo a cero.

`TargetPartGraceSeconds=.15` pausa si desaparece temporalmente la parte de un personaje válido. Si reaparece una parte válida del mismo jugador/personaje, se conserva el jugador y se reinicia el stream de posición; si no, se libera con motivo específico. Muerte, salida, cambio de personaje y MaxDistance no prolongan un objetivo inexistente.

`SmartSelection=false` permanece por compatibilidad. Al activarlo, la adquisición exige Radius y se mantienen la zona de liberación Radius×ReleaseRadiusMultiplier (1.3) y gracia .2 s para salida de pantalla/oclusión. Durante esa gracia se pausa; después se libera. No cambia a un jugador más cercano mientras exista un bloqueo válido.

`ReacquireOnLoss=false` evita seleccionar automáticamente a otro jugador después de una pérdida real. C solicita nueva adquisición. Puede habilitarse la política anterior explícitamente. Desbloqueo manual no se presenta como muerte o salida. `GetTrackingDiagnostics()` informa si el registro continúa bloqueado, estado actual, pausa y última pérdida (`PLAYER_LEFT`, `TARGET_DEAD`, `CHARACTER_CHANGED`, `HIT_PART_UNAVAILABLE`, `OUT_OF_RANGE`, etc.).

## Ping variable

Se probaron RTT 60/100/150/300 ms y perfiles con picos. Auto conserva la EMA PingSmoothing=.8 s y el slew del horizonte, sin sumar RTT otra vez. La curva empírica inicial 55/62/70 ms continúa sin inventar calibraciones nuevas a 100–300 ms: fuera de la curva se usa el extremo, no una extrapolación ilimitada. Que la red suba a 300 ms no garantiza que esa curva sea precisa.

RTT actual, RTT suavizado, horizonte, edad desde lectura local y retraso de captura se distinguen. En sesión, el tiempo original de captura del servidor continúa desconocido; `captureTimeKnown=false`, `ageSource="LocalReadTime"`. En la comparación la trayectoria retrasada es conocida solo por el simulador y no se proporciona ese conocimiento al estimador. No se asume que RTT/2 sea la antigüedad real de la posición publicada.

## Fly/Speed: Local y Server

```lua
MovementMode = "Auto", -- "Local" / "Server" también disponibles
LocalMovementAllowed = false,
MovementAuthorized = false, -- alias de integración autorizada anterior
```

- **Local:** no utiliza el bridge para aplicar movimiento. Se permite en Studio o con declaración explícita de entorno permitido (`LocalMovementAllowed=true`, alias autorizado o atributo propio). Esa declaración no concede derechos en un juego ajeno. Crea únicamente sus propias Attachment/LinearVelocity, usa cámara+WASD/Space/LeftControl, FlySpeed/FlySmoothing, restaura flags/estado y elimina recursos al cerrar/morir. Speed escribe WalkSpeed al entrar/cambiar configuración/personaje y no combate una sobrescritura externa.
- **Server:** exige el componente propio `src/cam_server/MovementServer.server.luau` y el permiso del Player. Conserva validación, límites, caducidad, propiedad de red, medidas físicas de servidor y restauración de V3. El cliente no duplica restricciones.
- **Auto:** utiliza el servidor propio anunciado si está disponible; en otro caso permite solo la prueba local autorizada. La detección tardía limpia el controlador local y restaura WalkSpeed antes de pedir aplicación servidor. Para cambiar Mode manualmente, desactiva Fly y Speed primero.

La ausencia de bridge ya no impide **una prueba local permitida**. Por defecto, un cliente de un juego de terceros no se considera un entorno autorizado. No se activa Fly/Speed en Da Hood eliminando sus permisos. La configuración local no garantiza replicación, estabilidad frente al servidor ni aceptación de la experiencia.

Estados de GUI: OFF, LOCAL ONLY (instalado/idle/no confirmado), LOCAL ACTIVE (velocidad física local observada en la dirección solicitada), SERVER AUTHORIZED (configuración aplicada por nuestro servidor), SERVER LIMITED (propiedad cambiada externamente, rechazo/timeout o movimiento solicitado no observado), UNAVAILABLE y ERROR. La causa de una ausencia de movimiento no se atribuye automáticamente al anticheat: puede ser física, propiedad de red o otra restricción, y se marca como no confirmada.

`GetMovementDiagnostics()` separa `requested`, `controllerActive`, `effective`, ruta, permiso, estado del personaje y motivo. Un RootPart anclado, personaje muerto, permiso revocado, servidor no disponible o API fallida no anuncia ACTIVE. El estado SERVER AUTHORIZED no sustituye a una medida física: el runner comprueba desplazamiento/velocidad y atributos medidos del servidor por separado. Speed se pausa mientras Fly está solicitado conservando su preferencia.

Las teclas V/G son editables y los conflictos tienen motivos concretos. Los errores de movimiento ya no se notifican como un Invalid value genérico. La cola y el cooldown conservan protección contra mensajes repetidos.

## ESP extendido autorizado

```lua
ESPMaxDistance = 350, -- compara 750 y 1500 con personajes cargados
ESPUnlimitedRange = false,
ESPOcclusionMode = "VisibleOnly", -- "AlwaysOnTop" en contexto autorizado
ESPAuthorized = false,
ESPFarDistance = 350,
ESPFarUpdateHz = 3,
```

El alcance finito se configura hasta 2000 studs; Unlimited evita ese límite artificial **solo sobre datos existentes en el cliente**. Unlimited y AlwaysOnTop requieren Studio, declaración de contexto autorizado o atributo propio. No cargan personajes que StreamingEnabled haya excluido ni convierten candidatos sin Character/Root/Humanoid válido en una posición inventada.

VisibleOnly conserva SelectionBox asociado al RootPart, BillboardGui con AlwaysOnTop=false y raycast de obstáculos cargados. AlwaysOnTop combina caja 2D proyectada de RootPart, Highlight del personaje con DepthMode.AlwaysOnTop y BillboardGui.AlwaysOnTop=true. La caja pequeña se mantiene legible con un mínimo visual de 4×6 píxeles; no modifica colisiones/tamaños reales. Solo se consideran proyecciones delante de la cámara. No utiliza remotes de juegos ajenos.

Conserva All, Specific Player, Username real, Apply y Clear. El texto nuevo sin Apply no reemplaza la selección aplicada, ni siquiera tras cambiar modo gráfico. Revocar permiso limpia el ESP; desactivar opciones y volver a VisibleOnly sigue siendo posible.

Registro por eventos, un bucle central, objetos reutilizados y limpieza al salir/desactivar/respawn. Cerca se usa ESPUpdateHz (10 inicialmente); lejos, proyección, visibilidad y sincronización se limitan a 3 Hz. Siempre se comprueban identidad/estado y rango barato; una oclusión/cambio de pantalla lejano puede tardar aproximadamente 1/3 s en reflejarse. AlwaysOnTop evita raycasts. No hay RenderStepped por jugador ni tweens permanentes.

**StreamingEnabled:** el filtro refleja únicamente personajes/obstáculos disponibles. Un raycast del cliente no certifica ausencia de obstáculos que no estén transmitidos. El runner contiene ausencia/retorno de Character como fixture; streaming real requiere el ensayo manual de Studio y no se ha verificado aquí.

### Diseño opcional para posiciones de servidor propio

No hay un servicio de posiciones del servidor de Da Hood ni se supone acceso a él. Para una experiencia propia, un servicio separado puede enviar snapshots a 5 Hz únicamente a usuarios con su ACL autorizada. El paquete diseñado contiene versión, timestamp de captura/servidor y `{UserId, Username, Position, Alive}` obtenidos de personajes reales del servidor. El cliente valida tipos/vectores finitos, limita tamaño y expira datos tras 1 s.

Cuando el avatar esté cargado se usa el indicador normal; cuando solo exista snapshot, se dibuja un marcador claramente rotulado **SERVER SNAPSHOT**, no una hitbox física ni un Character falso. No se emplea ese marcador como Hit Part de Cam Lock. El servidor decide qué posiciones/visibilidad compartir, con datos propios. Esta es una **arquitectura propuesta**, no un componente map-wide implementado/verificado en esta entrega. El ESP publicado sigue utilizando datos cargados reales.

## GUI y pruebas

Panel 420×520, MAIN/MISC, Hot Pink/negro, minimizar, drag, popup separado, scroll, animaciones discretas y notificaciones. Controles existentes y keybinds permanecen tras respawn. Todas las referencias visuales a V2 se eliminan. El logo original sigue pendiente de asset ID; se conserva el recurso preparado y el fallback visible, sin inventar un ID.

```bash
python3 scripts/check_cam.py
python3 scripts/check.py
python3 scripts/check_pink.py
python3 scripts/calibrate_cam_v31.py
python3 scripts/calibrate_persistence_v31.py
python3 scripts/benchmark_cam_v31.py
python3 scripts/benchmark_cam_v31.py --far
```

La nueva comparación independiente del Calibration Lab usa ambos bundles reales (V3 del commit 7eeb3d1 y V3.1), no una fórmula imitadora. Incluye saltos repetidos, aterrizaje, caída, inversión, cerca/lejos, círculo, parada, teleport y ping variable, 30/60/120/144 FPS programados y Manual/Auto. El laboratorio separado de persistencia ejecuta Session con oclusión y ausencia de Hit Part breves/prolongadas, registrando pérdidas y recuperación del mismo jugador. La herramienta heredada `API.Modules.CalibrationLab` se conserva para compatibilidad; la comparación V3/V3.1 actual se ejecuta con los nuevos runners.

Consulta [`SEDWARE_V31_RESULTS.md`](SEDWARE_V31_RESULTS.md) y sus CSV. Las medidas de CPU con dobles no son FPS de Roblox; las pérdidas de adquisición angular y fixtures de oclusión no equivalen a disparos fallidos del juego.

Abre [`studio/SedwareCamV31Test.rbxlx`](../studio/SedwareCamV31Test.rbxlx) y pulsa Play para ejecutar los **23 casos nativos preparados**. Incluye movimiento Local/Server con desplazamiento real, medida servidor, restauración, respawns, cámara y ESP por distancia/modo, escenarios de ausencia de personaje y 5/15/30 modelos. El runner no se ejecutó en Linux. Revisa físicamente C/V/G, drag/minimizar tras morir, cajas/nombres y paredes; usa dos clientes y StreamingEnabled real para la parte no sustituible por fixtures. Guarda Output y MicroProfiler. No marques estas comprobaciones como pasadas hasta ejecutarlas.

DebugMode limita diagnóstico general a 2 Hz y búsqueda sin candidatos a 1 Hz. Tracking informa eje yaw/pitch, estado/última pérdida, parte, fase, horizontes solicitados/usados y RTT; Movement informa solicitud/controlador/física y motivo; ESP informa registrados, considerados, no preparados, rango/pantalla/oclusión, indicadores, raycasts y coste. MicroProfiler conserva `SEDWARE ESP`.

## Límites que permanecen

- No se ejecutó Roblox Studio ni Da Hood; apariencia, física y FPS reales siguen pendientes.
- Los límites verticales reducen excesos en fixtures, pero pueden aumentar retraso en caída/latencia. No hay precisión universal ni balística exacta.
- Los estados de Humanoid/velocidad observados pueden estar retrasados respecto al servidor; el momento de captura no se conoce en un cliente publicado.
- El modo local no concede autorización ni garantiza replicación. El modo servidor requiere instalar nuestro componente en una experiencia que controlemos.
- ESP extendido necesita contexto autorizado y datos cargados; el diseño de snapshots no está implementado.
- No se modificó el sistema de disparo de Da Hood. Medir cámara no confirma impactos ni corrige por sí solo sus balas.
