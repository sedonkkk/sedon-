# DaHoodPrediction.lua · DH PREDICTION LAB

Versión autónoma del predictor existente. El generador incorpora **los ocho módulos originales** y cinco módulos de integración en un único archivo. Reescribe únicamente sus imports; conserva las fórmulas, filtros Memory, límites, perfiles base y pruebas originales. No descarga ni evalúa código externo durante la ejecución.

El nombre del archivo identifica este laboratorio de evaluación. Ahora incluye un arranque con auditoría de capacidades del cliente y puede inicializarse desde código Luau proporcionado por un entorno externo compatible; ese entorno no se incluye ni se ha probado aquí. [Loader y distribución GitHub](DISTRIBUTION.md). No proporciona una integración con las armas, comunicaciones o lógica interna de Da Hood. [Compatibilidad y datos verificables](DA_HOOD_COMPATIBILITY.md).

## Instalación con una ejecución

**Opción directa:** abre `build/DHPredictionLab.rbxlx` en Roblox Studio y pulsa **Play**. Contiene una baseplate, un spawn y **un solo LocalScript** con el contenido completo de `DaHoodPrediction.lua`. No necesita ModuleScripts adicionales, servidor del prototipo original, remotes, assets externos ni archivos locales.

**En tu propia experiencia:** crea un `LocalScript` en `StarterPlayer → StarterPlayerScripts`, pega todo `DaHoodPrediction.lua` y pulsa **Play**. Puede ejecutarse también en una versión publicada de esa experiencia, dentro del cliente, con los permisos de desarrollo correspondientes. No lo coloques en un Script de servidor ni uses Run sin cliente.

La función pública `API.init(options)` crea una sesión; `API.tryInit(options)` devuelve `sesión, informe` o `nil, informe` sin lanzar un error de compatibilidad. `API.checkCompatibility()` inspecciona capacidades sin crear objetos ni conexiones. En Roblox el archivo inicia automáticamente con `OwnCharacters` y ping del cliente (`useSimulatedPing=false`); cambia a `Simulated` y ping simulado en SETTINGS/MAIN para usar el banco de ensayo. Un error de arranque se guarda en `API.compatibility` y se informa mediante `warn`, o `print` como respaldo. Fuera de Roblox devuelve una API con los módulos matemáticos disponibles, pero un intérprete Luau sin servicios del motor no puede crear la GUI ni la cámara. No se incluyen herramientas para insertar código en experiencias de terceros.

Una nueva ejecución válida construye primero la nueva sesión y solo después emite el evento local de cierre de la anterior, desconecta conexiones y retira sus propios objetos. Si la construcción falla, limpia sus objetos parciales y mantiene usable la sesión anterior. Una configuración inicial inválida o una capacidad obligatoria ausente tampoco destruyen la sesión que ya funciona. Si un frame falla, la sesión pausa el seguimiento, detiene la asistencia, oculta indicadores y conserva el menú con el error para poder descargarla con Unload. **Close** o **Unload** limpian la sesión completa. Ocultar y minimizar conservan su ejecución.

## Controles

- **F** o **DISPARAR:** tiro local de ensayo; no activa herramientas reales, envía remotes, causa daño ni modifica salud.
- **RMB:** orientación suave de la cámara hacia la solución del blanco retenido en FOV.
- **Enable:** selección y asistencia ON/OFF. **AimType → Memory** conserva el historial; Velocity usa estimación instantánea.
- **Position Indicators:** esfera turquesa para posición visible del blanco y azul para el punto de apuntado suavizado. La compensación de caída puede separar el punto de apuntado de la posición predicha del blanco.
- **Hide Menu / ↓:** oculta el panel; **SHOW DH LAB** lo restaura. **−** minimiza; arrastra el encabezado para moverlo. **× / Unload** cierran y limpian.

El menú tiene MAIN, PREDICTION, WEAPONS, DIAGNOSTICS y SETTINGS. Incluye predicción automática/manual, ping, velocidad, distancia, aceleración, Memory, suavizado, perfiles físicos, correcciones por rango y comparación manual/automática.

`Prediction Smoothing` controla **el indicador y la cámara**; las estimaciones se filtran con los módulos de velocidad/aceleración/latencia originales. Un disparo recalcula la solución matemática al pulsarlo; no usa el marcador visual retrasado por suavizado.

## Fuentes de datos y de latencia

| Opción | Datos | Qué se puede medir |
| --- | --- | --- |
| `Simulated` | Tres trayectorias locales por tramos, con reversas, salto/caída y timestamps conocidos. | Error frente a verdad matemática, comparación de modos y tiros de ensayo. |
| `OwnCharacters` | Personajes disponibles en una experiencia propia; `HumanoidRootPart.Position` y `Humanoid:GetState()`. Velocidad derivada de posiciones recientes. | Observación local y predicción. No hay verdad autoritativa futura, por lo que no se genera RMSE ni calibración automática. |
| `Use Simulated Ping = ON` | RTT editable en ms; default 90. | Banco de ensayo con condiciones conocidas. El HUD lo etiqueta como **simulado**. |
| `Use Simulated Ping = OFF` | `LocalPlayer:GetNetworkPing()`, protegido con `pcall`. | RTT que la API reporta; si no está disponible, el HUD lo muestra y el input de ping es cero. Manual sigue disponible. |

La documentación actual define la API como RTT en segundos. Se divide por dos para una **estimación** de un trayecto, suponiendo simetría. No se afirma que ese valor mida procesamiento, edad de replicación o latencia de un arma real.

En `Simulated`, las muestras se toman en `ahora − RTT/2 − demora de observación`; sus timestamps conservan ese instante. El tiro local arranca tras el transporte **modelado** RTT/2. Ambas demoras son parte del banco de ensayo, no tráfico real del disparo. El predictor compensa la edad de la muestra y añade el delay de apuntado. No se añade nuevamente la demora de observación al ping.

En `OwnCharacters` solo se conoce el instante de captura local: el timestamp no revela cuándo el servidor produjo la posición replicada ni su interpolación. Ajustar un offset no garantiza recuperar información ausente. F usa raycasts/proyectiles locales de diagnóstico y **no representa** hit registration o daño del servidor.

## Perfiles Revolver, Default y Custom

Se crean copiando los perfiles originales, con ajustes **independientes**:

- **Revolver:** parte del RevolverLab existente, inicialmente hitscan, dispersión cero y cooldown 0.35 s. Estos valores son supuestos del laboratorio, no mediciones de Da Hood.
- **Default:** copia independiente del mismo modelo base.
- **Custom:** parte de ProjectileLab: 180 studs/s, gravedad cero, radio 0.12 studs y cooldown 0.25 s; todo editable.

Cada perfil conserva su propio `manualDelaySeconds`, `latencyOffsetSeconds` y `rangeOffsets.close/medium/long`. Se puede cambiar hitscan/proyectil, velocidad, gravedad, dispersión en radianes, radio e intervalo entre tiros. Un proyectil requiere velocidad positiva; los ajustes inválidos se rechazan sin cambiar la configuración vigente.

Los rangos son `<40`, `40–120` y `≥120` studs. Sus offsets iniciales son cero. Son correcciones **residuales calibradas**, no multiplicadores arbitrarios de distancia. Hitscan mantiene vuelo cero; Distance Prediction solo anticipa movimiento durante el tiempo de vuelo de un proyectil.

Los aliases `core.weapon`, `core.weaponOffsets.RevolverLab/ProjectileLab` y `core.manualDelaySeconds` se conservan para compatibilidad del módulo base. En la versión autónoma se usan los valores del **perfil activo**; edita los campos `profiles` del JSON o los controles de WEAPONS. Los puntos de calibración del ping siguen disponibles en `core.pingCalibration`, con las unidades de [CALIBRATION.md](CALIBRATION.md).

## Calibración y comparación

El predictor principal y los comparadores automático/manual comparten **el mismo historial Memory**, pero conservan filtros de delay independientes. Se toman pares de mediciones a 5 Hz. Los resultados de comparación corresponden al perfil y rango actuales, con ventana de hasta 120 registros por combinación (incluye ambos modos).

La referencia de cada medición es `instante de ensayo + transporte modelado + tiempo de vuelo`. **No se calcula desde el delay o el horizonte elegido por el predictor**: un offset incorrecto puede causar un error real respecto del modelo. La compensación de gravedad se retira al comparar la posición física predicha del objetivo.

La recomendación temporal usa el residuo firmado:

```text
residuo = posición_real_en_referencia − posición_predicha
corrección_segundos = residuo · velocidad / |velocidad|²
```

Solo muestras automáticas, con velocidad suficiente (>2 studs/s), mismo estado de movimiento y dirección concordante alimentan el aprendizaje. Saltos de estado y reversas conservan sus errores en RMSE pero no se usan como sesgo de latencia. La proyección es una aproximación local: filtrado, aceleración, vuelo o errores de modelo también pueden influir; no prueba que la causa sea ping.

La corrección usa EMA de 2 s y cap ±0.15 s. Requiere 20 muestras entrenables vigentes y caduca tras 5 s sin actualización. **Apply Calibration Suggestion** aplica como máximo ±2 ms por pulsación, al offset del rango activo. **Adaptive Calibration** aplica ese paso como máximo una vez por segundo cuando está activo Auto Prediction; viene OFF. No entrena con muestras manuales ni blancos sin verdad conocida.

Los cambios de condiciones físicas, latencia, perfil o fuente reinician la ventana de mediciones. Cambios de visualización/selección pueden conservarla. La calibración adaptativa conserva su aprendizaje entre pasos graduales. Exporta resultados antes de cambiar condiciones y usa **Clear Measurements** para iniciar otra ventana.

Para comparar, mantén el mismo perfil/rango y una condición fija durante al menos 20–30 s; registra muestras de rectas, reversas y saltos por separado. No interpretes una sola muestra o tasa de tiros como prueba universal de precisión. Dispersión y obstáculos se registran aparte del error de predicción.

## Guardar y cargar

**Save Configuration** genera JSON versionado en el campo editable de SETTINGS. Selecciónalo y cópialo para conservarlo donde prefieras; no se escribe al disco ni se usa DataStore. Para cargar, pega el envelope completo y pulsa **Load Configuration**. Hay límite de 64 KiB, validación de tipos/rangos/campos y carga atómica. Un JSON inválido conserva la sesión actual.

**Export Measurements** usa el mismo campo para JSON Lines con configuración, resumen y registros del predictor principal/tiros locales. Los RMSE comparativos por perfil/rango se muestran en DIAGNOSTICS. Reset restaura defaults; Unload retira la GUI, objetos de ensayo, indicadores, colas y conexiones.

Si prefieres un default dentro del archivo, asigna a `INITIAL_CONFIGURATION` una tabla de configuración (el contenido de `envelope.configuration`, no el envelope). La ejecución la valida antes de reemplazar una sesión existente. Esa edición local del generado se sobrescribe al regenerar; conserva tu JSON aparte.

## Desarrollo y comprobaciones

```sh
python3 scripts/build_standalone.py  # genera el .lua y el lugar de un LocalScript
python3 scripts/check.py             # verifica, compila y prueba ambos formatos
```

El generador no necesita Roblox ni dependencias Python externas. Las pruebas verifican que el archivo coincida con los módulos y fallan si está desactualizado; no sobrescriben fuentes. Tras editar módulos, regenera explícitamente el archivo antes de probar. El manifiesto `build/standalone-manifest.json` registra hashes de los módulos incorporados. Las fuentes originales siguen en `src/shared`, `src/client` y `src/server`; las nuevas son `src/standalone`. `build/AimLab.rbxlx` continúa siendo el prototipo cliente/servidor original.

Las comprobaciones automáticas incluyen las pruebas anteriores, equivalencia de los cálculos incorporados, perfiles, Memory, ping, configuración, calibración y eventos/limpieza de GUI con dobles explícitos. [Resultados y pendientes](VALIDATION.md).

**Prueba real pendiente:** en Studio verifica Play, visualización/resoluciones, cursor y RMB, los tres perfiles, disparos/collisions, cambiar Simulated/OwnCharacters con dos clientes propios, guardar/cargar y Stop → Play / ejecución repetida. Esta máquina Linux no ejecuta Studio; los dobles no validan renderizado, raycasts del motor o replicación real.

## Auditoría del cliente y ejecución externa

Las fórmulas, Memory y perfiles no dependen de Studio. GUI, entrada, cámara, posiciones, clock y raycasts requieren servicios nativos de cliente; se usan también en experiencias publicadas cuando el entorno tiene acceso. `Runtime.luau` verifica su presencia antes de cargar Session/Interface; no instala permisos ni modifica sistemas de seguridad.

Si faltan `PlayerGui`, contexto de cliente, constructores, entrada, JSON, raycast o reloj, se informa la operación que falta y no se reemplaza una sesión existente. `GetNetworkPing`, `CurrentCamera` y `Spherecast` son capacidades opcionales: la GUI/matemática permanecen disponibles. Sin cámara la selección espera; sin ping puede usarse manual o RTT simulado; sin Spherecast los tiros locales de proyectiles con radio se rechazan y radio cero permite raycast. No se declara éxito de una función que falta.

La auditoría comprueba presencia de métodos/servicios, no certifica su funcionamiento en un ejecutor real. Los errores posteriores se informan y pausan la actualización. No depende de `getgenv`, `gethui`, CoreGui, APIs de archivos o hooks. El contexto `script` puede faltar o ser un objeto no estándar: la propiedad de cierre por LocalScript es opcional; el dueño principal sigue siendo el evento local del menú.

No hay un Resolver nuevo: Memory ya filtra anomalías y reinicia ante discontinuidades, pero no reconstruye estado oculto, desincronización o datos que el servidor no publica. No se añade un botón que aparente hacerlo.
