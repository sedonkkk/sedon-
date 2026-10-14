# SEDWARE V3.2 — PINK EDITION

Actualización de los módulos existentes y del archivo autónomo SedwareCamLock.lua. Se conserva la GUI negra/rosada MAIN/MISC de 420×520, Memory, selección con C, primera/tercera persona, escala Prediction X/Y=13.15 y calibración interna .1205/.0800. PinkDotLock.lua y DaHoodPrediction.lua permanecen separados.

## Qué se comprobó del archivo antiguo

La [auditoría del adjunto completo](SEDWARE_V32_LEGACY_AUDIT.md) identifica el contenido real, SHA256 y líneas relevantes. No se ejecutó la GUI original ni se incorporaron sus otras herramientas.

Fly1 une un Core a LowerTorso, mueve el objetivo de BodyPosition mediante incrementos por wait() y usa BodyGyro para orientar el conjunto. Su valor 5/10 es distancia por iteración, no velocidad en studs/s; depende del scheduler y las diagonales no están normalizadas. Speed V2 aplica 140 y renombra Humanoid a xxx; después su condición sigue buscando Humanoid, por lo que deja de mantener la velocidad. Ambos conservan referencias y restauraciones inseguras.

Se reutilizan las ideas de desplazamiento relativo a cámara, orientación del cuerpo, activación y velocidad editable. Se reemplaza el mecanismo: no se crean Core/Welds, no se renombran Humanoids y no se copian sus bucles. Speed V1 contiene solo un enlace externo; su implementación no está incluida ni reutilizada. No se descargó ni ejecutó ese código.

## Movimiento moderno

| Parámetro | Inicial | Rango |
| --- | --- | --- |
| Fly | false | ON/OFF |
| Fly Keybind | V | Tecla de teclado sin conflictos |
| Fly Speed | 65 | 1–200 studs/s; ejemplos 25/50/65/100/150 |
| Speed | false | ON/OFF |
| Speed Keybind | G | Tecla de teclado sin conflictos |
| Walk Speed | 24 | 1–140; ejemplos 16/24/35/50/75/100/140 |

Los números editables actualizan la configuración aplicada; un valor fuera de rango se rechaza sin sustituir el último valor válido. Los límites delimitan comandos aceptados, no garantizan una velocidad física: masa, fuerza disponible, colisiones, propiedad de red y políticas del servidor afectan el resultado.

Fly utiliza una Attachment en HumanoidRootPart, LinearVelocity para el desplazamiento y AlignOrientation para estabilización con torque/velocidad angular/respuesta finitos. El modelo funciona sobre una raíz válida de R6 o R15, sin asumir LowerTorso. WASD usa la cámara; Space sube y LeftControl baja. La dirección combinada se normaliza y la respuesta depende de dt y FlySmoothing, sin incrementos por wait().

La estabilización local usa yaw de cámara y horizonte vertical del mundo. El servidor propio orienta según el movimiento horizontal validado y conserva su rumbo durante movimiento vertical/idle; no necesita recibir la CFrame completa de la cámara. FlyOrientation, FlyMaxTorque, FlyMaxAngularVelocity y FlyOrientationResponsiveness son parámetros internos editables. No se escribe directamente CFrame ni AssemblyLinearVelocity del personaje.

Al reducir Fly Speed, el comando suavizado se limita inmediatamente al nuevo máximo: conservar una velocidad residual superior podía causar rechazo de inputs y caducidad del controlador de servidor. El frenado normal al soltar las teclas conserva FlySmoothing.

Al detener o sustituir personaje/Humanoid/raíz se eliminan solamente las restricciones y Attachment propias y se restauran AutoRotate, PlatformStand y el estado capturado cuando corresponde. Speed guarda la velocidad original del Humanoid actual y restaura solo si su valor aplicado continúa vigente. Una sobrescritura externa se conserva y se informa; no hay un bucle para combatirla. Speed se pausa mientras Fly está solicitado.

WalkSpeed utiliza una propiedad float nativa. El controlador guarda por separado el valor solicitado y la lectura aplicada, tolerando únicamente diferencias finitas de hasta 1e-4. Así, la cuantización de 34.2 no produce un falso LIMITED ni escrituras repetidas; una corrección material, por ejemplo 24→7, continúa detectándose y no se sobrescribe. Los ensayos de cuantización usan dobles de almacenamiento float32, sin confirmar física nativa.

## Local, Server y estados

MISC incorpora Movement Mode: Auto, Local y Server. Local no necesita MovementBridge en Studio o en un contexto propio explícitamente permitido. LocalMovementAllowed/MovementAuthorized y los atributos de integración declaran ese contexto; no conceden autorización o replicación del servidor de otro juego.

Server necesita instalar src/cam_server/MovementServer.server.luau en ServerScriptService de una experiencia propia y ajustar grant() a sus permisos. Auto elige ese componente si está disponible; la desaparición/reemplazo del componente invalida confirmaciones anteriores y se vuelve a evaluar la ruta. Las respuestas tardías y los errores de transporte no conservan un falso ACTIVE.

| Estado | Evidencia |
| --- | --- |
| OFF | Función no solicitada o Speed pausado por Fly. |
| PENDING | Solicitada, pero esperando input, aplicación o movimiento observado. |
| LOCAL ACTIVE | Controlador local instalado y velocidad observada en la dirección solicitada; replicación no verificada. |
| SERVER ACTIVE | Solicitud propia aplicada, movimiento local coherente y velocidad medida por nuestro servidor. |
| LIMITED | Sobrescritura, rechazo/timeout o movimiento solicitado no observado dentro del plazo; no se atribuye automáticamente a anticheat. |
| UNAVAILABLE | Falta permiso, componente requerido o personaje válido. |
| ERROR | Fallo concreto de API/controlador. |

PENDING evita llamar ACTIVE a una instalación sin confirmación física o a un hover sin movimiento medido. GetMovementDiagnostics separa requested, controllerActive, effective, requestedSpeed, commandSpeed, appliedSpeed, observedSpeed y serverObservedSpeed. Los botones siguen aceptando OFF y muestran el motivo si se rechaza ON.

## Cámara, predicción y diagnóstico

V3.1 limitaba un comando interno y después lo interrumpía al llegar al objetivo/cambiar signo o salir a Grounded. La auditoría reprodujo aceleraciones aplicadas superiores al límite configurado. V3.2 conserva velocidad aplicada entre frames y utiliza frenado anticipado para pitch; la guarda vertical sigue activa entre fases cuando AngularSafety y el contexto de seguimiento están habilitados. Las llamadas matemáticas sin contexto o con AngularSafety=false conservan la política anterior.

No se añade otra EMA de posición. Smoothness sigue definiendo la respuesta solicitada; puede quedar temporalmente saturada por los límites físicos elegidos. Mantener aceleración finita puede introducir inercia y cruzar un setpoint que cambia bruscamente. Un clamp de polo, reemplazo de cámara o reinicio constituye una frontera especial: se informa mediante constraintConflict, safetyState y accelerationReference. No se promete ausencia de sobrepaso ni un límite global que abarque movimientos de otros controladores.

La anomalía vertical deja de depender de que Rising/Apex/Falling conserven el mismo nombre. Se validan cambios de velocidad entre fases, con excepciones explícitas de impulso de salto/aterrizaje e inicialización de una nueva estimación. Permanecen los límites de horizonte/adelanto de V3.1 y el reinicio ante gaps/teleports. Las fases y edades son estimaciones del cliente; no se inventa la antigüedad original de captura del servidor.

GetTrackingDiagnostics incluye yaw/pitch error, velocidades, accelerationApplied, overshootReference, cruces del objetivo, estado/pausa/pérdida y observaciones aceptadas/rechazadas. El rechazo de una muestra no libera por sí solo un jugador válido: se conserva la predicción aceptada mientras no esté obsoleta. DebugMode informa el rechazo con límite de frecuencia y los diagnósticos periódicos incluyen anomalía y horizontes usados.

## ESP y GUI

Visible Only oculta indicadores tras obstáculos por diseño. Always On Top, en un contexto autorizado, usa Highlight.DepthMode.AlwaysOnTop, Names con BillboardGui.AlwaysOnTop y caja 2D proyectada. MISC permite cambiar Display Mode, ESP Range y Unlimited Range sin agregar pestañas. El modo extendido sigue validando el contexto declarado.

Se corrigió un fallo modular: cambiar directamente VisibleOnly→AlwaysOnTop y refresh() con un renderer existente podía dejar la caja sin padre. La jerarquía ahora se prepara independientemente de crear un renderer. Adornee se actualiza al reaparecer y se valida pertenencia actual al Character. Highlights ocultos liberan sus slots; Frame/Billboard se reutilizan y no se reasignan instancias cada frame estable.

Se conservan All/Specific Player, Username, Apply y Clear. GetESPDiagnostics informa modo, rango, permisos, indicadores y referencias inválidas. Unlimited muestra solo personajes existentes en el cliente; no recupera datos excluidos por StreamingEnabled ni certifica ausencia de obstáculos no transmitidos. Las hitboxes son exclusivamente visuales.

Se mantiene la imagen configurada en LogoAssetId cuando existe un asset válido. Como aún no se proporcionó un asset ID del logo metálico, el fallback temporal permanece identificado; no se inventa un ID.

## Pruebas y ejecución

Consulta [resultados y comparación](SEDWARE_V32_RESULTS.md). Las categorías se mantienen separadas: matemática, APIs con dobles, ejecución nativa y observaciones del cliente real.

Abre studio/SedwareCamV32Test.rbxlx en Roblox Studio y pulsa Play. El lugar incluye el componente propio y un fixture exclusivo de pruebas que puede imponer WalkSpeed=7/16 desde el servidor; no se incluye en el archivo autónomo ni en el servidor de distribución normal. El runner registra desplazamiento/velocidad, restauración, respawn, rigs R6/R15, restricciones y métricas de cámara/ESP. Las pruebas físicas requieren el motor: compilar el runner no las aprueba.

Comprueba manualmente C/V/G y captura de teclas, primera/tercera persona, drag/minimizar tras respawn, Names/cajas detrás de paredes, servidor/cliente con dos jugadores y StreamingEnabled real. Conserva Output y MicroProfiler. Un escenario de Character ausente no sustituye la prueba de streaming del motor.

Este entorno Linux no proporciona Roblox Studio ni una conexión a un cliente Roblox. La publicación del código y sus regresiones no demuestra Fly/Speed/ESP en Da Hood, ni corrige el sistema de disparo de sus armas.
