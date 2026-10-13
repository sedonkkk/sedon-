# Resultados SEDWARE V3

Estado: **CLI ejecutado; Roblox Studio/Da Hood no ejecutados**. Resultados sintéticos, con ruido determinista y un giro inicial de 45°. Las filas Fixed usan el controlador original archivado de V2. Los promedios siguientes se calculan sobre los mismos 108 escenarios por técnica (9 trayectorias × 4 FPS × 3 RTT), con política Manual y filtro Memory. No equivalen a impactos ni a una prueba multijugador real.

| Controlador | Error medio frente al objetivo actual (°) | Error medio frente al setpoint predicho (°) | Error de predicción (studs) | Adquisición media a <1° del setpoint (s) |
|---|---:|---:|---:|---:|
| Fixed | 1.4241 | 0.4307 | 0.6088 | 0.1337 |
| Adaptive | 0.9996 | 0.7897 | 0.6088 | 0.1845 |
| Critical | 2.6245 | 3.5864 | 0.6088 | 1.1268 |

Un error menor frente a la posición actual puede cancelar parte del adelanto intencional. Adaptive aumenta el error respecto al setpoint; Critical adquiere más despacio con las ganancias/límites actuales. Estos resultados justifican conservar Fixed por defecto, no proclamar superioridad universal.

| Filtro (controlador Fixed, Manual) | Error medio de predicción (studs) |
|---|---:|
| Memory | 0.6088 |
| AlphaBeta | 0.6003 |
| OneEuro | 1.4374 |

La variante OneEuro añade retraso y empeora la predicción en estos escenarios. AlphaBeta tampoco se activa por defecto. Ninguno sustituye automáticamente a Memory.

| Escalón angular, Memory, Manual, RTT 0 | 30 FPS | 60 FPS | 120 FPS | 144 FPS |
|---|---:|---:|---:|---:|
| Fixed adquisición (s) | 0.100000 | 0.100000 | 0.091667 | 0.090278 |
| Adaptive adquisición (s) | 0.100000 | 0.083333 | 0.075000 | 0.076389 |
| Critical adquisición (s) | 0.466667 | 0.450000 | 0.441667 | 0.444444 |

El muestreo limita la resolución temporal de adquisición. El modo crítico conserva velocidad/aceleración entre frames y aplica saturación explícita: su respuesta limitada no es exactamente idéntica entre FPS. Todas las filas del laboratorio verificaron roll < 0.000001° en aritmética CLI. El runner nativo comprueba CFrame real por separado; no se ha ejecutado.

## CPU antes y después

Mismo host Luau CLI, dobles de eventos/API, 1200 frames programados a 60 Hz por condición. Estas cifras son **tiempo de CPU de la simulación**, no tiempo de render Roblox ni FPS observados. Cada versión usa su propio bundle real; V2 procede del commit 43612248fc40e2750678873acda642ab41f85c35.

| Jugadores simulados | Cam Lock | V2 ESP OFF (ms/frame) | V2 ESP ON | V3 ESP OFF | V3 ESP ON |
|---:|---|---:|---:|---:|---:|
| 5 | OFF | 0.004069 | 0.007942 | 0.004765 | 0.009634 |
| 5 | ON | 0.062437 | 0.074370 | 0.067898 | 0.072155 |
| 15 | OFF | 0.004157 | 0.015989 | 0.005047 | 0.017847 |
| 15 | ON | 0.061519 | 0.075181 | 0.068005 | 0.087512 |
| 30 | OFF | 0.004529 | 0.029764 | 0.006183 | 0.027614 |
| 30 | ON | 0.068846 | 0.094310 | 0.070167 | 0.102305 |

No hay mejora consistente del tiempo total del frame en esta ejecución. Las métricas y disponibilidad añaden coste, y los tiempos del host fluctúan. Las optimizaciones verificables eliminan resynchronización redundante y asignación del registro bloqueado, pero eso no demuestra mejora global de FPS. El runner de Studio registra FPS ESP ON/OFF y coste nativo para 5/15/30 modelos; sigue pendiente.

Los invariantes del benchmark verifican que no crecen las instancias/conexiones durante la actualización estable y que Unload elimina las conexiones/bindings de cada cliente. Esto acota recursos poseídos; no demuestra ausencia de toda fuga posible del motor.

## Pruebas ejecutadas

| Suite | Casos | Assertions | Resultado |
|---|---:|---:|---|
| Cam/V3: configuración, cámara, roll, GUI, V2 regresión, lifecycle, protocolo propio de servidor y loader | 116 | 123243 | 0 fallos |
| Proyectos originales DH Prediction + Pink/multiarmas | 342 | 80528 | 0 fallos |
| Total de regresión CLI/dobles | 458 | 203771 | 0 fallos |
| Calibration Lab | 1944 escenarios | Validación de métricas finitas y roll por fila | Completado |
| CPU V2/V3 | 24 condiciones | Recursos estables y limpieza | Completado |
| Compilación Cam | 40 archivos | Luau oficial | Aprobada |
| Roblox Studio: física, GUI/ESP visual, FPS | No ejecutada | Runner preparado | Pendiente |
| Da Hood original | No ejecutada | Sin integración de movimiento/armas de terceros | No verificado |

## Reproducción y datos completos

- [1944 filas del laboratorio](results/SEDWARE_V3_CALIBRATION.csv): errores actuales/setpoint/futuro, adquisición, seguimiento, roll, cambios de signo, sobrepaso y lag.
- [24 condiciones CPU](results/SEDWARE_V3_CPU.csv): incluye cámara ON/OFF y ESP ON/OFF.
- `python3 scripts/calibrate_cam.py` reconstruye ambos CSV en `build/`; requiere que el commit V2 esté disponible en Git local.
- `python3 scripts/check_cam.py`, `python3 scripts/check.py`, `python3 scripts/check_pink.py` ejecutan las regresiones.
- [Guía y comprobación nativa pendiente](SEDWARE_V3.md).
