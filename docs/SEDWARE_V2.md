# SEDWARE CAM LOCK V2 — PINK EDITION

Actualización sobre [SedwareCamLock.lua](../SedwareCamLock.lua), generado a partir de los módulos de `src/cam` y los algoritmos existentes. Se conservan PinkDotLock.lua, DaHoodPrediction.lua, sus fuentes y el controlador de cámara corregido. El archivo autónomo incorpora 28 módulos; no carga otros archivos Lua ni solicita servidores durante la ejecución.

## Auditoría y cambios

| Problema | Evidencia del código anterior | Cambio V2 |
| --- | --- | --- |
| Avisos de búsqueda repetidos | `_step` reintentaba cada 0.25 s y `LockTarget` emitía un aviso cada 2 s. | La búsqueda y C sin candidato no generan toasts; solo diagnóstico opcional limitado. Notificaciones deduplicadas, cooldown y cola máxima de cuatro. |
| Dropdown tapado | Era hijo de HitPartRow y el ScreenGui usaba orden Sibling; las filas posteriores podían cubrir ese grupo. | PopupLayer independiente, ZIndex Global 100+, fuera del scroll/clipping de las filas, posición acotada al viewport. |
| Drag interrumpido tras respawn | No había limpieza del drag en CharacterRemoving/Added ni en cambios de jerarquía. | Conexiones persistentes a UserInputService, recuperación por coordenadas del encabezado y limpieza en ambos eventos de personaje, fin de input y pérdida de foco. |
| Multiplicador oculto | Config dividía CamPrediction por 13.80 y escalaba manual X/Y, curvas y offsets. | Campo, control, metadatos y multiplicador eliminados. X/Z usan PredictionX; Y usa PredictionY. |
| Selección demasiado estrecha | Radius 50; ambos modos usaban siempre el centro. | Radius 180. Primera persona/ratón centrado usan el centro; tercera persona utiliza GetMouseLocation. |

El diagnóstico de drag identifica una carencia verificable del ciclo de vida. Sin reproducir el congelamiento original en el motor no se atribuye toda posible causa de ese síntoma a una única operación. Las pruebas nuevas interrumpen el drag con cinco respawns y comprueban recuperación y ausencia de conexiones crecientes.

## GUI y controles

Panel compacto de 360 × 432 px, negro profundo y Hot Pink, Gotham, esquinas redondeadas y bordes finos. MAIN/MISC se crean una sola vez. MISC usa ScrollingFrame. El botón `−` conserva una barra de 56 px con logo, título y `+`, arrastrable; restaurar conserva pestaña, valores y preferencias. Los controles ocultos no responden a sus acciones.

| MAIN | Default | Significado |
| --- | --- | --- |
| Enable | OFF | Adquirir y seguir un jugador válido; OFF devuelve el control al sistema normal de cámara. |
| Hit Part | UpperTorso | Head / UpperTorso / HumanoidRootPart; Torso como fallback R6. |
| Prediction X | 0.1205 | Segundos de anticipación horizontal X/Z. |
| Prediction Y | 0.0800 | Segundos de anticipación vertical. |
| Smoothness | 0.405 | Respuesta temporal del controlador sin roll. Valores menores responden más rápido. |
| Radius | 180 | Radio de adquisición en píxeles; no libera a un jugador ya bloqueado. |

MISC/MOVEMENT expone Fly, Fly Keybind, Fly Speed, Speed, Speed Keybind y Walk Speed. MISC/ESP expone ESP, Hitboxes, Names, Target Mode y, en Specific Player, Player Username, Apply Target y Clear Target.

Se utilizan tweens discretos de TweenService: hover 0.10 s, toggles/captura/dropdown 0.15 s, pestañas 0.18 s y minimizar 0.22 s. Existe un solo tween activo por instancia; se cancela al sustituirlo o destruir la GUI. No hay animaciones permanentes. Las notificaciones reutilizan el fade temporal existente. Si TweenService no existe, el estado se aplica inmediatamente y se registra la limitación.

## Predicción y cámara

```text
leadX = clamp(PredictionX, MinPredictionX, MaxPredictionX)
leadY = clamp(PredictionY, MinPredictionY, MaxPredictionY)
posición predicha = muestra + velocidad × (lead por eje + edad de la muestra)
```

Los límites iniciales de lead son 0–0.35 s. No existe ganancia de CamPrediction. Memory, filtros de velocidad, reversas, teleports, suavidad opcional de predicción y offsets empíricos de distancia se reutilizan. AutoPrediction sigue disponible internamente; con ping válido utiliza la curva X/Y empírica directa y no suma RTT dos veces. Arranca apagado para respetar los X/Y manuales.

El CameraController de la corrección anterior permanece sin cambios: yaw/pitch independientes, base Y global, fromMatrix, deltaTime y manejo de polos/wrap. Solo escribe la orientación con la posición actual de Roblox; no altera CameraSubject, Focus, posición del personaje ni distancia de tercera persona. [Detalle de orientación](SEDWARE_CAMERA_ROLL.md).

C sigue bloqueando/liberando con Enable ON; no actúa durante chat/TextBox ni con entrada procesada. Una liberación manual conserva la pausa de adquisición hasta C o apagar/encender Enable. ShowFOV=false oculta el círculo opcional; puede activarse desde Config sin añadir un control a la GUI.

## Logo original

No se proporcionó un asset ID. La tabla Config incluye exactamente:

```lua
LogoAssetId = "rbxassetid://COLOCAR_ID_REAL"
```

El ImageLabel original está preparado en el encabezado y las notificaciones; la barra minimizada reutiliza el mismo encabezado. Ambos ImageLabels utilizan la misma URI y la caché de recursos de Roblox. El fallback temporal de geometría rosada anterior sigue visible hasta que una imagen válida esté cargada; **no es el logo metálico original**. No se inventa un ID ni se sube una imagen sin disponer del recurso/ID.

Para usar el emblema: abre Roblox Creator Dashboard, entra en Creations/Development Items y la sección Images o Decals, sube el archivo original y espera su aprobación. Copia el ID de imagen accesible y sustitúyelo en LogoAssetId. Si creaste un Decal, verifica su Texture y usa el ID de imagen que carga correctamente en un ImageLabel. Puedes probarlo en Studio antes de publicar. Un asset privado/no aprobado conserva el fallback si IsLoaded no llega a true.

## Movimiento autorizado

Defaults: Fly=false, V, FlySpeed=65; Speed=false, G, WalkSpeed=24. Space sube y LeftControl baja, configurables mediante FlyUpKey/FlyDownKey. WASD controla el movimiento relativo a la cámara. Fly utiliza Attachment + LinearVelocity; conserva y restaura AutoRotate, PlatformStand y estado del Humanoid sin girar el personaje ni mover CFrame manualmente.

Por defecto el archivo genérico no declara autorización de movimiento. Se habilita en una experiencia propia mediante uno de estos mecanismos:

- El servidor de esa experiencia establece `SEDWAREMovementAuthorized=true` en Workspace o el jugador.
- El autor configura `MovementAuthorized=true` al integrar el cliente en una sesión explícitamente autorizada.

Los lugares de Studio incluidos contienen un Script propio que concede esa autorización. Ese Script y el RemoteEvent de respawn de pruebas pertenecen a este proyecto y se distribuyen únicamente en los lugares de Studio; el archivo autónomo no los solicita ni manipula remotes de Da Hood.

Speed captura la velocidad original y escribe solo al activar, editar o cambiar de personaje. Si el servidor impone otra velocidad, no la reescribe cada frame; al apagar tampoco sobrescribe una modificación ajena posterior. Mientras Fly está activo, Speed se pausa y restaura el valor propio; se reanuda al apagar Fly. Al morir se retiran constraints y referencias; las preferencias ON pueden reanudarse al estar listo el nuevo personaje.

Estos son controladores de cliente para una experiencia autorizada. **Una asignación local de WalkSpeed o una fuerza local no confirma aceptación del servidor.** Un servidor ajeno puede limitarlas; no se implementa ninguna evasión. En un juego publicado el desarrollador debe integrar su política/autorización y pruebas de física/replicación.

## Keybinds

Pulsa Fly Keybind o Speed Keybind: muestra Press a key. Una tecla de teclado válida actualiza la configuración; Escape, cambiar pestaña/minimizar o perder foco cancela. Se ignora input procesado y texto enfocado. Se rechazan duplicados con C, entre Fly/Speed, con teclas de subida/bajada y con WASD/teclas reservadas. La captura no dispara al mismo tiempo el toggle que acaba de asignarse.

## ESP

ESP es el interruptor principal; Hitboxes y Names son preferencias independientes. Apagar ESP destruye sus indicadores y conserva preferencias. Si ambos están OFF no se proyectan ni crean indicadores.

Hitboxes utiliza SelectionBox como referencia visual del volumen del modelo. No modifica Size, CanCollide, colisiones ni daños. Names usa BillboardGui compacto con `AlwaysOnTop=false` y el Username real (Player.Name), no DisplayName. VisibleOnly comprueba rango, profundidad, pantalla y línea de visión mediante raycast; no existe modo AlwaysOnTop/ThroughWalls.

Specific Player resuelve una coincidencia exacta de Username ignorando mayúsculas, una vez al pulsar Apply. Texto parcial y DisplayName no se aceptan. Un Username inexistente muestra un aviso discreto y no cae en All. La selección sobrevive al respawn. Si el jugador abandona, se liberan sus indicadores; Clear vacía la selección y mantiene modo/preferencias.

PlayerRegistry enumera Players una vez y mantiene cachés mediante PlayerAdded/Removing y CharacterAdded/Removing/ChildAdded/Removed. Hay un solo ciclo central en la sesión. Los adornments siguen transformaciones nativamente; no existe un RenderStepped por jugador. Se reutilizan al cambiar visibilidad/respawn y solo se crean para jugadores que han sido visibles.

Ajustes internos: ESPUpdateHz=20, ESPMaxDistance=350, ESPOcclusionMode="VisibleOnly", ESPLowPerformanceMode=true. El modo económico limita la comprobación de visibilidad a 10 Hz; false permite la frecuencia configurada, hasta 30 Hz. No se recrean textos ni instancias por frame, ni se vuelve a buscar Username en cada actualización.

## Diagnóstico y pruebas

DebugMode=true registra búsqueda limitada y coste ESP una vez por segundo. CameraDebugMode/CameraDebugInterval conservan los diagnósticos de yaw/pitch/roll y error angular. Los fallos de APIs opcionales desactivan la función afectada y explican el error; la GUI/cámara pueden seguir activas.

```sh
python3 scripts/build_cam.py
python3 scripts/check_cam.py
```

El compilador oficial valida 32 archivos de la variante y los XML contienen exactamente las fuentes probadas. **108 pruebas y 116.742 comprobaciones pasan**: 13 de predicción, 10 de cámara, 16 de roll, 43 de GUI/bundle, 20 específicas V2, 3 de rendimiento y 3 del loader. Las 342 de los proyectos anteriores también pasan. Total: 450 pruebas y 197.270 comprobaciones.

Una ejecución del benchmark de Luau CLI midió 1.000 actualizaciones con APIs/jugadores simulados:

| Jugadores simulados | Media de CPU por update | Máximo observado | Instancias ESP |
| ---: | ---: | ---: | ---: |
| 5 | 0.0243 ms | 0.2048 ms | 15 |
| 15 | 0.0738 ms | 0.3406 ms | 45 |
| 30 | 0.1465 ms | 0.5327 ms | 90 |

Estas cifras cambian según máquina/ejecución. Excluyen el renderizador, raycasts y física reales de Roblox; **no son FPS de Studio ni una promesa de cero impacto**. Se comprobó que durante esos updates no se crearon nuevos indicadores, no aumentaron conexiones y no se enumeró Players de nuevo. También se verificó la cadencia con deltas programados de 30/60/144 FPS.

## Comprobación nativa preparada

[studio/SedwareCamV2Test.rbxlx](../studio/SedwareCamV2Test.rbxlx) incluye el mismo archivo autónomo como ModuleScript, un runner LocalScript y un servidor de autorización/respawn propio. Abre el lugar en Studio y pulsa Play. Imprime NativeV2/PASSED o FAILED, diez escenarios y SUMMARY; usa TweenService, LinearVelocity/física reales y tres respawns solicitados a su servidor de pruebas. Mide CPU nativa y samples FPS ESP ON/OFF con 5/15/30 modelos de personaje **explícitamente simulados**, no cuentas reales. Los tests de keybind/drag invocan handlers con fixtures; la interacción física de ratón/teclado requiere revisión manual.

[studio/SedwareCamLock.rbxlx](../studio/SedwareCamLock.rbxlx) es el demo normal autorizado. Usa dos clientes para comprobar selección real, C, primera/tercera persona, seguimiento, ESP All/Specific, minimizar, dropdown y arrastre después de morir. Revisa también qué ocurre cuando la autorización o la velocidad la controla tu servidor.

**Este entorno Linux no ejecuta Roblox Studio.** No se presentan los runners preparados como resultados nativos. No se ha verificado V2 dentro de Da Hood ni se integra su sistema de disparo o mecanismos internos.

## Publicación

El nuevo Raw y loader se añadirán después de publicar el commit V2 y comprobar sus bytes. Los enlaces anteriores con commit fijo continúan ejecutando versiones anteriores.
