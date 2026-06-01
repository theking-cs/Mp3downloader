#!/usr/bin/python3
import sys
import subprocess
import os

DOWNLOAD_DIR = "/media/hdd/Mp3/"

def descargar(url):
    if not os.path.exists(DOWNLOAD_DIR):
        os.makedirs(DOWNLOAD_DIR)

    cmd = [
        "/usr/bin/yt-dlp",
        "-x",  # extraer audio
        "--audio-format", "mp3",  # convertir a mp3
        "-o", DOWNLOAD_DIR + "%(title)s.%(ext)s",
        url
    ]

    print("Ejecutando:", " ".join(cmd))
    subprocess.call(cmd)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        descargar(sys.argv[1])
    else:
        print("No se recibió URL")