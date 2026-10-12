# Compatibilidad: qué se sabe y qué falta medir

La revisión usa documentación **oficial de Roblox**, en `Roblox/creator-docs`, commit `af5f853c78b58c4ea86d62ac2345f881ac11fcec` (consultas del 11–12 de octubre de 2026). Se revisaron Player, Workspace, BasePart, Humanoid y LocalScript. No se proporcionaron fuentes autorizadas de Da Hood, una implementación de sus armas ni mediciones de una sesión real del juego; por tanto no se afirman características internas concretas.

## Información disponible mediante APIs oficiales

| Componente | Información verificable | Límite para evaluar Da Hood |
| --- | --- | --- |
| Movimiento | [`Humanoid:GetState()`](https://create.roblox.com/docs/reference/engine/classes/Humanoid#GetState) informa un estado local; posiciones sucesivas permiten estimar desplazamiento y velocidad. | Un estado no revela aceleración futura, giros, lógica personalizada o posición autoritativa del siguiente frame. No se midieron estados/velocidades específicos de Da Hood. |
| Velocidad de caminar | [`Humanoid.WalkSpeed`](https://create.roblox.com/docs/reference/engine/classes/Humanoid#WalkSpeed) es la velocidad máxima configurada en studs/s; el default del motor es 16. | No es la velocidad instantánea ni prueba que Da Hood use ese default. Cambios de input o de lógica pueden variar el movimiento observado. |
| Salto/caída | Humanoid incluye JumpPower/JumpHeight/UseJumpPower y estados; Workspace tiene Gravity. | No se conoce la configuración real del juego ni si usa trayectorias o fuerzas personalizadas. La curva de salto del banco de ensayo no representa ese juego. |
| Posición | `HumanoidRootPart.Position` o partes disponibles en el cliente. | Puede estar interpolada/retrasada. Streaming puede hacer que falte un personaje o una parte. No revela el timestamp de producción del servidor. |
| Velocidad física | [`AssemblyLinearVelocity`](https://create.roblox.com/docs/reference/engine/classes/BasePart#AssemblyLinearVelocity), studs/s; la propiedad está marcada NotReplicated. | No garantiza verdad autoritativa en un cliente remoto. OwnCharacters deriva velocidad de capturas locales y conserva su incertidumbre. |
| Latencia | [`LocalPlayer:GetNetworkPing()`](https://create.roblox.com/docs/reference/engine/classes/Player#GetNetworkPing): documentación actual indica **RTT en segundos** y permite llamadas cliente solo sobre LocalPlayer. | RTT/2 es una estimación de un trayecto, no medición de replicación, procesamiento o hit registration. Los pings históricos de una interfaz pueden usar otra convención. |
| Reloj | [`Workspace:GetServerTimeNow()`](https://create.roblox.com/docs/reference/engine/classes/Workspace#GetServerTimeNow) aproxima el reloj de servidor desde un cliente conectado. | No reconstruye timestamps que el juego no publique ni constituye una fuente segura de autoridad del cliente. |
| Impacto local | Raycast/Spherecast contra geometría disponible. | Un impacto visual local no prueba daño ni confirmación del servidor. No reemplaza el sistema de disparos del juego. |

## Ejecución de código propio

Un [`LocalScript`](https://create.roblox.com/docs/reference/engine/classes/LocalScript) es un contenedor de código que el desarrollador incorpora a su experiencia y ejecuta en cliente desde ubicaciones admitidas. Aquí se usa StarterPlayerScripts, servicios nativos y PlayerGui. Una experiencia publicada **propia** puede ejecutar este archivo cuando se incorpora a su proyecto.

Un jugador corriente no dispone de una API oficial para instalar un LocalScript arbitrario en una experiencia publicada que no puede editar. El hecho de que una API sea pública dentro de LocalScripts no proporciona esa capacidad de instalación. Cualquier ejecución de este archivo dentro de Da Hood exige una ruta de desarrollo/autorización del propietario; esta entrega no la asume ni la crea.

El payload no implementa inyección, ejecutores, hooks de metamétodos, modificaciones de remotes, lectura/escritura del entorno por APIs de ejecutores ni evasión de anticheat. Un loader separado puede descargar el único archivo mediante `game:HttpGet` y compilarlo con `loadstring` si el entorno externo ya ofrece esas capacidades; no las instala ni elude sus restricciones. El script tampoco descubre o llama remotes del juego. F y RMB actúan sobre el **laboratorio local**, no sobre una herramienta real del juego.

## Revolver: datos que siguen desconocidos

No se verificaron hitscan frente a proyectil, velocidad/caída, dispersión, intervalos de disparo, origen de rayos, selección de hitboxes, timestamps, rewind ni reglas de confirmación del Revolver de Da Hood. El perfil llamado **Revolver** tiene campos editables para ensayar supuestos, con defaults copiados del perfil RevolverLab anterior. El nombre no convierte esos supuestos en datos del juego.

La antigua cifra `13.371600151062012` permanece sin interpretación física ni conversión. Si se obtiene la fórmula original autorizada, podrá analizarse en una tarea posterior; no se ha inferido a partir de unos pocos impactos.

## Diferencias del banco de ensayo

| Prototipo original | Archivo autónomo | Juego real sin instrumentación autorizada |
| --- | --- | --- |
| Trayectorias del servidor y snapshots propios 20 Hz. | Trayectorias locales conocidas; observaciones controladas y loop de muestreo configurable. | Solo lo que el cliente recibe; no se conoce frecuencia/timestamp/interpolación interna. |
| Servidor propio valida cooldown/origen/impactos. | Tiros locales simulados; no daño ni confirmación del servidor. | Validación y procesamiento de disparos desconocidos. |
| Eventos propios de snapshots/telemetría. | Un solo LocalScript, sin remotes ni módulos externos. | No hay permiso o contrato de integración proporcionado. |
| Medición original de posición en el horizonte declarado. | Referencia de llegada modelada independiente del delay elegido; error firmado para calibración. | Falta una referencia de llegada e impacto autoritativa verificable. |
| Geometría y parámetros definidos por el laboratorio. | Perfiles editables y experimentos comparativos. | Dispersión, hitboxes y reglas reales sin verificar. |

## Cómo obtener evidencia útil con permiso

En una experiencia propia o una copia autorizada, registra posición, velocidad observada, estado y timestamps en movimientos laterales, velocidad sostenida, saltos, caídas y reversas. Instrumenta el servidor para conocer posición real y tiempos de disparo/impacto. Distingue RTT, edad de observación, cola de disparo y vuelo; mide cada etapa en la misma base temporal.

Empieza con disparos de dispersión cero contra trayectorias reproducibles. Compara automático/manual y offsets por rango en condiciones iguales; después añade dispersión y cambios bruscos. Valida correcciones en otro recorrido o sesión. Sin esos datos puede evaluarse el predictor matemático, pero no concluirse que reproduce o mejora la mecánica real de Da Hood.

## Auditoría de dependencias de esta versión

| Función o módulo | Dependencia | Comprobado / pendiente |
| --- | --- | --- |
| Settings, Weapons, Latency, MotionHistory, Predictor, Ballistics, Geometry, Diagnostics | Luau y operaciones vectoriales compatibles; incorporados al archivo. | Pruebas matemáticas y equivalencia con el original pasan; no requieren escenario ni remotes. |
| Configuration / Calibration | Tablas Luau; residuo de una medición con referencia conocida. | Copias, tipos/rangos, carga atómica, comparaciones y aprendizaje vigente verificados. Sin verdad conocida no hay calibración automática ni RMSE nuevo. |
| Interface | Instance, Color3, UDim/UDim2, Enum, PlayerGui, señales de entrada y propiedades de camera/viewport. | Eventos/carga/limpieza verificados con dobles; renderizado y entrada del cliente real pendientes. Ninguna llamada IsStudio es obligatoria. |
| Runtime | Lectura segura de constructores, servicios y métodos nativos; RunService:IsClient. | Casos de APIs ausentes/contexto erróneo y carácter opcional de ping/Spherecast/cámara probados. Presencia no significa certificación de un ejecutor. |
| Session observada | Players:GetPlayers, HumanoidRootPart.Position, Humanoid:GetState, cámara, reloj y raycast locales. | Arranque y propiedad de recursos probados con dobles; muestreo/entrada/replicación dentro de Da Hood pendientes. No se cambian remotes o salud. |
| Trayectorias/mediciones del simulador | Escenario analítico y transporte modelado definidos por nosotros. | Fórmulas/referencia independiente probadas; no equivalen a mecánicas del juego. |
| Revolver y tiro local | Parámetros configurables; raycast o vuelo propio, dispersión propia. | No disparan el Revolver real ni prueban confirmación del servidor. Una integración real necesitaría documentación y contrato de disparo autorizados. |
| Loader externo | `loadstring` y `game:HttpGet` proporcionados por el host. | Template compila; verificación de distribución prepara un loader solo con un Raw real de bytes idénticos. No disponible por defecto en LocalScript de cliente, ni probado en un ejecutor real. |

El arranque automático selecciona observación de personajes y RTT del cliente, con capacidades y errores visibles. El escenario simulado y sus herramientas se conservan como opción. Resolver no se anuncia como capacidad: la información oculta no es una entrada verificable del modelo.
