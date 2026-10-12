# Validación realizada

Las verificaciones se ejecutaron en la máquina Linux de desarrollo, con Luau oficial 0.695 (`1f6ff5d6f0072f2fab2adf35d1ffbaae7d848ad0`) y Python 3.12.14. No hubo ejecución del motor Roblox ni de Studio.

Comando reproducible: `bash scripts/setup_cloud.sh`, o `python3 scripts/check.py` si las herramientas están instaladas. El setup se ejecutó sobre las herramientas ya compiladas para comprobar su reutilización sin cambiar fuentes o dependencias.

- Compilación de **23 archivos Luau**: 16 fuentes modulares, 5 archivos de pruebas, el archivo autónomo y Loader.template.lua.
- **36 pruebas originales**, 6546 aserciones, 0 fallos.
- **39 pruebas del archivo autónomo**, 68 982 aserciones, 0 fallos: equivalencia numérica del predictor original con el incorporado, Memory, ping 8/60/150/180 ms, perfiles, carga atómica, rechazo de datos no finitos, RMSE separado y aprendizaje vigente.
- **21 pruebas de GUI e integración con dobles explícitos**, 367 aserciones, 0 fallos: eventos de los controles reales, guardar/cargar, ocultar/restaurar, arrastre, cerrar y repetir init, conexiones, referencia temporal física independiente y cambio de fuente. El doble de JSON transporta objetos, no verifica el serializador JSON de Roblox.
- **Total: 96 pruebas, 75 895 aserciones, 0 fallos.** El runner conserva el estado de salida y rechaza ejecuciones sin pruebas.
- Generación de `DaHoodPrediction.lua` con 13 módulos incorporados, importaciones internas y hashes de fuentes. `build/DHPredictionLab.rbxlx` contiene ese único LocalScript con igualdad exacta después de serializar/deserializar XML.
- Empaquetado del prototipo original de **11 scripts** en `build/AimLab.rbxlx`; comprobación de igualdad exacta de fuentes tras serializar/deserializar XML.
- Historial: datos inválidos/no finitos, orden temporal, capacidad, teleport, salto/caída y reversa lateral dominada por velocidad vertical.
- Latencia: EMA independiente de frecuencia, límites de cambio, manual, interpolación y offsets independientes por arma.
- Predicción: edad + delay + vuelo, hitscan independiente de distancia, blancos inalcanzables y muestras vencidas.
- Aceleración: integración numérica independiente antes/después de la ventana de aceleración, continuidad al pasar a velocidad constante.
- Balística/geometría: residuo de interceptación/caída, contacto en segmentos finitos, tangencias, extremos, casos degenerados y cruces rápidos entre muestras.
- Diagnósticos: RMSE con denominador propio, datos acotados, rechazos excluidos y aciertos al blanco equivocado separados de aciertos al blanco elegido.

## Benchmark de trayectoria simulada

240 observaciones por condición (1440 en total), con jitter determinista, desplazamiento lateral, saltos y reversas. El predictor recibe únicamente datos disponibles en el instante observado; el runner calcula verdad futura después de predecir. La posición observada sin predicción se compara con esa **misma** verdad futura. Es un baseline simple, no una comparación con el script original, cuyo algoritmo se desconoce.

| RTT nominal ms | RMSE predicción studs | RMSE posición observada studs | Error máximo predicción studs |
| ---: | ---: | ---: | ---: |
| 8 | 0.0615 | 0.1747 | 0.2690 |
| 16 | 0.0865 | 0.2930 | 0.4075 |
| 32 | 0.1412 | 0.5534 | 0.6919 |
| 60 | 0.3228 | 1.0210 | 2.3733 |
| 150 | 1.4464 | 2.4202 | 5.1724 |
| 180 | 1.6722 | 2.8586 | 5.7607 |

RMSE agregado: **0.9150** frente a **1.6070 studs**. Esto demuestra comportamiento acotado y mejora en este recorrido simulado, no una precisión universal ni un porcentaje de impactos real. Los errores aumentan en reversas con latencia alta.

El benchmark usa un snapshot por paso de 30 Hz y movimiento sinusoidal/por tramos; el servidor del lugar publica a 20 Hz con sus propias trayectorias analíticas. No son el mismo escenario ni se pretende que el resultado numérico del benchmark aparezca igual en Studio.

## Pendiente

Las comprobaciones funcionales dentro del motor de [STUDIO.md](STUDIO.md) y [STANDALONE.md](STANDALONE.md) no se ejecutaron desde esta máquina: presentación de GUI, entrada de teclado/ratón, arranque real, raycasts/Spherecast del motor, replicación y pruebas con dos clientes. No se midió Da Hood ni se integró su Revolver. No se afirma que la aplicación esté validada dentro de Roblox hasta completar esas comprobaciones.

El usuario informó que el prototipo original funciona. Las verificaciones propias aquí se limitan a compilación, matemática, empaquetado y eventos con dobles. La presentación y física de la **nueva versión autónoma** quedan pendientes de Studio; las pruebas con dobles no equivalen a renderizado ni a conexión con Da Hood.

## Arranque en clientes y distribución

Los nuevos casos cubren auditoría de capacidades sin crear objetos/conexiones, métodos obligatorios ausentes, ping/Spherecast opcionales, ausencia de PlayerGui, contexto servidor, arranque automático fallido sin excepción sin controlar, script no estándar, preservación de la sesión existente y limpieza de una construcción fallida. Una excepción de frame se informa una vez, pausa las actualizaciones y mantiene Unload operativo. Las advertencias de tres casos de fallo intencionado son resultados esperados, no errores de la suite.

Loader.template.lua es sintácticamente válido. El preparador de distribución empaqueta sin red por defecto y verifica ZIP, copias y hashes. Solo una URL Raw real con HTTPS y bytes coincidentes permite generar Loader.lua y el comando definitivo. Los ensayos de validación de URL/respuestas simuladas no prueban HTTP de un ejecutor ni publicación real.

**Sin verificar:** un ejecutor externo específico, renderizado del motor, comportamiento real de Da Hood, Revolver real y hit registration. El archivo fue publicado posteriormente en `sedonkkk/sedon-`, rama `main`, con autorización del usuario. Se comprobó el Raw HTTPS del commit `47a278a38ae3b7ce48fa2184bcf7ff0bd12bcedf` y su igualdad de bytes con el archivo local; se generó y compiló Loader.lua. Esta comprobación verifica la distribución, no la ejecución dentro del juego.
