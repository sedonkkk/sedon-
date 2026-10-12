# SEDWARE: corrección de inicialización

La versión v3 también corrige el rechazo de la tecla C. [Causa, normalización y pruebas de LockKey](SEDWARE_LOCKKEY.md).

Entrada estable publicada en [SEDWARE.lua](../SEDWARE.lua): carga la versión actual de PinkDotLock.lua en main, por lo que conserva la misma dirección cuando se publiquen nuevas correcciones. Su Raw se verificó contra el payload corregido. A diferencia del enlace de un commit, esta entrada recibe las actualizaciones del repositorio.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/sedonkkk/sedon-/main/PinkDotLock.lua"))()
```

Esta actualización repara el proyecto existente, mantiene PinkDotLock.lua como archivo autónomo y conserva PredictionX=0.1205, PredictionY=0.0800, Memory, Auto Prediction, perfiles, selección persistente, DOT y cámara libre. No incorpora integración de disparo con Da Hood ni cambia sus remotes o seguridad.

## Evidencia y alcance de la causa

Se ejecutó el **bundle real del commit anterior** `b1acdf9b231e48a3ccd97135fdcf8576155cb690` mediante los dobles públicos del proyecto. Su payload coincide con el commit fijado por el loader antiguo `837ef39140063c4576a7aa9166cda4cf2e4ceec3`.

| Caso reproducido | Comportamiento anterior | Corrección |
| --- | --- | --- |
| PlayerGui ausente y disponible 0,2 s después | Runtime.check lo consideraba falta definitiva. No creaba sesión ni reintentaba al aparecer. | Se distingue pending de missing; espera limitada y nueva auditoría. |
| CurrentCamera ausente y disponible después | Abortaba inmediatamente, sin recuperación de ese inicio. | Misma espera global para cámara y PlayerGui. |
| Cámara con ViewportSize=(0,0) | Runtime aceptaba la presencia del método de proyección; Session abortaba antes de la bienvenida. | Viewport finito y positivo forma parte de la preparación. |
| Inicio normal | No había trazas de ejecución, módulos, configuración ni conexión de C. | Cada fase crítica informa estado y explicación en consola. |
| API.tryInit fallida | Devolvía nil/report; únicamente el bloque de autoinicio intentaba avisar. | Fallo centralizado también para inicialización explícita. |
| Segundo error al construir aviso de fallo | El pcall lo descartaba; la notificación tampoco mostraba la explicación original. | Aviso mínimo independiente con explicación; si falla, la consola conserva ambos errores. |
| C sin candidatos, bienvenida ya caducada | LockTarget devolvía false, el callback ignoraba ese resultado y no aparecía ningún aviso. | SEDWARE / No valid target, más diagnóstico detallado con DebugMode. |

Estos fallos son verificables y explican rutas que terminaban sin interfaz activa. **No prueban cuál ocurrió en el entorno concreto del usuario**, porque no tenemos sus trazas ni ejecutamos Da Hood. La ausencia de DOT antes del primer bloqueo válido era intencional; el síntoma relevante era la ausencia de bienvenida/respuesta a C.

También se corrigió el desplazamiento del DOT y del cursor causado por añadir/restar el margen superior pese a IgnoreGuiInset=true. La [documentación de Camera.WorldToViewportPoint](https://create.roblox.com/docs/reference/engine/classes/Camera#WorldToViewportPoint) indica que esas coordenadas sirven directamente para esa GUI; [GetMouseLocation](https://create.roblox.com/docs/reference/engine/classes/UserInputService#GetMouseLocation) usa el origen superior izquierdo de pantalla. Este desplazamiento **no explica por sí solo la ausencia de bienvenida**. La colocación en el renderer real sigue pendiente.

## Arranque protegido y espera

Bootstrap coordina las mismas operaciones originales. El primer mensaje se imprime antes de construir la tabla editable de configuración; esa construcción, la carga de módulos, la validación, la sesión y el autoinicio se protegen con xpcall/pcall y conservan errores y stack cuando debug.traceback está disponible.

Runtime.check permanece como auditoría inmediata. Runtime.awaitReady espera únicamente los recursos temporales: LocalPlayer, PlayerGui, CurrentCamera y viewport. Las APIs incompatibles, RunService:IsClient=false y excepciones de servicios se informan de inmediato; no se ocultan como una simple espera.

```lua
InitializationTimeout = 8,
InitializationPollInterval = 0.05,
```

Es un plazo global compartido, sin WaitForChild infinito ni conexiones por sondeo. Usa os.clock y un límite adicional de consultas para detener relojes/esperas defectuosos que regresen sin avanzar. Requiere que las APIs nativas de espera respondan; el script no puede interrumpir una implementación externa bloqueada indefinidamente. Una inicialización posterior sobre la misma API cancela la anterior y preserva el informe de la más reciente. Al volver a ejecutar el bundle se sustituye el dueño en PlayerGui solo después de construir la nueva sesión; permanece una instancia con sus conexiones propias.

Los eventos devuelven una conexión desconectable y activa; se comprueban InputBegan y RenderStepped. Se ejercitan reloj, viewport, referencia e interfaz antes de declarar Session ACTIVE. WelcomeNotification/ShowNotifications desactivados se indican en Configuration. Un fallo crítico no anuncia éxito. La interfaz de error usa Frame/TextLabel, independientemente de Config, CanvasGroup y GetServerTimeNow. Si no hay PlayerGui o no se puede crear/limpiar el aviso, la consola explica el motivo. La caducidad de ese aviso es de 2 segundos y no agrega conexiones permanentes.

## Leer la consola

En Roblox usa la consola del cliente disponible con F9; en Studio, Output del cliente. Si el host externo dispone de otra consola, revisa también sus errores de HTTP y compilación. Filtra por `[SEDWARE]`.

Ejemplo de un inicio completo:

```text
[SEDWARE][Execution][START] ... payload began execution
[SEDWARE][Modules][READY] 13 embedded modules loaded
[SEDWARE][Configuration][READY] PredictionX=0.1205 PredictionY=0.08 ...
[SEDWARE][LocalPlayer][READY] ...
[SEDWARE][PlayerGui][READY] ...
[SEDWARE][CurrentCamera][READY] ...
[SEDWARE][Services][READY] ...
[SEDWARE][Graphics][READY] ...
[SEDWARE][Input][READY] InputBegan connected; LockKey=Enum.KeyCode.C
[SEDWARE][Session][ACTIVE] ...
[SEDWARE][Render][READY] First RenderStepped update completed ...
```

Graphics READY confirma construcción/parentado de objetos; Render READY confirma un callback completado. No certifican el renderer o la integración de armas de otra experiencia.

- **No aparece Execution START:** el payload todavía no comenzó. Revisa descarga, API game:HttpGet, compilación Luau y la invocación del loader. Un error sintáctico no puede ser capturado por un script que aún no compiló. PinkLoader.lua conserva el error de HTTP/compilación/ejecución de su host.
- **AutoInit SKIPPED:** PINK_DOT_NO_AUTOSTART=true; el informe lo dice explícitamente. Usa API.init() para iniciar.
- **PlayerGui/CurrentCamera WAIT:** está esperando dentro del límite configurado; el timeout explica qué recurso faltó.
- **Services/Graphics/Input FAIL:** copia esa línea y el stack completo. Incluye la excepción concreta, no solo un mensaje genérico.
- **Session DISABLED:** Enabled=false; no se crean controles ni sesión activa.
- **Session ACTIVE y Render READY, pero no se ve el DOT:** el DOT solo aparece con un objetivo válido bloqueado y visible en pantalla. Pulsa C y revisa la selección.

Las trazas de arranque siempre están activas. Para diagnosticar C sin descargar ni editar el archivo, conserva la API que devuelve el loader actualizado y luego ejecuta:

```lua
api.Config.DebugMode = true
api.init(api.Config)
```

`api` es una variable local de tu código que contiene el resultado del loader. Este reinicio mantiene la tabla completa de configuración y limpia la sesión anterior. DebugMode también se puede editar al principio del archivo.

Cada pulsación de la tecla configurada muestra key y mode. La adquisición informa `reference=(x,y)`, `evaluated=`, `valid=`, `rejections=` con nombres/motivos y `selected=`. Se detallan personajes ausentes, humanoides muertos, partes inválidas, distancia, occlusión, fuera de pantalla/FOV, entradas procesadas por Roblox o un TextBox enfocado. Al desbloquear no se vuelve a buscar un candidato. Sin candidatos aparece **SEDWARE / No valid target**.

## Archivos y validación

Se modifican Runtime, Config, Session, Overlay y Selection; se añade Bootstrap. El generador integra esa coordinación en PinkDotLock.lua y regenera los dos lugares de Studio. Se amplían PinkMock, las pruebas de GUI/selección y se agrega pink_startup_body.luau. El publicador actualiza PinkLoader.lua únicamente tras verificar el nuevo Raw. DH PREDICTION LAB, shared y los algoritmos de Prediction permanecen sin cambios.

```sh
python3 scripts/build_pink.py
python3 scripts/check_pink.py
python3 scripts/check.py
```

Compilación con Luau oficial 0.695 correcta. Resultado actual: **210 pruebas de Pink/SEDWARE y 96 anteriores: 306 pruebas, 79.051 comprobaciones, 0 fallos**. Las 36 pruebas de arranque abarcan todos los diez casos pedidos, más timeout conjunto, viewport, LocalPlayer, excepciones, cancelación, error del encabezado, autoinicio sin game y reemplazo de sesión tras respawn. Otras 3 pruebas ejercitan el loader real, la causa original de un error HTTP y la identificación de un fallo de compilación. La actualización v3 añade 30 pruebas específicas de LockKey; el [arma propia](SEDWARE_WEAPON_INTEGRATION.md) añade 52 pruebas de integración.

La lógica de arranque y los callbacks se ejecutaron sobre el archivo autónomo real con dobles deterministas. **No son pruebas de Roblox Studio ni Da Hood real.** Esas ejecuciones y las limitaciones específicas del host externo siguen pendientes. El loader depende de loadstring compatible con Luau y game:HttpGet proporcionados por un host autorizado; esas funciones no habilitan código remoto desde un LocalScript normal publicado. El script no intenta eludir esas restricciones.

El loader anterior estaba fijado a otro commit y continuará cargando esa versión. Hay que sustituir su línea por el Raw nuevo publicado; actualizar solamente main no modifica el código que descarga aquel enlace.

La versión corregida está publicada en el commit `ed141a9b2f0dcf8e4c9a677aa6c5a4fb0edcc28e`. [Raw nuevo, verificado HTTP 200 y byte por byte](https://raw.githubusercontent.com/sedonkkk/sedon-/ed141a9b2f0dcf8e4c9a677aa6c5a4fb0edcc28e/PinkDotLock.lua): 108.378 bytes; SHA-256 `235e4c13d224641240b0f5354e4983326e1761a70746ff6f80a232015bc18eb6`.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/sedonkkk/sedon-/ed141a9b2f0dcf8e4c9a677aa6c5a4fb0edcc28e/PinkDotLock.lua"))()
```
