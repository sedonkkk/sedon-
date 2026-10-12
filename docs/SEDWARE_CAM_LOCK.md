# SEDWARE CAM LOCK v1

Nueva variante: [SedwareCamLock.lua](../SedwareCamLock.lua). Conserva DH PREDICTION LAB, PinkDotLock y su demo multiarmas. El archivo autónomo incorpora 19 módulos; no requiere archivos locales ni descarga módulos durante la ejecución.

## Uso

Al ejecutar el archivo aparece un panel negro/rosado de 310 × 324 píxeles y la notificación **SEDWARE · Cam Lock Loaded**. Arranca con Enable **OFF**. Actívalo, coloca un personaje visible dentro del radio alrededor del centro de pantalla y el sistema seleccionará el candidato más cercano al centro. Mantiene ese objetivo mientras su personaje, vida, parte y distancia sean válidos; el radio solo afecta a la adquisición.

El encabezado permite mover el panel con ratón o toque. El panel se adapta al viewport. Edita un número y pulsa Enter o sal del campo para aplicarlo; los valores inválidos se rechazan con una explicación. Solo hay siete controles en MAIN:

| Control | Valor inicial | Efecto |
| --- | --- | --- |
| Enable | OFF | Activa adquisición y seguimiento; OFF libera el objetivo y detiene las escrituras a la cámara. |
| Hit Part | UpperTorso | Selecciona Head, UpperTorso o HumanoidRootPart. UpperTorso usa Torso en personajes R6 si existe y `FallbackR6=true`. |
| Cam Prediction | 13.80 | Ganancia sin unidades: valor / 13.80. Escala los horizontes de predicción. |
| Prediction X | 0.1205 | Segundos de anticipación horizontal, tanto X como Z. |
| Prediction Y | 0.0800 | Segundos de anticipación vertical. |
| Smoothness | 0.405 | Respuesta de la cámara, de 0 a 1; valores menores responden más rápido. 0 orienta directamente salvo la protección de transición polar. |
| Radius | 50 | Radio de selección en píxeles desde el centro del viewport, en primera y tercera persona. |

También se conserva C como acceso de teclado: con Enable ON, libera el objetivo y suspende la adquisición hasta pulsar C otra vez o apagar/encender Enable. Respeta entradas procesadas y campos de texto enfocados. La pérdida por muerte, retirada o cambio de personaje permite buscar otro candidato después de 0.25 s.

Para descargar el sistema sin añadir un octavo control al panel, guarda el resultado de la ejecución en una variable y llama a `api.Unload()`. Destruir la GUI o el LocalScript también descarga la sesión. Ejecutar otra vez sustituye la sesión previa únicamente cuando la nueva interfaz, entrada y render binding se han preparado.

## Predicción y respuesta

La tabla `Config` al principio del archivo contiene los siete valores y ajustes internos. Por defecto, AutoPrediction está apagado para respetar los X/Y manuales:

```text
gain = CamPrediction / 13.80
leadX = clamp(PredictionX × gain, MinPredictionX, MaxPredictionX)
leadY = clamp(PredictionY × gain, MinPredictionY, MaxPredictionY)
horizonte = lead + edad real de la última observación
```

Los límites por defecto de lead son 0–0.35 s. La velocidad se estima mediante el historial Memory existente; se conservan sus filtros, reversas, rechazo de teleports y tiempos desordenados. Cambiar números conserva las muestras. Cambiar Hit Part reinicia el historial de posición para no inferir movimiento entre dos partes distintas.

`AutoPrediction=true` y `PingCompensation=true`, editables en Config, habilitan la curva RTT empírica existente y su suavizado temporal. La curva también se escala por gain; ya expresa el horizonte total y **no se suma el ping otra vez**. Sin ping válido se utilizan los X/Y manuales. Los offsets de distancia se conservan como segundos calibrables y arrancan en cero; no se inventan velocidades ni propiedades de armas.

La suavidad de predicción y la de cámara están separadas. `PredictionSmoothing=0` evita por defecto otro filtro de posición. La cámara interpola orientación con:

```text
tau = 0.12 × Smoothness² segundos
alpha = 1 − exp(−deltaTime / tau)
```

Con 0.405, tau = 0.019683 s; la respuesta matemática de yaw/pitch a un cambio fijo alcanza aproximadamente el 95 % en 59 ms. Ese cálculo no promete una latencia total del juego. La cámara conserva únicamente yaw y pitch entre frames y toma la posición actual de Roblox. Construye una base nivelada respecto al eje Y global mediante `CFrame.fromMatrix`, sin transportar UpVector ni interpolar cuaterniones. El callback se registra en RenderStepped mediante `BindToRenderStep` con prioridad `Camera + 1`. [Causa del roll y corrección](SEDWARE_CAMERA_ROLL.md).

Solo se escribe orientación en `CurrentCamera.CFrame`; CameraType, CameraSubject, Focus y controles del personaje conservan su propietario. Una cámara Scriptable pausa el seguimiento por defecto. Una ausencia temporal de CurrentCamera también pausa; ambos casos se informan en consola y reanudan cuando existe una cámara compatible.

## Marca y notificaciones

El panel muestra SEDWARE, CAM LOCK y v1. El logo adjunto se usa como referencia para una **S rosada hecha con Frames nativos**, sin inventar un asset ID de Roblox. Las notificaciones comparten ese logo, colores y fade: Cam Lock Loaded, Lock Enabled, Lock Disabled, Target Locked y Target Lost. La cola breve evita que dos eventos del mismo frame se oculten entre sí; apagar Enable descarta mensajes de bloqueo pendientes.

## Comprobar en una experiencia propia

Abre [studio/SedwareCamLock.rbxlx](../studio/SedwareCamLock.rbxlx) en Roblox Studio. Incluye el mismo archivo autónomo como LocalScript, baseplate y dos SpawnLocations. Usa **Start Server con 2 Players**; los objetivos son otros jugadores, no NPC ni el jugador local.

1. En cada cliente, confirma GUI y bienvenida; OFF debe dejar la cámara normal.
2. Acerca el centro de pantalla al otro personaje, activa Enable y comprueba el seguimiento al caminar y saltar.
3. Cambia Hit Part, X/Y, Cam Prediction y Smoothness. Reduce Radius y vuelve a adquirir para comprobar su efecto.
4. Comprueba primera/tercera persona, C, pérdida por muerte/respawn y vuelta al comportamiento normal al apagar Enable.
5. Ejecuta una segunda copia y confirma una sola GUI/sesión; destruye la GUI y confirma limpieza.

También puedes copiar SedwareCamLock.lua a un LocalScript en StarterPlayerScripts o usar [sedware-cam.project.json](../sedware-cam.project.json) con Rojo. Studio no necesita loadstring ni HTTP para esa instalación.

## Diagnóstico y límites

La consola muestra `[SEDWARE][CamExecution]`, CamModules, CamConfiguration, PlayerGui, CurrentCamera, CamGraphics, CamRender y CamSession. La espera de recursos está limitada a 8 s por defecto. `CamRender BOUND` significa que se registró el callback; `CamRender READY` se emite después de completar el primer frame. Los fallos críticos muestran una notificación cuando PlayerGui está disponible y dejan una explicación en consola.

`CameraDebugMode=true` en Config habilita `[SEDWARE][CamCamera]` con yaw, pitch, roll, ángulo hacia el objetivo, deltaTime, error angular y estado. Los ángulos están en grados; `CameraDebugInterval=0.5` limita los mensajes. No hay controles nuevos en la GUI.

Esto es un controlador de cámara de cliente. **No integra el disparo de Da Hood**, no proporciona Silent Aim ni modifica comunicaciones de armas. El loader HTTP exige que el entorno permita obtener el archivo y compilar Luau; esas capacidades no pertenecen a un LocalScript publicado normal. No se ha probado esta variante dentro de Da Hood ni en el motor de Roblox desde el entorno Linux.

## Construcción y pruebas

```sh
python3 scripts/build_cam.py
python3 scripts/check_cam.py
```

El builder comprueba dependencias y genera el archivo y el lugar XML. El check usa el compilador oficial Luau y pruebas de predicción, cámara y eventos que ejecutan el **archivo autónomo real** mediante dobles explícitos de APIs. Comprueba controles, posición predicha, escrituras CFrame, prioridades, FPS, vida del objetivo, inicialización, reinicio y desconexiones. Los dobles no verifican renderizado, movimiento ni respuesta real de Roblox; la comprobación nativa anterior sigue pendiente.

Resultados después de corregir Camera Roll: **85 pruebas, 116.433 comprobaciones, cero fallos**, además de compilación oficial de 19 archivos de la variante y correspondencia exacta de la fuente incluida en ambos lugares XML.

| Pruebas | Casos | Comprobaciones | Alcance |
| --- | ---: | ---: | --- |
| Predicción | 13 | 916 | Configuración, X/Y, ganancia, Memory, Auto y curva de ping. |
| Cámara | 10 | 383 | Orientación y posición, respuesta temporal, intervalos irregulares y direcciones verticales. |
| Regresión de roll | 16 | 84.819 | Izquierda/derecha, salto/caída, círculos, detrás, polos, reversas, wrap, FPS, roll heredado y reset. |
| Archivo autónomo con GUI | 43 | 30.307 | Eventos del bundle bajo dobles de APIs: controles, C, orden de render, persistencia, avisos, espera, fallos, limpieza, nivelación, diagnóstico y perspectiva. |
| Loader | 3 | 8 | Texto del loader publicado bajo un host simulado: carga completa, fallo HTTP y error de compilación. |

También pasan las **342 pruebas de los proyectos anteriores**, con 80.528 comprobaciones, sin modificar sus módulos ni archivos autónomos. Total del repositorio: 427 pruebas y 196.961 comprobaciones. Estos resultados no representan una ejecución nativa en Roblox ni Da Hood. [SedwareCamRollTest](../studio/SedwareCamRollTest.rbxlx) prepara 12 escenarios con CFrame/Camera reales y un render binding nativo, pendientes de ejecución en Studio.

## Entrega de la corrección

La corrección está publicada en el commit **64678f60e84762cb9cbc29df6ee86f7395059254**. [Raw nuevo](https://raw.githubusercontent.com/sedonkkk/sedon-/64678f60e84762cb9cbc29df6ee86f7395059254/SedwareCamLock.lua) y [CamLoader.lua](../CamLoader.lua) cargan el controlador corregido. El enlace anterior con commit fijo conserva el controlador anterior.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/sedonkkk/sedon-/64678f60e84762cb9cbc29df6ee86f7395059254/SedwareCamLock.lua"))()
```

Se comprobó HTTP 200 y correspondencia byte por byte: 136.399 bytes, SHA-256 `5a1f8bc4e2e2249456de5d17bd3d8d5bf2aaad078422017841b2fd9abf4ff42b`. También se verificaron los bytes de ambos lugares publicados:

- [SedwareCamLock.rbxlx Raw](https://raw.githubusercontent.com/sedonkkk/sedon-/64678f60e84762cb9cbc29df6ee86f7395059254/studio/SedwareCamLock.rbxlx): demo para selección real con dos jugadores.
- [SedwareCamRollTest.rbxlx Raw](https://raw.githubusercontent.com/sedonkkk/sedon-/64678f60e84762cb9cbc29df6ee86f7395059254/studio/SedwareCamRollTest.rbxlx): runner nativo preparado, pendiente de ejecución en Studio.

El loader solo obtiene este archivo público y compila/ejecuta Luau con diagnóstico de errores. Para conservar una referencia y descargar la sesión después, guarda el retorno en `local api = loadstring(...)()` y llama a `api.Unload()`.
