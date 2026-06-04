# -*- coding: utf-8 -*-
import os
import subprocess
import html  # Limpia los títulos corruptos devueltos por YouTube (&amp;, &#39;, etc.)
from Plugins.Plugin import PluginDescriptor
from Screens.Screen import Screen
from Screens.ChoiceBox import ChoiceBox
from Screens.VirtualKeyBoard import VirtualKeyBoard
from Screens.MessageBox import MessageBox
from Components.ActionMap import ActionMap
from Components.Label import Label
from Components.Pixmap import Pixmap
from Components.MenuList import MenuList
from enigma import eServiceReference, eTimer
from Tools.LoadPixmap import LoadPixmap
from twisted.web.client import downloadPage  # Evita congelar el decodificador al moverte por la lista

# Rutas
DOWNLOAD_DIR = "/media/hdd/Mp3"
CONFIG_FILE = "/media/hdd/mp3_config/config.py"
HISTORY_FILE = "/media/hdd/mp3_config/history.txt"

def get_api():
    if not os.path.exists(CONFIG_FILE):
        try:
            dirname = os.path.dirname(CONFIG_FILE)
            if not os.path.exists(dirname):
                os.makedirs(dirname)
            with open(CONFIG_FILE, "w") as f:
                f.write('# -*- coding: utf-8 -*-\n')
                f.write('YOUTUBE_API_KEY = "TU_API_KEY_AQUI"\n')
        except Exception:
            pass
        return None

    try:
        import importlib.util
        spec = importlib.util.spec_from_file_location("cfg", CONFIG_FILE)
        cfg = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cfg)
        return getattr(cfg, "YOUTUBE_API_KEY", None)
    except Exception: 
        return None

def manage_history(mode, q=None):
    if mode == "save" and q:
        try:
            if not os.path.exists(os.path.dirname(HISTORY_FILE)):
                os.makedirs(os.path.dirname(HISTORY_FILE))
            with open(HISTORY_FILE, "a") as f: 
                f.write(str(q) + "\n")
        except Exception: 
            pass
    else:
        if not os.path.exists(HISTORY_FILE): 
            return []
        try:
            with open(HISTORY_FILE, "r") as f:
                lines = f.readlines()
                return list(dict.fromkeys([x.strip() for x in lines if x.strip()]))[::-1][:20]
        except Exception: 
            return []


class DownloadsScreen(Screen):
    skin = """
    <screen position="center,center" size="900,500" title="MP3 Downloader PRO - Mis Descargas">
        <widget name="list" position="20,20" size="860,400" font="Regular;24" itemHeight="45" scrollbarMode="showOnDemand" />
        <eLabel position="20,430" size="860,2" backgroundColor="#444444" />
        <widget name="key_red" position="30,445" size="350,30" font="Regular;22" foregroundColor="#ff3b30" halign="left" transparent="1" />
        <widget name="info" position="450,445" size="420,30" font="Regular;20" foregroundColor="#aaaaaa" halign="right" transparent="1" />
    </screen>"""

    def __init__(self, session):
        Screen.__init__(self, session)
        self.session = session
        self["list"] = MenuList([])
        self["key_red"] = Label("● [ROJO] Refrescar Lista")
        self["info"] = Label("[ OK ] Reproducir  |  [ EXIT ] Volver")
        
        self["actions"] = ActionMap(["SetupActions", "ColorActions"], {
            "red": self.refresh_list,
            "ok": self.go_play,
            "cancel": self.close
        }, -1)
        
        self.reset_timer = eTimer()
        try: self.reset_timer.timeout.connect(self.reset_button_text)
        except Exception: self.reset_timer.callback.append(self.reset_button_text)

        self.init_timer = eTimer()
        try: self.init_timer.timeout.connect(self.refresh_list)
        except Exception: self.init_timer.callback.append(self.refresh_list)
        self.init_timer.start(100, True)

    def refresh_list(self):
        if not os.path.exists(DOWNLOAD_DIR): 
            os.makedirs(DOWNLOAD_DIR)
        
        files = [f for f in os.listdir(DOWNLOAD_DIR) if f.lower().endswith(('.mp3', '.mp4', '.m4a'))]
        files.sort()
        
        if not files:
            self["list"].setList([("📁 Carpeta vacía (Pulsa ROJO para escanear de nuevo)", None)])
        else:
            self["list"].setList([(f, f) for f in files])
            
        self["key_red"].setText("● Lista Actualizada")
        self.reset_timer.start(1200, True)

    def reset_button_text(self):
        self["key_red"].setText("● [ROJO] Refrescar Lista")

    def go_play(self):
        cur = self["list"].getCurrent()
        if cur and cur[1]:
            ref = eServiceReference(4097, 0, os.path.join(DOWNLOAD_DIR, cur[1]))
            self.session.nav.playService(ref)


class ResultsScreenPro(Screen):
    skin = """
    <screen position="center,center" size="1240,680" title="MP3 Downloader PRO - Buscador" backgroundColor="#1a1a1a" flags="wfNoBorder">
        <eLabel position="15,15" size="580,650" backgroundColor="#242424" zPosition="-1" />
        <widget name="list" position="25,25" size="560,630" font="Regular;26" itemHeight="63" backgroundColor="#242424" foregroundColor="#cccccc" foregroundColorSelected="#ffffff" backgroundColorSelected="#336699" selectionZoom="105" scrollbarMode="showOnDemand" transparent="1" />
        
        <eLabel position="615,15" size="610,650" backgroundColor="#2c2c2c" zPosition="-1" />
        <widget name="preview" position="630,35" size="580,326" alphatest="on" zPosition="1" />
        
        <eLabel position="630,380" size="580,2" backgroundColor="#444444" />
        <widget name="title" position="630,395" size="580,180" font="Regular;28" foregroundColor="#ffffff" backgroundColor="#2c2c2c" halign="center" valign="center" transparent="1" />
        <eLabel position="630,590" size="580,2" backgroundColor="#444444" />
        
        <eLabel position="630,605" size="580,45" text="[ OK ] Opciones de reproducción   |   [ EXIT ] Volver" font="Regular;22" foregroundColor="#aaaaaa" backgroundColor="#2c2c2c" halign="center" valign="center" transparent="1" />
    </screen>"""
    
    def __init__(self, session, results):
        Screen.__init__(self, session)
        self.results = results
        self.selected_vid = None
        self["list"] = MenuList([(item[0], idx) for idx, item in enumerate(results)])
        self["preview"], self["title"] = Pixmap(), Label("")
        self["actions"] = ActionMap(["OkCancelActions"], {
            "ok": self.go_ok, 
            "cancel": self.go_exit
        }, -1)
        
        self.timer = eTimer()
        try: self.timer_conn = self.timer.timeout.connect(self.show_data)
        except Exception: self.timer.callback.append(self.show_data)
        
        self["list"].onSelectionChanged.append(self.start_timer)
        self.start_timer()

    def start_timer(self):
        self.timer.start(300, True)

    def show_data(self):
        cur = self["list"].getCurrent()
        if not cur or not self.results: return
        res = self.results[cur[1]]
        self["title"].setText(res[0])
        
        path = b"/tmp/v.jpg"
        try:
            url_bytes = res[2].encode('utf-8') if isinstance(res[2], str) else res[2]
            downloadPage(url_bytes, path).addCallback(self.image_downloaded).addErrback(self.image_error)
        except Exception:
            pass

    def image_downloaded(self, result):
        try:
            if os.path.exists("/tmp/v.jpg") and os.path.getsize("/tmp/v.jpg") > 0:
                self["preview"].instance.setPixmap(LoadPixmap(path="/tmp/v.jpg"))
        except Exception:
            pass

    def image_error(self, error):
        pass

    def go_ok(self):
        cur = self["list"].getCurrent()
        if cur:
            self.selected_vid = self.results[cur[1]][1]
            opts = [("▶️ Reproducir Audio (Rápido)", "a"), ("📺 Reproducir Vídeo (Máx)", "v"), ("📥 Descargar M4A a Local", "d")]
            self.session.openWithCallback(self.execute_action, ChoiceBox, title="Menú de Acciones:", list=opts)

    def execute_action(self, res):
        if res and self.selected_vid:
            vid = self.selected_vid
            url = "https://www.youtube.com/watch?v=" + vid
            
            if res[1] == "d":
                if not os.path.exists(DOWNLOAD_DIR): os.makedirs(DOWNLOAD_DIR)
                cmd = "yt-dlp -f 'ba[ext=m4a]/bestaudio' --no-playlist -o '%s/%%(title)s.%%(ext)s' '%s' &" % (DOWNLOAD_DIR, url)
                os.system(cmd)
                self.session.open(MessageBox, "Descarga iniciada en segundo plano", MessageBox.TYPE_INFO, timeout=5)
            else:
                fmt = "ba" if res[1] == "a" else "18/22/best"
                try:
                    cmd = "yt-dlp -g -f %s --no-playlist '%s'" % (fmt, url)
                    stream_url = subprocess.check_output(cmd, shell=True).decode().strip()
                    
                    if stream_url:
                        ref = eServiceReference(4097, 0, stream_url)
                        self.session.nav.playService(ref)
                except Exception: 
                    pass

    def go_exit(self):
        self.timer.stop()
        if os.path.exists("/tmp/v.jpg"):
            try: os.remove("/tmp/v.jpg")
            except Exception: pass
        self.close()


class MP3Manager(Screen):
    skin = "<screen position='0,0' size='0,0' title=' ' />" 

    def __init__(self, session):
        Screen.__init__(self, session)
        self.session = session
        self.api = get_api()
        self.init_timer = eTimer()
        try: self.init_timer.timeout.connect(self.open_main_menu)
        except Exception: self.init_timer.callback.append(self.open_main_menu)
        self.init_timer.start(200, True)

    def open_main_menu(self):
        menu = [("🔍 Buscar Contenido", "s"), ("🕒 Historial de Búsquedas", "h"), ("📂 Explorar Descargas", "d"), ("❌ Salir", "e")]
        self.session.openWithCallback(self.main_menu_cb, ChoiceBox, title="MP3 Downloader PRO", list=menu)

    def main_menu_cb(self, res):
        if not res or res[1] == "e":
            self.close()
            return
        if res[1] == "s":
            self.session.openWithCallback(self.search_yt, VirtualKeyBoard, title="Escribe tu búsqueda:")
        elif res[1] == "h":
            h = manage_history("load")
            if h: self.session.openWithCallback(self.search_yt, ChoiceBox, title="Historial", list=[(x, x) for x in h])
            else: self.open_main_menu()
        elif res[1] == "d":
            self.session.openWithCallback(self.return_to_menu, DownloadsScreen)

    def search_yt(self, txt):
        if txt is None:
            self.open_main_menu()
            return
        query = txt[1] if isinstance(txt, tuple) else txt
        
        if query:
            manage_history("save", query)
            
        if not query or not self.api or self.api == "TU_API_KEY_AQUI":
            self.session.openWithCallback(self.return_to_menu, MessageBox, "Por favor configura tu YouTube API Key en:\n/media/hdd/mp3_config/config.py", MessageBox.TYPE_ERROR)
            return

        try:
            import requests
            url = "https://www.googleapis.com/youtube/v3/search"
            p = {"part": "snippet", "q": query, "type": "video", "maxResults": 15, "key": self.api}
            resp = requests.get(url, params=p, timeout=10)
            data = resp.json()
            
            results = []
            for i in data.get("items", []):
                clean_title = html.unescape(i["snippet"]["title"])
                v_id = i["id"]["videoId"]
                thumb = i["snippet"]["thumbnails"]["high"]["url"]
                results.append((clean_title, v_id, thumb))
            
            if results:
                self.session.openWithCallback(self.return_to_menu, ResultsScreenPro, results)
            else:
                self.session.openWithCallback(self.return_to_menu, MessageBox, "Sin resultados", MessageBox.TYPE_INFO)
        except Exception:
            self.session.openWithCallback(self.return_to_menu, MessageBox, "Error de red", MessageBox.TYPE_ERROR)

    def return_to_menu(self, *args):
        self.open_main_menu()


def main(session, **kwargs):
    session.open(MP3Manager)

def Plugins(**kwargs):
    icon_path = os.path.join(os.path.dirname(__file__), "plugin.png")
    if not os.path.exists(icon_path):
        icon_path = None
        
    return [PluginDescriptor(
        name="MP3 Downloader PRO", 
        description="Descarga música MP3 desde YouTube",
        where=PluginDescriptor.WHERE_PLUGINMENU, 
        icon=icon_path, 
        fnc=main
    )]
