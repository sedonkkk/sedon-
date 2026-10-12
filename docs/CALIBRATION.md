# Calibrar con mediciones

Ningún default describe el Revolver de Da Hood. Son parámetros iniciales del **laboratorio** con límites explícitos. Calibra de uno en uno; compara ventanas de igual duración, arma, distancia, estado y nivel de latencia. No busques un número que prometa acertar siempre.

## Orden de ajuste

1. Usa `RevolverLab` (hitscan, dispersión cero), desactiva aceleración y mantén movimiento simple. Empieza con offsets cero. Mide al menos 200 observaciones por condición; las estadísticas conservan hasta 600 registros de cada tipo, así que exporta antes de reemplazarlos. Usa **Export Measurements** en Diagnostics para imprimir JSON Lines en Studio Output; luego **Clear Measurements** antes de cada nueva condición para separar ventanas.
2. Usa RTT real o redes simuladas verificables para rangos 8–55, 55–100, 100–150 y 150–180 ms. El código recibe **RTT/2**, y los puntos de `pingCalibration` están en **segundos de un trayecto estimado**. En loopback Studio no puedes fabricar RTT real con el control Demora simulada.
3. Ajusta `latencyOffsetSeconds` en pasos pequeños (por ejemplo 0.005 s) alrededor de cero. Busca el menor RMSE en un conjunto de calibración y verifica la mejora en otra sesión/recorrido. Un offset puede compensar procesamiento no incluido en ping, pero no corrige dispersión.
4. Si el sesgo cambia con RTT, mide un offset por rango y ajusta los offsets de los cuatro puntos en Prediction, etiquetados por RTT equivalente. Para cambiar sus ubicaciones o añadir puntos, escribe puntos ordenados `{pingSeconds, offsetSeconds}` en `Settings.pingCalibration`. El módulo interpola linealmente y conserva el offset del extremo fuera del rango. Los ceros iniciales evitan inventar un ajuste sin medición.
5. Compara diferentes valores de `pingSmoothingSeconds` y del límite de cambio. Aumenta suavizado si fluctúa; redúcelo si tarda demasiado en seguir cambios sostenidos. Evita calibrar sobre ruido de una sola muestra.
6. Activa Memory y luego aceleración. Compara RMSE separado en rectas, saltos y reversas; conserva aceleración solo si mejora mediciones independientes. Un giro futuro abrupto no se conoce de antemano.
7. Usa `weaponOffsets.RevolverLab` para un sesgo residual específico del perfil, dejando fijo el offset global. No cambies ambos simultáneamente: son indistinguibles en esa condición.
8. Cambia a proyectiles. Mide velocidad y caída del sistema de disparo **que controlas** antes de introducirlas. Usa `ProjectileLab` como referencia propia (180 studs/s, gravedad cero), y compara Distance Prediction ON/OFF. No aumentes delay de hitscan por distancia.
9. Finalmente introduce dispersión angular autoritativa y obstáculos. Si RMSE de predicción es bajo pero baja la tasa de impactos, revisa dispersión, origen del tiro, geometría, cooldown, obstrucción y retrasos de registro. No concluyas que el ping es culpable.

Los registros de tiro contienen resultados físicos; los de predicción comparan la posición estimada con la trayectoria real a `sampleTime + horizon`. En un proyectil con gravedad, esta medición usa `targetPosition`, no el punto elevado de compensación. No compara con una posición en pantalla potencialmente interpolada.

## Parámetros expuestos en UI

| Parámetro | Default | Unidades y criterio |
| --- | --- | --- |
| Aim assistance | ON | Selección y orientación con RMB; ON no dispara automáticamente. |
| Auto Prediction | ON | Usa EMA de RTT/2 más calibración; OFF usa delay manual. |
| Manual Prediction | 0.08 | Segundos desde ahora; valor inicial de comparación, no convertido del script previo. No incluye la edad de la muestra. |
| Ping Smoothing | 0.8 | Constante temporal τ en segundos. Tras τ alcanza ~63% de un cambio. EMA `α=1-exp(-dt/τ)` independiente de Hz. |
| Offset global | 0 | Segundos de procesamiento residual; permite ajustes negativos limitados y aplica clamp final. |
| Offset por perfil | 0 | Segundos adicionales independientes; sesgo base del perfil en `Weapons` más override de sesión. |
| Latencia mínima/máxima | 0 / 0.35 | Segundos del componente de latencia; no acotan edad de muestra ni vuelo. Ajusta máximo tras medir tus colas y latencia. |
| Distance Prediction | ON | Anticipa movimiento durante vuelo; no aumenta hitscan por distancia. OFF mantiene vuelo/caída pero usa blanco estacionario durante él. |
| Velocity Prediction | ON | Usa velocidad; OFF toma posición observada como base, útil como baseline. |
| Acceleration Prediction | ON | Aceleración filtrada y limitada; requiere Memory y Velocity. Compara con OFF en reversas. |
| Memory Tracking | ON | Historial acotado y filtros. OFF usa velocidad instantánea con aceleración cero. |
| Weapon Profiles | RevolverLab | Modelo físico del laboratorio, con estadísticas por perfil. |
| Debug Visualization | OFF | Punto naranja local; no interviene en colisiones ni autoridad del servidor. |
| FOV | 180 | Radio en píxeles alrededor del cursor; ajusta por resolución y selección deseada. |
| Distancia máxima | 350 | Studs para selección; servidor limita tiros a 400 studs, no amplíes uno ignorando el otro. |
| Demora simulada | 0 | Segundos adicionales SOLO en entrega de snapshots, 0–0.25. Ya incluidos en edad observada. |
| Actualizaciones/s | 30 | Estimación/selección; 5–60 Hz. El servidor entrega 20 Hz: subirlo no crea muestras nuevas. |
| Reset Settings | — | Restaura defaults de sesión; los registros se conservan para comparar antes/después. |

## Parámetros avanzados en Settings.luau

| Campo | Default | Calibración y justificación |
| --- | --- | --- |
| `historyCapacity` | 12 | Muestras por objetivo; con 20 Hz cubre hasta ~0.55 s, restringido también por ventana. Aumentarlo no debe ignorar el límite temporal. |
| `historyWindowSeconds` | 0.3 | Historial reciente para estimar desplazamiento; menor responde antes a giros, mayor amortigua ruido. Guarda mínimo dos muestras. |
| `velocitySmoothingSeconds` | 0.06 | τ del filtro de velocidad; combina 75% velocidad instantánea y 25% desplazamiento reciente. Estos pesos son una heurística inicial: compara ambos métodos antes de cambiarlos. |
| `accelerationSmoothingSeconds` | 0.15 | τ del filtro de aceleración; reduce ruido de derivación. Ajusta frente a error en cambios de velocidad. |
| `maxObservedSpeedStuds` | 120 | Studs/s para rechazar muestras anómalas. El lab se mueve mucho más lento; mide máximos legítimos antes de adaptar a tu experiencia. |
| `maxAccelerationStuds` | 180 | Studs/s², cap de estimación. No interpreta una reversa instantánea como aceleración infinita. |
| `teleportSlackStuds` | 5 | Margen de discontinuidad: distancia > velocidad máxima×dt + margen reinicia historial. Ajusta con teleports y ruido medidos. Velocidad derivada aún se valida. |
| `reversalDotThreshold` | −0.2 | Producto escalar normalizado; valores menores reinician (giro >~101.5°). Ajusta si los giros bruscos acumulan inercia del filtro. |
| `maxAccelerationHorizonSeconds` | 0.18 | Solo integra aceleración estimada durante esta ventana; después conserva la velocidad alcanzada, sin continuar acelerando. Determina con pruebas de trayectoria retenidas. |
| `staleAfterSeconds` | 0.6 | Rechaza blancos cuyas muestras sean demasiado viejas. Debe admitir demora ensayada pero limitar extrapolación sin observaciones. |
| `latencySlewSecondsPerSecond` | 0.12 | Cambio máximo de delay por segundo: a 0.1 s permite 0.012 s. Compara estabilidad frente a adaptación a nuevos RTT. |
| `maxFlightSeconds` | 2 | Límite de solución balística. Server lifetime usa `min(4,400/speed)`; mantén límites coherentes si editas perfiles. |
| `pingCalibration` | 4/30/75/90 ms, offset 0 | Puntos por trayecto estimado, cubren RTT 8–180 ms. Reemplaza offsets con mediciones, conserva orden estricto. |
| `weaponOffsets` | 0 por arma | Copias independientes en cada sesión; también editables en UI. |

## Perfiles en Weapons.luau

`kind` elige `hitscan` o `projectile`; `speed` está en studs/s y solo tiene efecto con proyectiles; `gravity` es aceleración hacia abajo en studs/s²; `cooldown` es intervalo mínimo en segundos; `spreadRadians` es semicono angular de dispersión uniforme en ángulo sólido, no un porcentaje; `radius` es radio del proyectil en studs; `latencyOffsetSeconds` es sesgo base del perfil. Inicialmente `RevolverLab` tiene cooldown 0.35 s y dispersión cero; `ProjectileLab` velocidad 180, radio 0.12, cooldown 0.25 y gravedad cero. Son elecciones de ensayo explícitas, no mediciones de armas ajenas.

Si aumentas gravedad o velocidad puede no existir solución alcanzable. El predictor devuelve ausencia de solución en vez de mostrar un punto inválido. La compensación balística usa una solución de vuelo verificada numéricamente, con tolerancia residual 0.05 studs y máximo 16 refinamientos; no garantiza todas las soluciones/arcos balísticos. Usa pruebas retenidas para cambiar tolerancia y límites.

El factor de orientación de cámara (τ≈1/12 s) solo suaviza la visualización; el disparo utiliza la solución recalculada al pulsar F. Radios de blancos (2 studs), frecuencias del servidor y distancias del escenario son parámetros del banco de ensayo, no parámetros de precisión ocultos.
