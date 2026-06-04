# -*- coding: utf-8 -*-
import os, requests, subprocess
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

# Rutas
DOWNLOAD_DIR = "/media/hdd/Mp3"
CONFIG_FILE = "/media/hdd/mp3_config/config.py"
HISTORY_FILE = "/media/hdd/mp3_config/history.txt"

def get_api():
    # Si el archivo de configuración no existe, lo crea automáticamente
    if not os.path.exists(CONFIG_FILE):
        try:
            dirname = os.path.dirname(CONFIG_FILE)
            if not os.path.exists(dirname):
                os.makedirs(dirname)
            with open(CONFIG_FILE, "w") as f:
                f.write('# -*- coding: utf-8 -*-\n')
                f.write('YOUTUBE_API_KEY = "TU_API_KEY_AQUI"\n')
        except:
            pass
        return None

    # Si existe, lee la API KEY
    try:
        import importlib.util
        spec = importlib.util.spec_from_file_location("cfg", CONFIG_FILE)
        cfg = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cfg)
        return getattr(cfg, "YOUTUBE_API_KEY", None)
    except: 
        return None

def manage_history(mode, q=None):
    if mode == "save" and q:
        try:
            if not os.path.exists(os.path.dirname(HISTORY_FILE)):
                os.makedirs(os.path.dirname(HISTORY_FILE))
            with open(HISTORY_FILE, "a") as f: 
                f.write(str(q) + "\n")
        except: 
            pass
    else:
        if not os.path.exists(HISTORY_FILE): 
            return []
        try:
            with open(HISTORY_FILE, "r") as f:
                lines = f.readlines()
                return list(dict.fromkeys([x.strip() for x in lines if x.strip()]))[::-1][:20]
        except: 
            return []

class ResultsScreenPro(Screen):
    skin = """
    <screen position="center,center" size="1200,600" title="Resultados YouTube">
        <widget name="list" position="10,10" size="550,580" font="Regular;28" itemHeight="70" />
        <widget name="preview" position="580,40" size="600,340" alphatest="on" />
        <widget name="title" position="580,400" size="600,150" font="Regular;30" halign="center" />
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
        except: self.timer.callback.append(self.show_data)
        
        self["list"].onSelectionChanged.append(self.start_timer)

    def start_timer(self):
        self.timer.start(400, True)

    def show_data(self):
        cur = self["list"].getCurrent()
        if not cur or not self.results: return
        res = self.results[cur[1]]
        self["title"].setText(res[0])
        path = "/tmp/v.jpg"
        try:
            r = requests.get(res[2], timeout=3)
            with open(path, "wb") as f: f.write(r.content)
            self["preview"].instance.setPixmap(LoadPixmap(path=path))
        except: pass

    def go_ok(self):
        cur = self["list"].getCurrent()
        if cur:
            self.selected_vid = self.results[cur[1]][1]
            opts = [("▶️ Audio", "a"), ("📺 Vídeo", "v"), ("📥 Descargar M4A", "d")]
            self.session.openWithCallback(self.execute_action, ChoiceBox, title="¿Qué quieres hacer?", list=opts)

    def execute_action(self, res):
        if res and self.selected_vid:
            vid = self.selected_vid
            url = "https://www.youtube.com/watch?v=" + vid
            if res[1] == "d":
                if not os.path.exists(DOWNLOAD_DIR): os.makedirs(DOWNLOAD_DIR)
                cmd = "yt-dlp -f 'ba[ext=m4a]/bestaudio' -o '%s/%%(title)s.m4a' '%s' &" % (DOWNLOAD_DIR, url)
                os.system(cmd)
                self.session.open(MessageBox, "Descarga iniciada", MessageBox.TYPE_INFO, timeout=5)
            else:
                fmt = "best" if res[1] == "v" else "bestaudio"
                try:
                    stream_url = subprocess.check_output(["yt-dlp", "-g", "-f", fmt, url]).decode().strip()
                    if stream_url:
                        ref = eServiceReference(4097, 0, stream_url)
                        self.session.nav.playService(ref)
                except: pass

    def go_exit(self):
        self.timer.stop()
        self.close()

class MP3Manager(Screen):
    skin = "<screen position='0,0' size='0,0' title=' ' />" 

    def __init__(self, session):
        Screen.__init__(self, session)
        self.session = session
        self.api = get_api()
        self.init_timer = eTimer()
        try: self.init_timer.timeout.connect(self.open_main_menu)
        except: self.init_timer.callback.append(self.open_main_menu)
        self.init_timer.start(200, True)

    def open_main_menu(self):
        menu = [("🔍 Buscar", "s"), ("🕒 Historial", "h"), ("📂 Descargas", "d"), ("❌ Salir", "e")]
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
            self.show_files()

    def search_yt(self, txt):
        if txt is None:
            self.open_main_menu()
            return
        query = txt[1] if isinstance(txt, tuple) else txt
        
        # Primero guardamos en historial si hay texto, antes de verificar la API
        if query:
            manage_history("save", query)
            
        if not query or not self.api or self.api == "TU_API_KEY_AQUI":
            self.session.openWithCallback(self.return_to_menu, MessageBox, "Por favor configura tu YouTube API Key en:\n/media/hdd/mp3_config/config.py", MessageBox.TYPE_ERROR)
            return

        try:
            url = "https://www.googleapis.com/youtube/v3/search"
            p = {"part": "snippet", "q": query, "type": "video", "maxResults": 15, "key": self.api}
            resp = requests.get(url, params=p, timeout=10)
            data = resp.json()
            results = [(i["snippet"]["title"], i["id"]["videoId"], i["snippet"]["thumbnails"]["high"]["url"]) for i in data.get("items", [])]
            
            if results:
                self.session.openWithCallback(self.return_to_menu, ResultsScreenPro, results)
            else:
                self.session.openWithCallback(self.return_to_menu, MessageBox, "Sin resultados", MessageBox.TYPE_INFO)
        except:
            self.session.openWithCallback(self.return_to_menu, MessageBox, "Error de red", MessageBox.TYPE_ERROR)

    def return_to_menu(self, *args):
        self.open_main_menu()

    def show_files(self):
        if not os.path.exists(DOWNLOAD_DIR): os.makedirs(DOWNLOAD_DIR)
        f_list = [(f, f) for f in os.listdir(DOWNLOAD_DIR) if f.lower().endswith(('.mp3', '.mp4', '.m4a'))]
        if f_list:
            self.session.openWithCallback(self.play_f, ChoiceBox, title="Descargas:", list=f_list)
        else:
            self.session.openWithCallback(self.return_to_menu, MessageBox, "Vacío", MessageBox.TYPE_INFO)

    def play_f(self, res):
        if res:
            ref = eServiceReference(4097, 0, os.path.join(DOWNLOAD_DIR, res[1]))
            self.session.nav.playService(ref)
        self.open_main_menu()

def main(session, **kwargs):
    session.open(MP3Manager)

def Plugins(**kwargs):
    return [PluginDescriptor(name="MP3 Downloader PRO", where=PluginDescriptor.WHERE_PLUGINMENU, fnc=main)]
