#!/bin/sh
# Instalador optimizado para Mp3downloader - theking-cs

echo "********************************************************"
echo "* Instalando Mp3downloader v1.0                        *"
echo "********************************************************"

PLUGIN_NAME="Mp3downloader"
PLUGIN_PATH="/usr/lib/enigma2/python/Plugins/Extensions/$PLUGIN_NAME"

# Asegurar que dependencias básicas como unzip estén instaladas
if ! command -v unzip >/dev/null 2>&1; then
    echo "> 'unzip' no encontrado. Instalando dependencia..."
    opkg update && opkg install unzip
fi

# Limpiar carpetas temporales y previas para evitar conflictos
rm -rf "$PLUGIN_PATH"
rm -rf /tmp/Mp3downloader.zip
rm -rf /tmp/Mp3downloader-main

echo "> Descargando desde GitHub..."
wget --no-check-certificate -q https://github.com/theking-cs/Mp3downloader/archive/refs/heads/main.zip -O /tmp/Mp3downloader.zip

# Verificar si la descarga fue exitosa
if [ ! -f /tmp/Mp3downloader.zip ]; then
    echo "❌ Error: No se pudo descargar el archivo desde GitHub."
    exit 1
fi

echo "> Extrayendo archivos..."
unzip -q /tmp/Mp3downloader.zip -d /tmp/

echo "> Instalando en el sistema..."
# Aseguramos que la carpeta destino exista
mkdir -p "/usr/lib/enigma2/python/Plugins/Extensions"
mv /tmp/Mp3downloader-main "$PLUGIN_PATH"

# Dar permisos correctos a los archivos del plugin
echo "> Configurando permisos..."
chmod -R 755 "$PLUGIN_PATH"

# Limpieza de archivos temporales
rm -rf /tmp/Mp3downloader.zip

echo "********************************************************"
echo "* INSTALACIÓN COMPLETADA - REINICIANDO ENIGMA2          *"
echo "********************************************************"

# Reinicio seguro de Enigma2 para guardar configuraciones previas
init 4 && sleep 2 && init 3

exit 0
