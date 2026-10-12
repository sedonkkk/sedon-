# SEDWARE: corrección de Camera Roll

Se modifican CameraController y su diagnóstico interno; GUI, branding, notificaciones, selección, predicción y los siete valores iniciales se conservan. El archivo autónomo y los lugares de Studio se regeneran a partir de los módulos originales.

## Causa y evidencia

`_stableUp()` proyectaba el UpVector anterior sobre el plano de la nueva dirección. Esa operación conserva orientación transportada, no un horizonte nivelado respecto al eje Y global. Por ejemplo, pasar de yaw 90°/pitch 45° a yaw 180°/pitch 0° conserva un UpVector diagonal y deja unos 45° de roll. `lastFrame` realimenta esa orientación; `CFrame:Lerp` tampoco elimina el roll heredado ni garantiza nivelación entre dos poses con cambios simultáneos de yaw y pitch.

Una reproducción con el controlador publicado anteriormente y dobles explícitos recorrió una vuelta del objetivo `(100*sin(t), 40, -100*cos(t))`: terminó con aproximadamente **133.47° de roll con Smoothness=0**, y **132.92° con 0.405**. Es evidencia numérica del defecto, no una medición dentro de Da Hood. Las pruebas anteriores verificaban finitud y ortogonalidad; esas propiedades también se cumplen en una cámara inclinada.

## Cambio

Se eliminan `_stableUp` y la interpolación de CFrames. Al comenzar o reemplazar una cámara se extraen yaw/pitch de su LookVector, ignorando la inclinación lateral. Después se retienen únicamente esos dos escalares. La orientación de cada frame se construye con:

```text
Look  = (sin(yaw)*cos(pitch), sin(pitch), -cos(yaw)*cos(pitch))
Right = (cos(yaw), 0, sin(yaw))
Up    = (-sin(yaw)*sin(pitch), cos(pitch), cos(yaw)*sin(pitch))
```

Esto usa Y global como eje vertical: `Right.Y=0` y `Up.Y>=0` con pitch limitado a ±90°. `CFrame.fromMatrix(posición_actual, Right, Up, -Look)` evita restar posiciones grandes para recuperar una dirección de longitud uno; también permite mirar exactamente arriba/abajo sin un producto cruzado casi nulo.

Yaw recorre la diferencia más corta al atravesar ±180°. Pitch se interpola por separado con el mismo alpha temporal anterior. Smoothness, Prediction X/Y, Cam Prediction, Hit Part y Radius mantienen sus valores. El controlador utiliza siempre la posición actual de Roblox, sin tocar CameraSubject, CameraType, Focus ni el personaje. Cambios de objetivo, OFF, Unload y reemplazo de CurrentCamera limpian los estados angulares.

## Polos

Directamente arriba/abajo, el yaw y el roll de Euler no tienen una definición única. El controlador conserva el yaw previo y construye una base horizontal estable. Una pequeña banda con histéresis (`horizontal / distancia <= 0.0001` para entrar; `<= 0.0002` para seguir dentro) evita que ruido mínimo cambie el heading. Su tolerancia geométrica de puntería es de hasta unos 0.023° aparte de la suavidad elegida.

Al salir del polo, un objetivo que lo cruza puede exigir un cambio de yaw de 180°. Durante esa transición, y a menos de 3° de la vertical, se limita el giro de yaw a 720°/s según deltaTime. Fuera de ese caso se conserva el alpha original; no se añade otro filtro general. Cerca de un polo existe una transición de puntería deliberada: orientación globalmente continua, puntería instantánea exacta y roll cero no pueden garantizarse simultáneamente para todo cruce del cénit.

## Pruebas

`python3 scripts/check_cam.py` pasa **85 casos y 116.433 comprobaciones**. La compilación oficial incluye el controlador, el archivo autónomo, el loader y el runner nativo. Las nuevas regresiones miden ejes/horizonte en cada frame, no solo un campo de diagnóstico:

- Caminar a izquierda/derecha, saltar, caer, seis vueltas circulares y pasar detrás.
- Mirar directamente arriba/abajo, ruido cerca del polo, cambios de 180° y wrap en ambas direcciones.
- Roll inicial de hasta 180°, activación repetida, cambio de cámara/perspectiva y conservación de posición.
- Respuesta comparable a 30, 60, 120 y 144 FPS con deltas programados.
- GUI y valores intactos, Memory/predicción activos, diagnóstico opcional, limpieza y ausencia de conexiones duplicadas.

Los 342 casos de DH PREDICTION LAB/PinkDotLock también pasan. Estas comprobaciones usan matemáticas y dobles de APIs. **No se ha ejecutado Roblox Studio ni Da Hood en este entorno Linux; no se considera confirmada todavía la corrección dentro del motor.**

## Comprobación nativa preparada

Abre [studio/SedwareCamRollTest.rbxlx](../studio/SedwareCamRollTest.rbxlx) en Studio y pulsa Play. El lugar contiene el mismo archivo autónomo como ModuleScript y [CamRollRegression.client.luau](../tests/studio/CamRollRegression.client.luau) como LocalScript. El runner imprime `[SEDWARE][NativeRoll][PASSED/FAILED]` y un SUMMARY con 12 escenarios.

Usa Camera/CFrame reales, prueba posiciones grandes y roll inicial, ejecuta la comparación con deltaTimes programados y comprueba además 24 frames reales con un binding después de Camera. Los deltas programados no fuerzan ni miden el FPS real del motor. El runner limpia sus cámaras/bindings; no integra armas ni Da Hood. Hasta ejecutarlo, no existe un resultado nativo PASS.

Para comprobar selección real y percepción del seguimiento, abre [studio/SedwareCamLock.rbxlx](../studio/SedwareCamLock.rbxlx) con dos clientes, adquiere al otro jugador y repite los movimientos mirando el horizonte. Apaga/enciende Enable y alterna primera/tercera persona; confirma que la cámara normal recupera el control y que no aparecen inclinaciones.

## Diagnóstico opcional

Config incluye `CameraDebugMode=false` y `CameraDebugInterval=0.5`. Puedes habilitarlo desde el archivo o mediante `api.configure("CameraDebugMode", true)`. La consola registra yaw, pitch, roll, targetAngle, deltaTime, angularError y estado; los ángulos están en grados. `api.session.controller:GetDiagnostics()` devuelve una copia de esos datos. El diagnóstico no añade controles ni envía información a servidores externos.

## Archivo publicado

[SedwareCamLock.lua Raw del commit corregido](https://raw.githubusercontent.com/sedonkkk/sedon-/64678f60e84762cb9cbc29df6ee86f7395059254/SedwareCamLock.lua), verificado byte por byte. [Loader e instrucciones](SEDWARE_CAM_LOCK.md#entrega-de-la-corrección). El commit anterior no recibe cambios automáticamente.
