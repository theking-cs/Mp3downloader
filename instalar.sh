#!/bin/sh
# Instalador oficial para Mp3downloader - por theking-cs

echo "********************************************************"
echo "* Instalando Mp3downloader v1.0                        *"
echo "********************************************************"

PLUGIN_NAME="Mp3downloader"
PLUGIN_PATH="/usr/lib/enigma2/python/Plugins/Extensions/$PLUGIN_NAME"
TMP_ZIP="/tmp/Mp3downloader.zip"
TMP_DIR="/tmp/Mp3downloader_extracted"

# 1. Asegurar dependencia 'unzip' para descomprimir el repo
if ! command -v unzip >/dev/null 2>&1; then
    echo "> 'unzip' no encontrado. Instalando dependencia..."
    opkg update && opkg install unzip
fi

# 2. Limpieza previa total para evitar conflictos
rm -rf "$PLUGIN_PATH"
rm -rf "$TMP_ZIP"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# 3. Descarga desde la rama main de tu GitHub
echo "> Descargando desde GitHub..."
wget --no-check-certificate -q "https://github.com/theking-cs/Mp3downloader/archive/refs/heads/main.zip" -O "$TMP_ZIP"

if [ ! -f "$TMP_ZIP" ] || [ ! -s "$TMP_ZIP" ]; then
    echo "❌ Error: No se pudo descargar el archivo desde GitHub."
    rm -rf "$TMP_DIR"
    exit 1
fi

# 4. Extracción de los archivos
echo "> Extrayendo archivos..."
unzip -q "$TMP_ZIP" -d "$TMP_DIR"
if [ $? -ne 0 ]; then
    echo "❌ Error: El archivo ZIP está corrupto."
    rm -rf "$TMP_ZIP" "$TMP_DIR"
    exit 1
fi

# 5. Instalación en la ruta correcta de Enigma2
echo "> Instalando en el sistema..."
mkdir -p "/usr/lib/enigma2/python/Plugins/Extensions"

# Busca dinámicamente dónde está el __init__.py en los archivos extraídos
INIT_FILE=$(find "$TMP_DIR" -name "__init__.py" | head -n 1)

if [ -z "$INIT_FILE" ]; then
    echo "❌ Error: Estructura de plugin no válida (falta __init__.py)."
    rm -rf "$TMP_ZIP" "$TMP_DIR"
    exit 1
fi

ACTUAL_PLUGIN_DIR=$(dirname "$INIT_FILE")

# Mueve los archivos renombrando la carpeta final correctamente a 'Mp3downloader'
mv "$ACTUAL_PLUGIN_DIR" "$PLUGIN_PATH"

# 6. Asignar permisos Linux correctos
echo "> Configurando permisos..."
chmod -R 755 "$PLUGIN_PATH"

# 7. Limpieza final de temporales
rm -rf "$TMP_ZIP"
rm -rf "$TMP_DIR"

echo "********************************************************"
echo "* INSTALACIÓN COMPLETADA CON ÉXITO                     *"
echo "********************************************************"

# Reinicio de interfaz seguro: El sleep da tiempo a que la AppStore cierre bien la pantalla de la consola
echo "> Solicitando reinicio de la interfaz gráfica..."
(sleep 2 && systemctl restart enigma2 || init 4 && sleep 2 && init 3) &

exit 0
