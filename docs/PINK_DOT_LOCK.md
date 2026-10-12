# PINK DOT LOCK

La versión actual usa la marca **SEDWARE** y corrige el arranque. [Diagnóstico, causas reproducidas y guía de consola](SEDWARE_INITIALIZATION.md).

[Corrección de LockKey en startup v3](SEDWARE_LOCKKEY.md): el valor editable `"C"` y Enum.KeyCode.C se normalizan por pertenencia e identidad, sin comparar el texto de EnumType.

Proyecto independiente de DH PREDICTION LAB: C selecciona un personaje, muestra un DOT Hot Pink sobre su parte actual y C lo libera. No hay menú. El código lee la cámara para proyectar y seleccionar; nunca escribe su CFrame, Focus, CameraSubject ni mueve el mouse o gira al personaje. No modifica el sistema de disparo de Da Hood.

## Archivos y arranque

- `PinkDotLock.lua`: archivo autónomo, con 13 módulos integrados y configuración editable al principio. No requiere otros archivos Lua, HTTP ni APIs de un ejecutor para su lógica.
- `src/pink/`: configuración, detección de cámara, selección, predicción X/Y, overlay, auditoría de APIs, adaptador de disparo y ciclo de vida.
- `src/shared/`: se reutilizan **sin cambios** Settings, MotionHistory, Latency y Ballistics de DH PREDICTION LAB.
- `src/pink_demo/`: cliente y servidor opcionales del disparo propio de prueba. Estos scripts funcionan exclusivamente en Studio.

En una experiencia propia, copia `PinkDotLock.lua` a un **LocalScript de StarterPlayerScripts** y usa Play. También puedes generar los lugares completos:

```sh
python3 scripts/build_pink.py
```

`build/PinkDotLock.rbxlx` incluye el único LocalScript y el escenario básico. `build/PinkDotLockTest.rbxlx` incluye además el adaptador de disparo propio. Su XML preserva las fuentes exactamente; abrirlos y probar el motor en Studio está pendiente.

También se incluyen las mismas copias listas para abrir en [`studio/PinkDotLock.rbxlx`](../studio/PinkDotLock.rbxlx) y [`studio/PinkDotLockTest.rbxlx`](../studio/PinkDotLockTest.rbxlx), para descargarlas desde GitHub sin instalar el compilador ni Python.

Después de comprobar reloj, viewport, entrada, servicios e inicializar recursos aparece abajo al centro **SEDWARE — Successfully Loaded | Press C to Lock**, durante 4 segundos. Locked, Unlocked y Target Lost usan el mismo aviso compacto durante 2 segundos. C sin candidatos muestra **SEDWARE — No valid target**. Una sola notificación reutilizada evita acumulación. Las APIs ausentes o los fallos críticos impiden anunciar éxito y generan un informe en consola; si quedan disponibles las APIs de GUI, aparece **SEDWARE | Load Failed** con la explicación durante 2 segundos. Los recursos temporales tienen una espera global de 8 segundos por defecto.

## Selección y cámara libre

Primera persona usa el centro del viewport con radio `FirstPersonFOV=120` píxeles. Tercera persona usa las coordenadas del cursor, con radio `ThirdPersonFOV=180`. Las coordenadas de GetMouseLocation/WorldToViewportPoint se usan directamente para esta GUI con IgnoreGuiInset=true; no se suma/resta el margen de la barra superior. Se elige el personaje válido más cercano en pantalla. La adquisición requiere vida, parte válida, distancia permitida, posición visible en pantalla y, cuando está activado, raycast de visibilidad.

`LockMode="Auto"` combina CameraMode.LockFirstPerson, la identidad del sujeto local y las distancias cámara-cabeza y cámara-Focus. La entrada/salida automática usa umbrales distintos de 0.75/1.5 studs y confirmación de 0.2 segundos. Una cabeza cercana por sí sola no confirma primera persona. Es una heurística pública: cámaras personalizadas pueden necesitar `"FirstPerson"` o `"ThirdPerson"` explícitos.

Con `TargetPersistence=true`, mover cursor/cámara, cambiar de modo, salir del FOV o quedar oculto no cambia el objetivo. Fuera de pantalla se oculta el DOT y se conserva el bloqueo. Muerte, eliminación, respawn, pérdida de parte o superar `MaxDistance` lo invalidan. No se busca un sustituto automáticamente. Con persistencia desactivada, perder FOV o visibilidad también libera el objetivo.

El DOT sigue **TargetPart.Position actual**, cada RenderStepped, usando coordenadas del viewport; no usa la predicción ni su suavizado. Por defecto mide 6 píxeles, es circular, `#FF69B4`, opaco y tiene contorno blanco de 1 píxel. Los avisos y el DOT son pasivos, sin botones ni captura de entrada. C se ignora si Roblox procesó la entrada o se está escribiendo en un TextBox; DebugMode informa ese rechazo. El DOT permanece oculto hasta seleccionar un objetivo válido.

## Configuración y unidades

Edita `local Config = {...}` al principio del archivo autónomo antes de ejecutarlo. Para mantener las fuentes modulares, modifica también el literal y los defaults en `src/pink/Config.luau` y regenera. El generador comprueba dependencias explícitas y no toca DaHoodPrediction.lua. La configuración se valida antes de crear objetos.

| Campos | Efecto |
| --- | --- |
| Enabled, LockKey | Activa el arranque; tecla de bloqueo como `"C"` o Enum.KeyCode.C. Se valida y normaliza a Enum nativo. False no crea recursos y descarga una instancia anterior. |
| InitializationTimeout, InitializationPollInterval | Tiempo máximo global de preparación y sondeo en segundos; 8 y 0,05 por defecto. |
| LockMode, FirstPersonFOV, ThirdPersonFOV | Referencia y radio de selección en píxeles. |
| ModeEnterDistance, ModeExitDistance, ModeDwellSeconds | Umbrales en studs y confirmación temporal de Auto. |
| TargetPart, TargetPersistence, VisibilityCheck, MaxDistance | Parte observada, retención, visibilidad de adquisición y límite en studs. |
| PredictionX, PredictionY | Horizontes manuales en segundos, respectivamente X/Z e Y. |
| AutoPrediction, PingCompensation, PingSmoothing, PingReferences | Curva automática de RTT; filtro temporal; referencias editables ordenadas. |
| Min/MaxPredictionX/Y, PredictionSlew | Límites en segundos y cambio máximo de la curva automática en segundos/segundo. |
| MemoryTracking, VelocityPrediction | Historial filtrado o derivada entre capturas; extrapolación de velocidad. |
| AccelerationPrediction, MaxAccelerationHorizon | Aceleración opcional, desactivada por defecto; tiempo máximo de aceleración asumida. |
| HistoryCapacity, HistoryWindow, VelocitySmoothing, AccelerationSmoothing | Tamaño/ventana y constantes temporales del historial. |
| MaxObservedSpeed, MaxAcceleration, TeleportSlack, ReversalDotThreshold | Rechazo de anomalías, límites y reinicios de Memory. |
| StaleAfter, UpdateHz, PingHz | Caducidad de observaciones en segundos, capturas y muestras de ping por segundo. |
| PredictionSmoothing | EMA del resultado predicho, en segundos; nunca retrasa el DOT. |
| DistancePrediction, CloseDistance, MediumDistance | Aplica offsets explícitos por rango y vuelo de proyectiles configurados; no inventa una ganancia física por distancia. |
| WeaponProfile, Profiles, CloseOffset, MediumOffset, LongOffset | Perfil activo y ajustes globales/por perfil. |
| MaxFlightSeconds | Límite de vuelo para proyectiles configurados explícitamente. |
| ShowDot, DotSize, DotColor, DotTransparency, DotOutline, DotOutlineColor | Apariencia y visibilidad reales del DOT. |
| ShowNotifications, WelcomeNotification, WelcomeDuration, NotificationDuration | Avisos y duración, sin menú persistente. |
| DebugMode | Diagnóstico de cada pulsación de C y línea por segundo con objetivo, modo, ping, X/Y, velocidad, posiciones, distancia, edad, error y estado. Las trazas críticas de arranque siempre están activas. |

Para esta implementación elegimos segundos como unidad de PredictionX/Y. No convertimos las escalas antiguas 14.20 o 13.37. Los valores proporcionados son **referencias de calibración**, no precisión garantizada ni propiedades de Da Hood.

```text
edad = max(0, ahora - timestamp_captura)
offset_rango = DistancePrediction ? global[rango] + perfil[rango] : 0
hX = clamp(baseX + perfil.XOffset + perfil.LatencyOffset + offset_rango, minX, maxX) + edad
hY = clamp(baseY + perfil.YOffset + perfil.LatencyOffset + offset_rango, minY, maxY) + edad
predicción = posición + (velocidad.X*hX, velocidad.Y*hY, velocidad.Z*hX)
```

Si se habilita aceleración, cada eje añade `a * (u*h - 0.5*u²)`, con `u=min(h,MaxAccelerationHorizon)`. Después de esa ventana se supone velocidad terminal constante. VelocityPrediction=false elimina velocidad y aceleración; MemoryTracking=false conserva la derivada de las dos posiciones recientes y elimina aceleración acumulada.

AutoPrediction=false usa exactamente las bases manuales `0.1205/0.0800`; el ping no las altera. Los offsets explícitos del perfil/rango y los límites siguen aplicándose. Con AutoPrediction=true y PingCompensation=true, `LocalPlayer:GetNetworkPing()` entrega **RTT en segundos** según la documentación pública actual. Latency recibe RTT/2 para reutilizar su EMA y devuelve el equivalente RTT suavizado en milisegundos para interpolar X/Y:

| RTT ms | X segundos | Y segundos |
| --- | --- | --- |
| 55 | 0.113 | 0.075 |
| 62 | 0.120 | 0.080 |
| 70 | 0.128 | 0.085 |

Por debajo de 55 o por encima de 70 se mantiene el extremo de la tabla, incluyendo 8 y 180 ms. Puedes añadir puntos ordenados respaldados por mediciones. No se suma RTT/2 otra vez: la curva ya define el horizonte total elegido. Si falta ping o se desactiva PingCompensation, el estado es `AutoFallback` y usa las bases manuales. La edad de captura se añade una sola vez; las APIs públicas no revelan el timestamp de producción de cada réplica remota, por lo que no podemos conocer toda su antigüedad real.

Revolver, Default y Custom empiezan con `Kind="Unknown", Speed=0, Gravity=0`. Cada perfil permite offsets X/Y, latencia adicional y rangos. No declaramos el Revolver real hitscan ni asignamos velocidad o caída desconocidas. Solo un perfil configurado explícitamente como Projectile, con Speed positivo en studs/segundo, activa Ballistics al habilitar DistancePrediction. Gravity usa studs/segundo²; Hitscan es otra elección explícita del usuario. `physicsVerified=false` recuerda que estos parámetros no se han medido en Da Hood. Un proyectil inalcanzable devuelve ausencia de solución, no un disparo ficticio.

## API y adaptador de disparo propio

El archivo devuelve una tabla API que inicia automáticamente en un cliente Roblox. Sus métodos se llaman con punto; los métodos de `API.session` con dos puntos:

```lua
API.GetLockedTarget()          -- Player o nil
API.GetPredictedPosition()     -- Vector3 o nil; no mueve la cámara ni dispara
API.GetPrediction()            -- Registro de cálculo o nil
API.LockTarget()               -- Adquirir el más próximo; no reemplaza un bloqueo activo
API.UnlockTarget()
API.IsValidTarget(player)
API.SetEnabled(false)          -- Limpieza completa; para reiniciar usa API.init(config)
API.Unload()
```

El adaptador requiere un callback de un sistema **propio o autorizado**. No se registra ninguna comunicación de armas en el archivo autónomo:

```lua
local adapter = API.CreateShotAdapter(function(ticket)
    -- Tu sistema propio recibe ticket.aimpointActive y ticket.targetUserId.
    -- Guarda ticket.id para asociarlo a la medición real de ese disparo.
    OwnedFire(ticket)
end)
local ticket, reason = adapter:fire()
-- Cuando TU sistema entrega una medición independiente:
local measured, rejection = adapter:record(ticket.id, {
    accepted = true,
    targetUserId = ticket.targetUserId,
    character = ticket.character,
    actualPosition = measuredTargetPosition,
    referenceTime = measuredShotTime,
})
local metrics = adapter:summary()
```

OwnedFire y las variables de medición del ejemplo pertenecen a tu integración; el ejemplo no está conectado a Da Hood. El código completo funcional de ese puente está en `src/pink_demo/Probe.client.luau` y `Probe.server.luau`. Abre el lugar generado **PinkDotLockTest** en Studio con **Start Server y 2 Players**, coloca los personajes a la vista, usa C y dispara con F. El servidor crea exclusivamente sus propios eventos PinkDotLockProbe, valida el tiro de prueba y calcula un raycast hitscan de laboratorio. Compara la predicción capturada con la posición del personaje al procesar ese tiro. No aplica daño ni reproduce la física del Revolver de Da Hood.

La referencia usa el reloj y la posición medidos en el servidor en ese momento, independientemente de hX/hY; no elige una fecha que favorezca la predicción. El cliente asocia la respuesta con el ticket y registra errores de objetivo activo/manual/auto, RMSE horizontal/vertical/total y sesgo por perfil/rango. La comparación de posición usa targetPosition; excluye el desplazamiento de apuntado por gravedad. El éxito geométrico del raycast y el error de predicción son métricas diferentes. Los relojes deben compartir la base temporal de GetServerTimeNow; la caducidad y el rechazo de identidades impiden mezclar tiros obsoletos, duplicados o respawns.

## Pruebas y límites

```sh
python3 scripts/check_pink.py
python3 scripts/check.py
```

Herramienta oficial Luau 0.695, commit `1f6ff5d6f0072f2fab2adf35d1ffbaae7d848ad0`. La primera orden verifica que el archivo coincide con sus fuentes, compila y ejecuta pruebas matemáticas, del adaptador y del **archivo completo** mediante dobles de eventos/APIs. La segunda conserva las pruebas anteriores. Los mensajes Load Failed de las pruebas corresponden a fallos provocados deliberadamente.

Resultados verificados: **156 pruebas de Pink/SEDWARE, 2.384 comprobaciones, 0 fallos**, incluidas **34 de arranque, 30 de LockKey y 3 del loader**; **96 pruebas anteriores, 75.895 comprobaciones, 0 fallos**. Total **252 pruebas, 78.279 comprobaciones**. El archivo autónomo integra 13 módulos y no contiene requires externos. Las fuentes anteriores de DH PREDICTION LAB se preservan.

| Requisito de las 23 comprobaciones | Evidencia automatizada | Studio / Da Hood real |
| --- | --- | --- |
| 1–2 Inicialización y bienvenida | Archivo completo: recursos, texto, fade y caducidad, sin éxito ante fallo | Pendiente verificar render real |
| 3–5 Selección en primera/tercera persona y desbloqueo con C | Entrada real del bundle con dobles, referencia central/cursor, espacio de coordenadas y FOV | Pendiente probar entrada/cámara del motor |
| 6 Persistencia | Retención sin rescan con cursor distinto, occlusión y fuera de pantalla | Pendiente escena real |
| 7–8 Color y seguimiento del DOT | Propiedades Hot Pink, 6px y coordenadas observadas distintas de la predicción | Pendiente render/salto real |
| 9–10 Cambio de modo y cámara libre | Histéresis, dwell, lock retenido; espías registran cero escrituras de cámara/mouse | Pendiente cámara personalizada del juego |
| 11–14 X, Y, Auto y ping smoothing | Fórmulas, unidades, interpolación, 8–180 ms, fallback, límites y suavizado temporal | Pendiente replicación/ping real |
| 15–18 Memory, velocidad, Revolver, salto/reversa | Historial acotado, anomalías, reinicios, offsets y física configurable explícita | Pendiente calibración y movimiento reales |
| 19–21 Inválidos, limpieza y repetición | Muerte/eliminación/respawn, cero listeners tras unload, dueño único y fallo parcial limpio | Pendiente ciclo de vida nativo |
| 22 Rendimiento | 30/60/144 FPS controlados, cero scans por render y capturas limitadas | Sin medición CPU/GPU en Roblox |
| 23 Adaptador de disparo autorizado | Captura/medición funcional, tiempo independiente, comparativas, rechazos y limpieza | Demo preparado; ejecución de Studio pendiente |

No se ejecutaron Roblox Studio ni Da Hood en esta máquina Linux. Las pruebas matemáticas y los dobles no demuestran el renderer, la red o la física de esos programas. La selección, el DOT y el cálculo usan APIs públicas de cliente. Alterar un disparo requiere acceso autorizado al sistema de la experiencia; esa integración con Da Hood **no existe** aquí. C solo selecciona: no modifica balas, daño, remotes protegidos ni seguridad. No hay evasión de anticheat, hooks, ofuscación, inyección ni recopilación de credenciales.

## GitHub y loader

La corrección SEDWARE se publicó en [sedonkkk/sedon-](https://github.com/sedonkkk/sedon-/blob/main/PinkDotLock.lua). El [Raw nuevo verificado](https://raw.githubusercontent.com/sedonkkk/sedon-/02e0e72f1ec0a66e23ae490e5c15819fe2f20cf7/PinkDotLock.lua) está fijado al commit `02e0e72f1ec0a66e23ae490e5c15819fe2f20cf7`. Respondió HTTP 200 y sus **107.988 bytes** coinciden con el archivo compilado y probado; SHA-256 `1237403a663b604ac77ea070850d0c087a013a151062e9be80596c09a7e861ec`.

Puedes copiar esta línea, sin descargar archivos, en un host autorizado compatible:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/sedonkkk/sedon-/02e0e72f1ec0a66e23ae490e5c15819fe2f20cf7/PinkDotLock.lua"))()
```

[`PinkLoader.lua`](../PinkLoader.lua) contiene el cargador pequeño con informe de errores. Toda la lógica queda en PinkDotLock.lua. Para publicar otra versión: sube ese archivo a tu repositorio, abre el archivo → **Raw**, obtén la URL real del commit y ejecuta `python3 scripts/publish_pink_loader.py --raw-url URL_REAL` para comprobar los bytes antes de generar el loader. Apuntar a main recibiría cambios posteriores.

`loadstring` y `game:HttpGet` no son una vía de ejecución disponible en un LocalScript normal de Roblox publicado. El loader requiere un host autorizado que exponga esas APIs y permita ejecutar código remoto; no certificamos ejecutores externos. En Studio usa el LocalScript/ModuleScript, sin loader. Un loader ejecuta con los permisos de su host el código de la URL: revisa el archivo y utiliza el enlace del commit verificado. El payload no hace solicitudes de red; el único acceso HTTP del loader es obtener ese archivo.
