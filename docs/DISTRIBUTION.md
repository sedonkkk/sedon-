# Distribución de DH PREDICTION LAB

`DaHoodPrediction.lua` contiene toda la lógica y los módulos necesarios. El loader solo descarga ese archivo y pide al runtime que lo compile. No instala otros scripts, no escribe credenciales, no contacta servidores adicionales y no llama remotes de Da Hood. El archivo completo también se puede ejecutar directamente sin loader.

## Qué necesita el runtime

En un cliente Roblox normal, `game` es un `DataModel`, **no una función**: `loadstring(game("URL"))()` no es sintaxis de carga funcional. La forma usual de algunos entornos externos es `game:HttpGet(...)`; esa capacidad no forma parte del contrato de un LocalScript normal. `loadstring` tampoco está disponible en el cliente publicado normal. Activar `LoadStringEnabled` en Studio no convierte un LocalScript de cliente en ese runtime.

Un entorno externo necesita proporcionar `loadstring`, acceso HTTP HTTPS mediante `game:HttpGet`, los servicios y APIs del cliente que usa el archivo y permisos para crear una GUI en `LocalPlayer.PlayerGui`. El script no obtiene esos permisos ni incluye un ejecutor. `Loader.template.lua` comprueba compilación y descarga, informa fallos y contiene una URL vacía intencionalmente. Las APIs normales siguen siendo el camino para instalarlo como LocalScript en tu propia experiencia.

La validación automática del proyecto no prueba un ejecutor específico ni una sesión real de Da Hood. Aunque la GUI se abra, la observación de personajes y la orientación de cámara no confirman compatibilidad con la mecánica de disparo o registro de impactos de ese juego. Consulta [compatibilidad y limitaciones](DA_HOOD_COMPATIBILITY.md) y [resultados de validación](VALIDATION.md).

## Subir el archivo a GitHub

1. Abre tu repositorio `sedonkkk/sedon-` en GitHub, o el repositorio propio donde quieras publicar el archivo. Usa **Add file → Upload files** y sube `DaHoodPrediction.lua` a la raíz. Si aún no hay rama, este primer commit la crea; comprueba el nombre que GitHub muestra. Publica mediante **Commit changes**. No necesitas subir el ZIP ni el lugar de Studio para usar el loader.
2. Abre el archivo publicado y pulsa **Raw**. Copia la URL de la barra del navegador. Debe ser una dirección HTTPS real de `raw.githubusercontent.com` que termine en `DaHoodPrediction.lua`. Para mantener la versión estable, abre antes el archivo en un commit concreto y copia su Raw; un enlace de rama cambia cuando se actualiza esa rama.
3. Verifica que el enlace se pueda abrir sin iniciar sesión y muestre el código completo. No pegues tokens ni enlaces con credenciales en el loader. Un repositorio privado normalmente requiere autenticación, por lo que ese enlace no sirve para una distribución pública sin credenciales.

El proyecto fue subido a `sedonkkk/sedon-`, rama `main`, con autorización del usuario. El enlace Raw del commit inicial fue comprobado por HTTPS y sus bytes coinciden con el archivo local; la URL no se ha inventado.

## Comando de una sola línea

Esta es la **plantilla**, que solo puede ejecutarse tras definir `URL_RAW_DEL_SCRIPT` con el enlace Raw real obtenido arriba:

```lua
loadstring(game:HttpGet(URL_RAW_DEL_SCRIPT))()
```

Para obtener el comando final con la URL insertada, desde la raíz del proyecto define en tu shell `URL_RAW_DEL_SCRIPT` con esa dirección real y ejecuta:

```sh
python3 scripts/prepare_distribution.py --raw-url "$URL_RAW_DEL_SCRIPT"
```

El preparador descarga una sola vez ese Raw usando HTTPS con verificación TLS normal, sin credenciales, y exige que sus bytes sean idénticos al `DaHoodPrediction.lua` local. Si responde 404, es HTML o pertenece a otra versión, la operación falla y no genera un loader nuevo. Cuando pasa la verificación, crea `Loader.lua`, `build/LOADSTRING.txt` y copias descargables de ambos; también imprime la línea final. `Loader.lua` conserva toda la lógica en el archivo principal y agrega mensajes para APIs ausentes, descarga fallida y error de compilación.

La comprobación garantiza los bytes recibidos durante la preparación. Un Raw de rama puede cambiar después y el loader pequeño no fija un hash en runtime: prefiere el Raw de un commit si quieres ejecutar siempre la misma versión. Repite la preparación al publicar una actualización. Lee el código que vas a ejecutar y usa únicamente tu URL conocida.

## Archivos descargables y preparación local

```sh
python3 scripts/build_standalone.py
python3 scripts/check.py
python3 scripts/prepare_distribution.py
```

Sin `--raw-url`, el último comando **no realiza solicitudes de red**. Empaqueta el archivo autónomo y el código fuente actual en `build/`, verifica cada entrada ZIP y copia los resultados con permisos de lectura a `/workspace/downloads/`:

- `DaHoodPrediction.lua` y `DaHoodPrediction.txt`: mismos bytes; el TXT puede renombrarse a `.lua`.
- `DaHoodPrediction.zip`: contiene solo el script autónomo.
- `DHPredictionLab-source.zip`: fuentes, documentación, scripts de construcción y pruebas originales y autónomas.
- `DHPredictionLab.rbxlx`: lugar de Studio de un LocalScript, si ya fue generado.

`build/distribution-manifest.json` registra SHA-256 de cada archivo empaquetado; el script comprueba también que las copias descargables coincidan. No incluye `.git`, credenciales, cachés, archivos subidos por el usuario ni dependencias ajenas. Ejecuta la preparación después de que terminen los cambios y la validación, para que los ZIP representen la versión final.

La plantilla puede inspeccionarse localmente sin ninguna URL. Un loader que llama código descargado requiere un runtime que permita esas APIs; sus errores no se solucionan desactivando la seguridad, alterando anticheat o manipulando remotes protegidos.

## Publicación verificada

[Archivo en GitHub](https://github.com/sedonkkk/sedon-/blob/main/DaHoodPrediction.lua) · [Raw de la versión verificada](https://raw.githubusercontent.com/sedonkkk/sedon-/47a278a38ae3b7ce48fa2184bcf7ff0bd12bcedf/DaHoodPrediction.lua)

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/sedonkkk/sedon-/47a278a38ae3b7ce48fa2184bcf7ff0bd12bcedf/DaHoodPrediction.lua"))()
```

`Loader.lua` usa ese enlace fijo. La verificación del Raw confirma distribución e integridad de esa versión; no certifica la ejecución en un ejecutor ni Da Hood.
