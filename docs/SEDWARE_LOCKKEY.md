# SEDWARE: corrección de LockKey

La versión anterior rechazaba el propio `Enum.KeyCode.C` durante `Config.new(Config)`. La validación exigía `typeof(value)=="EnumItem"` y `tostring(value.EnumType)=="Enum.KeyCode"` antes de normalizarlo. Esa comparación textual era incorrecta: `EnumItem.EnumType` es una **referencia al Enum padre**, cuya representación textual no es una prueba de pertenencia.

Reproduje el problema ejecutando el bundle anterior del commit `8e48f6c16cdb3d045b3da1717b0de558b42ef7b3` con dobles de APIs. Cambiar únicamente la representación del padre a `"KeyCode"` produjo `LockKey inválido` y `Configuration FAIL`. Cambiar únicamente typeof del elemento a `"userdata"` también lo rechazó. El doble anterior devolvía justamente `"Enum.KeyCode"` e inventaba cualquier miembro solicitado; por eso las pruebas no detectaban el defecto. Ahora el doble tiene miembros finitos y referencias estables y permite probar variantes de formato/tipo explícitamente.

Referencias públicas: [EnumItem.EnumType](https://create.roblox.com/docs/reference/engine/datatypes/EnumItem#EnumType) describe la referencia al padre; [Enum:GetEnumItems](https://create.roblox.com/docs/reference/engine/datatypes/Enum#GetEnumItems) devuelve los elementos disponibles de ese Enum. No usamos el texto de EnumType ni typeof como criterio único de aceptación.

## Cambios

La configuración editable empieza con:

```lua
LockKey = "C",
PredictionX = 0.1205,
PredictionY = 0.0800,
```

También se admite `LockKey=Enum.KeyCode.C`. `Config.normalizeLockKey()` resuelve el nombre con acceso protegido a `Enum.KeyCode`, comprueba el elemento en `GetEnumItems()`, verifica el Enum padre y el miembro por nombre, y devuelve la referencia canónica. En datos Lua de pruebas se exige identidad de referencia, evitando que un `__eq` falsificado o una tabla con Name/EnumType se haga pasar por una tecla. Se preserva la igualdad de valores de userdata nativa entre wrappers del motor.

Nombres inexistentes, elementos de otros Enums, None/Unknown, números, funciones y objetos falsificados se rechazan con un error de LockKey. Si el Enum existe pero su consulta falla, no se acepta una tecla sin verificar. Sin Roblox, solo se conserva un conjunto acotado de nombres conocidos para las pruebas numéricas; Runtime sigue exigiendo APIs nativas para iniciar una sesión.

`Config.new()` ahora valida y normaliza también los defaults. Las copias de configuración conservan la identidad de LockKey sin depender de typeof ni recorrer internamente un Enum. La bienvenida obtiene `Name` de la tecla normalizada sin comparar cadenas de EnumType, por lo que mantiene **Press C to Lock**. InputBegan conserva la comparación con el Enum normalizado; las pruebas disparan ese callback del archivo autónomo para bloquear y desbloquear.

Se modificaron Config, el nombre de la tecla en Session, las marcas de versión de Bootstrap/generador y las pruebas. Se regeneraron PinkDotLock.lua y sus dos lugares de Studio. DOT Hot Pink, X/Y, Memory, Auto Prediction, perfiles, selección en primera/tercera persona, cámara libre, esperas limitadas, errores en consola y notificaciones permanecen disponibles. No se modificaron los algoritmos de Prediction ni DH PREDICTION LAB.

## Validación

```sh
python3 scripts/build_pink.py
python3 scripts/check_pink.py
python3 scripts/check.py
```

Compilador oficial Luau 0.695. **30 pruebas de LockKey y 292 comprobaciones**, cubriendo texto C, Enum C, miembros incorrectos, nombres inexistentes, formas falsificadas, variantes y excepciones de typeof/tostring, conservación de identidad, arranque completo, C lock/unlock, limpieza y fallos posteriores de inicialización. Las fallas se informan en consola y en un aviso breve cuando PlayerGui y las APIs de visualización están disponibles.

Total actual, incluyendo la integración del arma propia: **210 pruebas de Pink/SEDWARE + 96 anteriores = 306 pruebas, 79.051 comprobaciones, 0 fallos**. Los casos de cliente usan el bundle real con dobles deterministas. **No se ejecutaron Roblox Studio ni Da Hood real.** La corrección elimina el rechazo reproducido; la ejecución en el entorno del usuario requiere sus APIs nativas y no se certifica mediante estos dobles.

Para comprobar qué versión ejecutas, busca `[SEDWARE][Execution][START] SEDWARE startup v3` y después `Configuration READY`, `Input READY`, `Session ACTIVE`. Si aparece otro FAIL, conserva su explicación y el stack completo. DebugMode informa la tecla detectada y los resultados de selección. El loader fijado al commit anterior continuará ejecutando el código antiguo; debe usarse el enlace de la publicación nueva.

## Publicación verificada

La corrección está publicada en el commit `ed141a9b2f0dcf8e4c9a677aa6c5a4fb0edcc28e`. [Raw nuevo](https://raw.githubusercontent.com/sedonkkk/sedon-/ed141a9b2f0dcf8e4c9a677aa6c5a4fb0edcc28e/PinkDotLock.lua): HTTP 200, 108.378 bytes coincidentes con el archivo compilado y probado; SHA-256 `235e4c13d224641240b0f5354e4983326e1761a70746ff6f80a232015bc18eb6`.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/sedonkkk/sedon-/ed141a9b2f0dcf8e4c9a677aa6c5a4fb0edcc28e/PinkDotLock.lua"))()
```

PinkLoader.lua se actualizó a este nuevo commit. La entrada SEDWARE.lua de main mantiene su dirección y carga el payload vigente; usa la línea fijada anterior si necesitas ejecutar exactamente esta versión v3. Ambas vías requieren un host autorizado compatible con Luau y las APIs del cliente.
