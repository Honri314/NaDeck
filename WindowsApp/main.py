# NaDeck — TrueNAS 관리 프로그램 (Windows / PySide6)
# 실행: python main.py  (requirements: PySide6, requests)
#
# 주의: Qt 플러그인 경로를 import 전에 고정한다.
# PySide6 설치 환경에 따라 기본 스캔 경로 탐색이 실패하여
# "Could not find the Qt platform plugin cocoa" 오류(Abort trap 6)가
# 반복되는 문제를 방지한다.
import os
import sys
import datetime
import traceback
from typing import Any, Callable, Optional

import PySide6

_qt_plugins_platforms = os.path.join(
    os.path.dirname(PySide6.__file__), "Qt", "plugins", "platforms")
if os.path.isdir(_qt_plugins_platforms):
    os.environ.setdefault("QT_QPA_PLATFORM_PLUGIN_PATH", _qt_plugins_platforms)

from PySide6.QtCore import QObject, QRunnable, QRectF, QSettings, Qt, QThreadPool, QTimer, Signal
from PySide6.QtGui import QColor, QIcon, QPainter, QPen
from PySide6.QtWidgets import (
    QApplication, QCheckBox, QComboBox, QDialog, QDialogButtonBox, QFormLayout,
    QFrame, QHBoxLayout, QHeaderView, QInputDialog, QLabel, QLineEdit, QListWidget, QListWidgetItem,
    QMessageBox, QProgressBar, QPushButton, QScrollArea, QTabWidget, QTableWidget,
    QTableWidgetItem, QVBoxLayout, QWidget,
)

import truenas_api
from truenas_api import TruenasClient, TruenasError, normalize_base_url


# ------------------------- 앱 버전 (릴리스 빌드 시 nadeck_version 모듈로 채움)

try:
    import nadeck_version
    APP_VERSION = nadeck_version.__version__
except Exception:
    APP_VERSION = "1.0.0"

UPDATE_BASE = "https://ubuntu.tail543772.ts.net/nadeck/releases"
DOWNLOAD_PAGE = "https://ubuntu.tail543772.ts.net/nadeck/"


# ------------------------- 포맷 유틸

def fmt_bytes(v: Any) -> str:
    try:
        num = int(v)
    except (TypeError, ValueError):
        return "-"
    if num <= 0:
        return "0 B"
    units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]
    val = float(num)
    i = 0
    while val >= 1024 and i < len(units) - 1:
        val /= 1024
        i += 1
    return f"{val:0.1f} {units[i]}"


def fmt_epoch(v: Any) -> str:
    try:
        ts = int(v)
        if ts > 0:
            return datetime.datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M")
    except (TypeError, ValueError):
        pass
    return "-"


def status_color(status: str) -> QColor:
    s = (status or "").upper()
    if s in ("ONLINE", "RUNNING", "SERVING"):
        return QColor("green")
    if s == "DEGRADED":
        return QColor("orange")
    if s in ("FAULTED", "OFFLINE", "REMOVED", "UNAVAIL"):
        return QColor("red")
    return QColor("gray")


def password_line() -> QLineEdit:
    edit = QLineEdit()
    edit.setEchoMode(QLineEdit.Password)
    return edit


# ------------------------- 백그라운드 작업

class WorkerSignals(QObject):
    done = Signal(object)
    failed = Signal(str)


class Worker(QRunnable):
    def __init__(self, fn: Callable):
        super().__init__()
        self.fn = fn
        self.signals = WorkerSignals()

    def run(self):
        try:
            result = self.fn()
            self.signals.done.emit(result)
        except TruenasError as err:
            self.signals.failed.emit(str(err))
        except Exception as err:
            self.signals.failed.emit(t("오류", "Error") + ":\n" + traceback.format_exc(limit=2))


# ------------------------- 설정

LANG_KEY = "lang"

# 하단 상태 메시지(오류 안내 포함) 자동 지우기 시간
MSG_TIMEOUT_MS = 2000


def t(korean: str, english: str) -> str:
    """언어 설정(QSettings: lang)에 따라 문구 선택. 기본 한국어."""
    settings = QSettings("Freebuff", "TrueNASManager")
    return english if settings.value(LANG_KEY, "ko") == "en" else korean


def current_language() -> str:
    settings = QSettings("Freebuff", "TrueNASManager")
    return "en" if settings.value(LANG_KEY, "ko") == "en" else "ko"


class Config:
    def __init__(self):
        self.settings = QSettings("Freebuff", "TrueNASManager")

    # ---- 기존 단일 연결 호환 읽기(활성 프로파일의 별칭) ----
    def load(self) -> dict:
        return {
            "name": self.settings.value("name", ""),
            "base_url": self.settings.value("base_url", ""),
            "api_key": self.settings.value("api_key", ""),
            "verify_tls": self.settings.value("verify_tls", "true") == "true",
            "lang": self.settings.value(LANG_KEY, "ko"),
            "port": str(self.settings.value("port", "") or ""),
            "auth_mode": str(self.settings.value("auth_mode", "") or ""),
            "basic_user": str(self.settings.value("basic_user", "") or ""),
        }

    def save(self, **kwargs):
        for key, value in kwargs.items():
            self.settings.setValue(key, value)
        self.settings.sync()

    # ---- 다중 프로파일: 
    # 값은 JSON 문자열로 settings("profiles") 한 키에 저장한다.
    # 구조: {"active": "이름", "list": [{name, base_url, api_key, port,
    #        verify_tls, auth_mode, basic_user}]}

    def profiles(self) -> dict:
        import json
        raw = str(self.settings.value("profiles", "") or "")
        if not raw:
            # 이전 단일 연결을 1회 이식해 "기본 연결" 프로파일로 만든다.
            cfg = self.load()
            if cfg.get("base_url") and cfg.get("api_key"):
                data = {"active": cfg.get("name") or "기본 연결",
                        "list": [{
                            "name": cfg.get("name") or "기본 연결",
                            "base_url": cfg.get("base_url"),
                            "api_key": cfg.get("api_key"),
                            "port": cfg.get("port"),
                            "verify_tls": cfg.get("verify_tls"),
                            "auth_mode": cfg.get("auth_mode"),
                            "basic_user": cfg.get("basic_user"),
                        }]}
                self.save_profiles(data)
                return data
            return {"active": "", "list": []}
        try:
            data = json.loads(raw)
            if not isinstance(data, dict):
                return {"active": "", "list": []}
            data.setdefault("active", "")
            data.setdefault("list", [])
            return data
        except Exception:
            return {"active": "", "list": []}

    def save_profiles(self, data: dict):
        import json
        self.settings.setValue("profiles", json.dumps(data, ensure_ascii=False))
        self.settings.sync()

    def active_profile(self) -> tuple:
        """(이름, 항목dict) 또는 ("", {})"""
        data = self.profiles()
        name = data.get("active") or ""
        for item in data.get("list", []):
            if item.get("name") == name:
                return name, item
        if data.get("list"):
            first = data["list"][0]
            return first.get("name") or "", first
        return "", {}

    def upsert_profile(self, name: str, item: dict):
        data = self.profiles()
        item = dict(item)
        item["name"] = name
        list_ = data.get("list", [])
        for i, existing in enumerate(list_):
            if existing.get("name") == name:
                list_[i] = item
                break
        else:
            list_.append(item)
        data["active"] = name
        self.save_profiles(data)
        # 단일 연결 호환 키도 함께 기록(구 코드가 직접 읽는 경우 대비)
        self.save(
            name=name,
            base_url=item.get("base_url") or "",
            api_key=item.get("api_key") or "",
            port=str(item.get("port") or ""),
            verify_tls="true" if item.get("verify_tls") else "false",
            auth_mode=str(item.get("auth_mode") or ""),
            basic_user=str(item.get("basic_user") or ""),
        )

    def delete_profile(self, name: str):
        data = self.profiles()
        data["list"] = [i for i in data.get("list", []) if i.get("name") != name]
        if data.get("active") == name:
            data["active"] = data["list"][0].get("name") if data["list"] else ""
        self.save_profiles(data)


# ------------------------- 연결 탭

class ConnectionPage(QWidget):
    def __init__(self, main: "MainWindow"):
        super().__init__()
        self.main = main
        cfg = main.config.load()

        self.name_edit = QLineEdit(str(cfg.get("name") or ""))
        self.url_edit = QLineEdit(str(cfg.get("base_url") or ""))
        self.url_edit.setPlaceholderText(t("예: 192.168.1.100 또는 https://nas.local",
                                           "e.g. 192.168.1.100 or https://nas.local"))
        self.key_edit = password_line()
        self.key_edit.setText(str(cfg.get("api_key") or ""))
        self.key_edit.setPlaceholderText(t("TrueNAS 웹 UI의 API 키", "API key from the TrueNAS web UI"))
        self.verify_check = QCheckBox(t("TLS 인증서 검증 (공식 인증서 사용 시)",
                                        "Verify TLS certificates"))
        self.verify_check.setChecked(bool(cfg.get("verify_tls", True)))

        self.port_edit = QLineEdit(str(cfg.get("port") or ""))
        self.port_edit.setPlaceholderText(t("공란 권장 (기본 https 443)", "blank = default (https 443)"))

        self.basic_user_edit = QLineEdit(str(cfg.get("basic_user") or ""))
        self.basic_user_edit.setPlaceholderText(t("예: truenas_admin", "e.g. truenas_admin"))

        self.lang_combo = QComboBox()
        self.lang_combo.addItem(t("한국어", "한국어"), "ko")
        self.lang_combo.addItem(t("English", "English"), "en")
        self.lang_combo.setCurrentIndex(1 if current_language() == "en" else 0)

        form = QFormLayout()
        form.addRow(t("표시 이름(선택)", "Display name (optional)"), self.name_edit)
        form.addRow(t("주소", "Address"), self.url_edit)
        form.addRow(t("포트(선택)", "Port (optional)"), self.port_edit)
        form.addRow(t("API 키", "API key"), self.key_edit)
        form.addRow(t("사용자 이름(Basic인증용)", "Username (for Basic auth)"), self.basic_user_edit)
        form.addRow(t("표시 언어", "Language"), self.lang_combo)
        form.addRow("", self.verify_check)

        note = QLabel(t(
            "[API 키 발급 (단계별)]\n"
            "1. 웹 브라우저로 트루나스 관리 화면 접속 (예: https://192.168.1.100)\n"
            "2. 왼쪽 메뉴 'Credential(자격 증명)' 클릭\n"
            "3. 'API Keys' -> 'Add(추가)' -> 이름 입력 후 생성\n"
            "4. 화면에 표시된 텍스트가 API 키 -> Copy 버튼으로 복사\n"
            "5. 이 앱의 'API 키' 입력칸에 바로 붙여넣기 (공백/줄바꿈 없이)\n"
            "▼ Copy 버튼을 쓰지 않고 드래그하면 잘리거나 공백이 섞일 수 있습니다.\n"
            "▼ 키는 다시 표시되지 않으니 복사 실패 시 삭제 후 재발급하세요.\n"
            "\n"
            "[연결 참고]\n"
            "기본 포트: https 443 / http 80 (보통 공란). 관리 UI 포트를 바꾼 경우에만 입력 (예: 8443).\n"
            "http(s):// 생략 시 https가 사용되며 /api/v2.0 경로는 자동 추가됩니다.\n"
            "테일스케일(Tailscale) 사용 시 매직DNS 이름(예: nas.tailnet.ts.net) 또는 100.x.x.x IP를 입력하세요.\n"
            "자체 서명 인증서라면 'TLS 인증서 검증'을 끄세요.",
            "[API key (step by step)]\n"
            "1. Open the TrueNAS web UI (e.g. https://192.168.1.100)\n"
            "2. Click 'Credential' in the left menu\n"
            "3. 'API Keys' -> 'Add' -> enter a name and create\n"
            "4. The shown text is the API key -> copy via the Copy button\n"
            "5. Paste it into the 'API key' field (no spaces/newlines)\n"
            "NOTE: Manual selection may clip the key.\n"
            "NOTE: The key is shown only once; re-issue if needed.\n"
            "\n"
            "[Connection notes]\n"
            "Default ports: https 443 / http 80 (usually blank); only set if changed (e.g. 8443).\n"
            "https is used when no scheme is given; /api/v2.0 is appended automatically.\n"
            "With Tailscale, use a MagicDNS name or a 100.x.x.x IP.\n"
            "Turn off certificate verification if you use a self-signed certificate."
        ))
        note.setWordWrap(True)

        self.result_list = QListWidget()
        self.test_btn = QPushButton(t("연결 테스트", "Test connection"))
        self.test_btn.clicked.connect(self.on_test)
        self.diag_btn = QPushButton(t("진단 실행", "Run diagnosis"))
        self.diag_btn.clicked.connect(self.on_diagnose)
        self.copy_btn = QPushButton(t("진단 결과 복사", "Copy diagnosis"))
        self.copy_btn.clicked.connect(self.copy_diag)
        self.copy_btn.setEnabled(False)
        self.save_btn = QPushButton(t("연결 저장", "Save"))
        self.save_btn.clicked.connect(self.on_save)

        btns = QHBoxLayout()
        btns.addWidget(self.test_btn)
        btns.addWidget(self.diag_btn)
        btns.addWidget(self.copy_btn)
        btns.addWidget(self.save_btn)
        btns.addStretch(1)

        outer = QVBoxLayout()
        outer.addLayout(form)
        outer.addWidget(note)
        outer.addLayout(btns)
        outer.addWidget(QLabel(t("연결 결과", "Result")))
        outer.addWidget(self.result_list, stretch=1)
        self.setLayout(outer)

    def on_save(self):
        url = normalize_base_url(self.url_edit.text())
        self.url_edit.setText(url)
        lang = self.lang_combo.currentData() or "ko"
        self.main.config.save(**{LANG_KEY: lang})
        # 표시 이름이 있으면 그 이름의 프로파일로 저장(다중 NAS 관리).
        # 기존 활성 프로파일이 있으면 그 이름 아래에 덮어쓴다.
        active_name, _item = self.main.config.active_profile()
        name = self.name_edit.text().strip() or active_name or "기본 연결"
        self.main.config.upsert_profile(name, {
            "name": name,
            "base_url": url,
            "api_key": self.key_edit.text(),
            "port": self.port_edit.text().strip(),
            "verify_tls": self.verify_check.isChecked(),
            "auth_mode": str(self.main.config.load().get("auth_mode") or ""),
            "basic_user": self.basic_user_edit.text().strip(),
        })
        self.main.refresh_nas_list()
        import truenas_api
        truenas_api.set_language(lang)
        self.main.show_message(t(f"'{name}' 연결을 저장했습니다.", f"Saved connection '{name}'."))

    def on_test(self):
        lang = self.lang_combo.currentData() or "ko"
        import truenas_api
        truenas_api.set_language(lang)
        if not self.url_edit.text().strip() or not self.key_edit.text().strip():
            self.main.show_message(t("주소와 API 키를 입력하세요.",
                                           "Enter the address and API key."))
            return
        self.main.show_message(t("연결 테스트 중...", "Testing connection..."), sticky=True)
        self.result_list.clear()
        client = self.make_client()
        self.main.run_async(client.system_info, self.main.test_done)
        self.main.run_async(
            lambda: [(p.get("name"), p.get("status")) for p in client.pools()],
            self.main.pools_test_done,
        )

    def make_client(self) -> TruenasClient:
        cfg = self.main.config.load()
        return TruenasClient(
            base_url=self.url_edit.text(),
            api_key=self.key_edit.text(),
            verify_tls=self.verify_check.isChecked(),
            port=self.port_edit.text().strip(),
            auth_mode=str(cfg.get("auth_mode") or "api_key"),
            basic_user=str(cfg.get("basic_user") or ""),
        )

    def on_diagnose(self):
        # 언어를 먼저 적용한 뒤 백그라운드 진단을 시작한다 (메시지 언어 일관성)
        truenas_api.set_language(self.lang_combo.currentData() or "ko")
        client = self.make_client()
        self.result_list.clear()
        self.main.show_message(t("진단 실행 중...", "Running diagnosis..."), sticky=True)
        self.main.run_async(client.diagnose, self.diag_done)

    def diag_done(self, result):
        # diagnose는 (진단 줄들, 성공한 인증 방식 또는 None)을 반환한다
        lines, found_auth = result if isinstance(result, tuple) else ((result or []), None)
        for line in lines or []:
            self.result_list.addItem(str(line))
        # 진단에서 성공한 인증 방식이 있으면 설정에 저장해 이후 연결에 자동 적용
        if found_auth:
            self.main.config.save(auth_mode=found_auth)
            self.copy_btn.setEnabled(True)
            self.main.show_message(t(
                f"인증 방식 '{found_auth}'로 자동 재연결에 성공했습니다. '연결 저장'을 눌러 유지하세요.",
                f"Auth method '{found_auth}' works - press Save to keep it."))
        else:
            self.copy_btn.setEnabled(True)
            self.main.show_message(t(
                "진단 결과가 목록에 표시됩니다. '진단 결과 복사'로 복사해 전달하면 원인 파악이 빨라집니다.",
                "Diagnosis listed; copy it when reporting issues."))

    def copy_diag(self):
        from PySide6.QtWidgets import QApplication
        items = []
        for i in range(self.result_list.count()):
            items.append(self.result_list.item(i).text())
        QApplication.clipboard().setText("\n".join(items))
        self.main.show_message(t("진단 결과를 클립보드에 복사했습니다.",
                                       "Diagnosis copied to clipboard."))


# ------------------------- 대시보드 탭

class DashboardPage(QWidget):
    def __init__(self, main: "MainWindow"):
        super().__init__()
        self.main = main

        self.info_lbl = QLabel("시스템 정보 없음")
        self.info_lbl.setWordWrap(True)
        self.cpu_lbl = QLabel("")
        self.cpu_bar = QProgressBar()
        self.cores_tbl = QTableWidget()
        self._setup_cores_table()
        self.mem_ring = RingGauge("메모리 사용률", diameter=150)
        self.mem_detail = QLabel("")
        self.pools_table = QTableWidget()
        self.alerts_list = QListWidget()

        refresh_btn = QPushButton("대시보드 새로고침")
        refresh_btn.clicked.connect(self.refresh)

        self._setup_pools_table()

        outer = QVBoxLayout()
        outer.addWidget(self.info_lbl)
        outer.addWidget(QLabel("CPU 사용률"))
        outer.addWidget(self.cpu_lbl)
        outer.addWidget(self.cpu_bar)
        outer.addWidget(QLabel("코어별 사용률"))
        outer.addWidget(self.cores_tbl, stretch=1)
        outer.addWidget(QLabel("메모리 사용률"))
        outer.addWidget(self.mem_ring)
        outer.addWidget(self.mem_detail)
        outer.addWidget(QLabel("스토리지 풀"))
        outer.addWidget(self.pools_table, stretch=2)
        outer.addWidget(QLabel("활성 알림"))
        outer.addWidget(self.alerts_list, stretch=1)
        outer.addWidget(refresh_btn)
        self.setLayout(outer)
        self.refresh()

    def _setup_cores_table(self):
        headers = ["코어", "사용률"]
        self.cores_tbl.setColumnCount(len(headers))
        self.cores_tbl.setHorizontalHeaderLabels(headers)
        self.cores_tbl.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.cores_tbl.setEditTriggers(QTableWidget.NoEditTriggers)
        self.cores_tbl.setMaximumHeight(220)

    def _setup_pools_table(self):
        headers = ["풀", "상태", "사용", "전체", "남음", "사용률"]
        self.pools_table.setColumnCount(len(headers))
        self.pools_table.setHorizontalHeaderLabels(headers)
        self.pools_table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.pools_table.setEditTriggers(QTableWidget.NoEditTriggers)

    def refresh(self):
        client = self.main.client()
        if client is None:
            self.main.show_message("먼저 '연결 설정' 탭에서 연결을 저장하세요.")
            return
        self.main.run_async(self._load, self.on_loaded)

    def _load(self) -> dict:
        client = self.main.client()
        return {
            "info": client.system_info(),
            "cpu": client.cpu_usage(),
            "cores": client.cpu_core_usages(),
            "temps": client.disk_temperatures(),
            "mem": client.memory_usage(),
            "pools": client.pools(),
            "alerts": client.alerts(),
        }

    def on_loaded(self, data: dict):
        info = data.get("info") or {}
        cpu_model = info.get("model") or "-"
        cores_count = info.get("cores") or "-"
        self.info_lbl.setText(
            f"호스트: {info.get('hostname', '-')}   버전: {info.get('version', '-')}\n"
            f"CPU: {cpu_model} ({cores_count}스레드)\n"
            f"가동 시간: {info.get('uptime', '-')}"
        )
        set_percent(self.cpu_bar, data.get("cpu"))

        # 코어별 사용률 표
        cores = data.get("cores") or []
        self.cores_tbl.setRowCount(max(len(cores), 0))
        for row, c in enumerate(cores):
            self.cores_tbl.setItem(row, 0, QTableWidgetItem(str(c.get("name") or "-")))
            val = float(c.get("value") or 0.0)
            item = QTableWidgetItem(f"{val:0.1f}%")
            if val >= 80:
                item.setForeground(QColor("red"))
            elif val >= 50:
                item.setForeground(QColor("orange"))
            self.cores_tbl.setItem(row, 1, item)

        mem = data.get("mem") or {}
        free = mem.get("free")
        if free is not None:
            used_pct = 100.0 - float(free)
            self.mem_ring.set_percent(used_pct)
            physmem = info.get("physmem")
            if physmem:
                total_b = float(physmem)
                used_b = total_b * used_pct / 100.0
                self.mem_detail.setText(
                    f"전체 {fmt_bytes(int(total_b))} · 사용 {fmt_bytes(int(used_b))} ({used_pct:0.1f}%) · "
                    f"남음 {fmt_bytes(int(total_b - used_b))}")
            else:
                self.mem_detail.setText(f"남음 {float(free):0.1f}%")
        else:
            self.mem_ring.set_percent(None)
            self.mem_detail.setText("")

        pools = data.get("pools") or []
        self._setup_pools_table()
        self.pools_table.setRowCount(len(pools))
        for row, pool in enumerate(pools):
            used = pool.get("allocated") or 0
            size = pool.get("size") or 0
            pct = (used / size * 100) if size > 0 else 0.0
            cells = [pool.get("name") or "-", pool.get("status") or "-", fmt_bytes(used),
                     fmt_bytes(size), fmt_bytes(pool.get("free")), f"{pct:0.1f}%"]
            for col, val in enumerate(cells):
                item = QTableWidgetItem(str(val))
                if col == 1:
                    item.setForeground(status_color(str(val)))
                self.pools_table.setItem(row, col, item)

        self.alerts_list.clear()
        for alert in data.get("alerts") or []:
            severity = str(alert.get("level") or alert.get("severity") or "").upper()
            text = f"[{severity}] {alert.get('klass', '')} :: {alert.get('formatted', '')}"
            self.alerts_list.addItem(text)



# ------------------------- 원형 게이지 (램 사용량을 도넛 모양으로 표시)

class RingGauge(QWidget):
    """도넛형 원형 게이지. set_percent(None)이면 '-'를 표시한다."""

    def __init__(self, label: str = "", diameter: int = 96, parent=None):
        super().__init__(parent)
        self._label = label
        self._percent: Optional[float] = None
        self._diameter = diameter
        self.setFixedHeight(diameter + 28)

    def set_percent(self, value: Optional[float]):
        self._percent = max(0.0, min(100.0, value)) if value is not None else None
        self.update()

    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        side = min(self.width(), self.height() - 28)
        side = max(40, side)
        cx = (self.width() - side) // 2
        cy = 2
        rect = QRectF(cx, cy, side, side)
        width = max(6, side // 10)

        # 배경 링
        bg = QPen(QColor("#4c4c50"), width, Qt.SolidLine, Qt.RoundCap)
        p.setPen(bg)
        draw_arc = 360 * 16
        p.drawArc(rect, 0, draw_arc)

        if self._percent is None:
            arc_pen = QPen(QColor("#888888"), width, Qt.SolidLine, Qt.RoundCap)
            p.setPen(arc_pen)
            p.drawArc(rect, 0, draw_arc)
        else:
            pct = float(self._percent)
            color = QColor("#3478f6")
            if pct >= 90:
                color = QColor("#e03131")
            elif pct >= 75:
                color = QColor("#f76707")
            arc_pen = QPen(color, width, Qt.SolidLine, Qt.RoundCap)
            p.setPen(arc_pen)
            # Qt 각도: 반시계 방향 3시 위치 기준 1/16도. 시계 방향 채우기 = 음수 각도
            span = -int(360 * 16 * pct / 100.0)
            p.drawArc(rect, 90 * 16, span)

        # 중앙 백분율 텍스트
        text = "-" if self._percent is None else f"{self._percent:0.0f}%"
        p.setPen(QColor("#cccccc"))
        f = self.font()
        f.setPointSizeF(12)
        f.setBold(True)
        p.setFont(f)
        p.drawText(rect, Qt.AlignCenter, text)

        # 아래 레이블
        if self._label:
            p.setPen(QColor("#999999"))
            f2 = self.font()
            f2.setPointSizeF(9)
            p.setFont(f2)
            p.drawText(QRectF(0, cy + side, self.width(), 22), Qt.AlignCenter, self._label)
        p.end()


def set_percent(bar: QProgressBar, percent: Optional[float]):
    if percent is None:
        bar.setValue(0)
        bar.setFormat("데이터 없음")
    else:
        bar.setValue(int(max(0, min(100, percent))))
        bar.setFormat(f"{percent:0.1f}%")


# ------------------------- 범용 엔티티 페이지 (카테고리 사양 기반)

class EntitySpec:
    """단일 엔티티 목록/생성/삭제/편집을 담당하는 범용 사양"""

    def __init__(self, title: str, endpoint: str, columns,
                 id_field: str = "id", delete_path: Optional[str] = None,
                 create_fields=None, create_defaults=None, read_only: bool = False,
                 edit_fields=None):
        self.title = title
        self.endpoint = endpoint
        self.columns = columns  # [(json_key, header, kind)] kind: raw/bytes/bool/time/percent
        self.id_field = id_field
        self.delete_path = delete_path  # 기본: endpoint + "/id/{id}"
        self.edit_fields = edit_fields or []  # 편집 가능 항목(있으면 편집 버튼 표시)
        self.create_fields = create_fields or []  # [{"key","label","kind"}] kind: text/password/number/choice_datasets/bool
        self.create_defaults = create_defaults or {}
        self.read_only = read_only

    def delete_url(self, row_id: Any) -> str:
        base = self.delete_path or f"{self.endpoint}/id/"
        return f"{base}{quote(str(row_id), safe='')}"

    def edit_url(self, row_id: Any) -> str:
        return f"{self.endpoint}/id/{quote(str(row_id), safe='')}"


from urllib.parse import quote  # noqa: E402


class EntityPage(QWidget):
    """사양 하나로 목록/생성/삭제를 처리하는 범용 화면"""

    def __init__(self, main: "MainWindow", spec: EntitySpec):
        super().__init__()
        self.main = main
        self.spec = spec
        self.rows = []

        table_headers = [h for _, h, _ in spec.columns]
        self.table = QTableWidget()
        self.table.setColumnCount(len(spec.columns))
        self.table.setHorizontalHeaderLabels(table_headers)
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.table.setEditTriggers(QTableWidget.NoEditTriggers)

        btns = QHBoxLayout()
        if spec.create_fields:
            add_btn = QPushButton("추가")
            add_btn.clicked.connect(self.on_add)
            btns.addWidget(add_btn)
        if spec.edit_fields:
            edit_btn = QPushButton("선택 편집")
            edit_btn.clicked.connect(self.on_edit)
            btns.addWidget(edit_btn)
        if not spec.read_only:
            del_btn = QPushButton("선택 삭제")
            del_btn.clicked.connect(self.on_delete)
            btns.addWidget(del_btn)
        refresh_btn = QPushButton("새로고침")
        refresh_btn.clicked.connect(self.refresh)
        btns.addStretch(1)
        btns.addWidget(refresh_btn)

        outer = QVBoxLayout()
        outer.addWidget(self.table)
        outer.addLayout(btns)
        self.setLayout(outer)
        self.refresh()

    def _load_rows(self):
        client = self.main.client()
        rows = client.get_list(self.spec.endpoint)
        if rows and self.spec.endpoint == "/disk":
            # 디스크 온도 병합 (25.10: POST /disk/temperatures {})
            try:
                temps = client.disk_temperatures()
            except TruenasError:
                temps = {}
            if temps:
                rows = [dict(r, temperature=temps.get(r.get("name"))) for r in rows]
        return rows

    def refresh(self):
        client = self.main.client()
        if client is None:
            self.main.show_message("먼저 연결을 저장하세요.")
            return
        self.main.run_async(self._load_rows, self.on_loaded)

    def on_loaded(self, rows):
        self.rows = rows or []
        self.table.setRowCount(len(self.rows))
        for row, entry in enumerate(self.rows):
            for col, (key, _header, kind) in enumerate(self.spec.columns):
                val = render_value(entry.get(key), kind)
                item = QTableWidgetItem(val)
                if key == "status":
                    item.setForeground(status_color(val))
                self.table.setItem(row, col, item)

    def _primary(self, row: int):
        if row < 0 or row >= len(self.rows):
            return None, None
        entry = self.rows[row]
        return entry.get(self.spec.id_field), entry

    def on_add(self):
        dlg = EntityCreateDialog(self, self.spec, self.main.choice_datasets())
        if dlg.exec() != QDialog.Accepted:
            return
        body = dict(self.spec.create_defaults or {})
        for key in self.spec.create_fields:
            value = dlg.values().get(key)
            if value in ("", None):
                continue
            body[key] = value
        client = self.main.client()
        title = self.spec.title
        self.main.run_async(
            lambda: (client.post(self.spec.endpoint, body), f"{title} 항목 추가 완료"),
            self.main.reload_entity(self),
        )

    def on_delete(self):
        row = self.table.currentRow()
        row_id, entry = self._primary(row)
        if row_id is None:
            self.main.show_message("삭제할 항목을 테이블에서 선택하세요.")
            return
        label_text = str(entry.get(self.spec.columns[0][0]) or row_id)
        if QMessageBox.question(self, "삭제",
                                f"항목 '{label_text}'을(를) 삭제할까요?\n되돌릴 수 없습니다.") != QMessageBox.Yes:
            return
        client = self.main.client()
        dept = self.spec.delete_url(row_id)
        title = self.spec.title
        self.main.run_async(
            lambda: (client.delete(dept), f"{title} 항목 삭제 완료"),
            self.main.reload_entity(self),
        )

    def on_edit(self):
        row = self.table.currentRow()
        row_id, entry = self._primary(row)
        if row_id is None:
            self.main.show_message("편집할 항목을 테이블에서 선택하세요.")
            return
        dlg = EntityEditDialog(self, self.spec, entry or {})
        if dlg.exec() != QDialog.Accepted:
            return
        body = {k: v for k, v in dlg.values().items() if v not in ("", None)}
        client = self.main.client()
        title = self.spec.title
        self.main.run_async(
            lambda: (client.edit_entity(self.spec, row_id, body), f"{title} 항목 편집 완료"),
            self.main.reload_entity(self),
        )


# ------------------------- 웹 대시보드 대응 확장 페이지

class TextPage(QWidget):
    """load() -> (제목 없는 텍스트 레포트) 형태의 간단히 보기 페이지"""

    def __init__(self, main: "MainWindow", loader, extra_buttons=None):
        super().__init__()
        self.main = main
        self.loader = loader
        self.report = QLabel("로딩...")
        self.report.setWordWrap(True)
        refresh_btn = QPushButton("새로고침")
        refresh_btn.clicked.connect(self.refresh)
        outer = QVBoxLayout()
        outer.addWidget(self.report)
        btns = QHBoxLayout()
        btns.addStretch(1)
        for label, handler in (extra_buttons or []):
            btn = QPushButton(label)
            btn.clicked.connect(handler)
            btns.addWidget(btn)
        btns.addWidget(refresh_btn)
        outer.addLayout(btns)
        self.setLayout(outer)
        self.refresh()

    def refresh(self):
        client = self.main.client()
        if client is None:
            self.main.show_message("먼저 연결을 저장하세요.")
            return
        self.main.run_async(self.loader, self.on_loaded)

    def on_loaded(self, text):
        self.report.setText(text if text else "데이터 없음")


class ListPage(QWidget):
    """표 형태 데이터 + 선택 액션 버튼만 있는 재사용 페이지.
    actions: [(레이블, 콜백(row_values: dict), 확인_문구 또는 None)]"""

    def __init__(self, main: "MainWindow", loader, columns, actions=None,
                 searchable: bool = False, note: str = "", row_id_key: str = "id"):
        super().__init__()
        self.main = main
        self.loader = loader
        self.columns = columns
        self.actions = actions or []
        self.row_id_key = row_id_key
        self.rows: list = []

        self.table = QTableWidget()
        self.table.setColumnCount(len(columns))
        self.table.setHorizontalHeaderLabels([h for _, h, _ in columns])
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.table.setEditTriggers(QTableWidget.NoEditTriggers)

        btns = QHBoxLayout()
        if searchable:
            self.search = QLineEdit()
            self.search.setPlaceholderText("검색(이름)")
            self.search.textChanged.connect(self._filter)
            btns.addWidget(self.search)
        for label, _handler, _confirm in self.actions:
            btn = QPushButton(label)
            btn.clicked.connect(lambda _=False, l=label: self.on_action(l))
            btns.addWidget(btn)
        btns.addStretch(1)
        refresh_btn = QPushButton("새로고침")
        refresh_btn.clicked.connect(self.refresh)
        btns.addWidget(refresh_btn)

        outer = QVBoxLayout()
        if note:
            n = QLabel(note)
            n.setWordWrap(True)
            outer.addWidget(n)
        outer.addWidget(self.table, stretch=2)
        outer.addLayout(btns)
        self.setLayout(outer)
        self.refresh()

    def refresh(self):
        client = self.main.client()
        if client is None:
            self.main.show_message("먼저 연결을 저장하세요.")
            return
        self.main.run_async(self.loader, self.on_loaded)

    def on_loaded(self, rows):
        self.rows = rows or []
        self._render(self.rows)

    def _filter(self, *_):
        text = (self.search.text() or "").lower() if hasattr(self, "search") else ""
        if not text:
            self._render(self.rows)
            return
        self._render([r for r in self.rows
                     if text in str(r.get("name") or "").lower()
                     or text in str(r.get("description") or "").lower()])

    def _render(self, rows):
        self.table.setRowCount(len(rows))
        for row, entry in enumerate(rows):
            for col, (key, _header, kind) in enumerate(self.columns):
                item = QTableWidgetItem(render_value(entry.get(key), kind))
                self.table.setItem(row, col, item)
            self.table.item(row, 0).setData(Qt.UserRole, entry)

    def _selected(self):
        row = self.table.currentRow()
        if row < 0:
            return None
        return self.table.item(row, 0).data(Qt.UserRole)

    def on_action(self, label: str):
        entry = self._selected()
        if entry is None:
            self.main.show_message("작업할 항목을 표에서 선택하세요.")
            return
        for l, handler, confirm in self.actions:
            if l != label:
                continue
            if confirm:
                if QMessageBox.question(self, label, confirm) != QMessageBox.Yes:
                    return
            client = self.main.client()
            self.main.run_async(lambda: (handler(client, entry), f"{label} 완료"),
                                self.main.reload_entity(self))
            return


class UpdateSystemPage(QWidget):
    """TrueNAS 본체 업데이트: 상태 확인 + 설치 실행(이중 확인)"""

    def __init__(self, main: "MainWindow"):
        super().__init__()
        self.main = main
        self.report = QLabel("로딩...")
        self.report.setWordWrap(True)
        check_btn = QPushButton("업데이트 확인")
        check_btn.clicked.connect(self.refresh)
        run_btn = QPushButton("실제 업데이트 설치(재부팅)")
        run_btn.clicked.connect(self.on_run)
        outer = QVBoxLayout()
        outer.addWidget(self.report)
        btns = QHBoxLayout()
        btns.addStretch(1)
        btns.addWidget(check_btn)
        btns.addWidget(run_btn)
        outer.addLayout(btns)
        self.setLayout(outer)
        self.refresh()

    @staticmethod
    def _new_version(info: dict) -> Optional[dict]:
        status = (info or {}).get("status") or {}
        new = status.get("new_version")
        return new if isinstance(new, dict) else None

    def refresh(self):
        client = self.main.client()
        if client is None:
            self.main.show_message("먼저 연결을 저장하세요.")
            return

        def load():
            status = client.update_status()
            versions = client.update_available_versions()
            return {"status": status, "versions": versions}

        self.main.run_async(load, self.on_loaded)

    def on_loaded(self, data):
        status = (data or {}).get("status") or {}
        versions = (data or {}).get("versions") or []
        cur = (status.get("status") or {}).get("current_version") or {}
        new = self._new_version(status)
        lines = [
            f"현재 트레인: {cur.get('train', '-')} ({cur.get('profile', '-')})",
            f"코드: {status.get('code', '-')}",
            f"새 버전: " + (str(new) if new else "없음 (최신)"),
            f"가용 버전 목록: {', '.join(str(v) for v in versions[:10]) or '-'}",
        ]
        self.report.setText("\n".join(lines))

    def on_run(self):
        if QMessageBox.question(self, "TrueNAS 업데이트 설치",
                                "정말로 TrueNAS 본체 업데이트를 실행할까요?\n"
                                "다운로드 후 시스템이 재부팅되며 몇 분 걸릴 수 있습니다.") \
                != QMessageBox.Yes:
            return
        if QMessageBox.question(self, "최종 확인",
                                "다시 한 번 확인합니다. 실행 중인 앱/서비스가 중단됩니다.\n계속할까요?") \
                != QMessageBox.Yes:
            return
        client = self.main.client()
        self.main.run_async(
            lambda: (client.update_run(reboot=True), "업데이트 실행: 다운로드-설치-재부팅 시작"),
            lambda *_: self.main.show_message("업데이트 시작됨 - 완료 후 재연결하세요"))


class AppCatalogPage(QWidget):
    def __init__(self, main: "MainWindow"):
        super().__init__()
        self.main = main
        self.rows: list = []
        self.table = QTableWidget()
        self.table.setColumnCount(4)
        self.table.setHorizontalHeaderLabels(["이름", "버전", "카테고리", "설명"])
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.table.setEditTriggers(QTableWidget.NoEditTriggers)
        self.search = QLineEdit()
        self.search.setPlaceholderText("앱 이름/설명 검색")
        self.search.textChanged.connect(self._filter)
        note = QLabel("설치는 앱별 설정 스키마가 달라 TrueNAS 웹 UI에서 권장합니다. 이 화면은 카탈로그 검색/버전 확인용.")
        note.setWordWrap(True)
        refresh_btn = QPushButton("새로고침")
        refresh_btn.clicked.connect(self.refresh)
        outer = QVBoxLayout()
        outer.addWidget(self.search)
        outer.addWidget(note)
        outer.addWidget(self.table, stretch=2)
        outer.addWidget(refresh_btn)
        self.setLayout(outer)
        self.refresh()

    def refresh(self):
        client = self.main.client()
        if client is None:
            self.main.show_message("먼저 연결을 저장하세요.")
            return
        self.main.run_async(client.app_catalog, self.on_loaded)

    def on_loaded(self, rows):
        self.rows = rows or []
        self._filter()

    def _filter(self, *_):
        text = (self.search.text() or "").lower()
        rows = [r for r in self.rows
                if not text or text in str(r.get("name") or "").lower()
                or text in str(r.get("description") or "").lower()]
        self.table.setRowCount(len(rows))
        for i, r in enumerate(rows):
            cats = ", ".join(str(c) for c in (r.get("categories") or [])[:3])
            cells = [r.get("name"), r.get("latest_human_version") or "-", cats,
                     str(r.get("description") or "-")[:160]]
            for col, val in enumerate(cells):
                self.table.setItem(i, col, QTableWidgetItem("" if val is None else str(val)))


class ApiKeyPage(QWidget):
    """API 키 목록/생성/삭제(폐기)"""

    def __init__(self, main: "MainWindow"):
        super().__init__()
        self.main = main
        self.rows: list = []
        self.table = QTableWidget()
        self.table.setColumnCount(5)
        self.table.setHorizontalHeaderLabels(["이름", "사용자", "생성일", "폐기됨", "ID"])
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.table.setEditTriggers(QTableWidget.NoEditTriggers)
        add_btn = QPushButton("API 키 생성")
        add_btn.clicked.connect(self.on_add)
        del_btn = QPushButton("선택 키 폐기")
        del_btn.clicked.connect(self.on_revoke)
        refresh_btn = QPushButton("새로고침")
        refresh_btn.clicked.connect(self.refresh)
        btns = QHBoxLayout()
        btns.addStretch(1)
        btns.addWidget(add_btn)
        btns.addWidget(del_btn)
        btns.addWidget(refresh_btn)
        outer = QVBoxLayout()
        outer.addWidget(self.table, stretch=2)
        outer.addLayout(btns)
        self.setLayout(outer)
        self.refresh()

    def refresh(self):
        client = self.main.client()
        if client is None:
            self.main.show_message("먼저 연결을 저장하세요.")
            return
        self.main.run_async(client.api_keys, self.on_loaded)

    def on_loaded(self, rows):
        self.rows = rows or []
        self.table.setRowCount(len(self.rows))
        for i, r in enumerate(self.rows):
            created = fmt_epoch(r.get("created_at"))
            cells = [r.get("name"), r.get("username"), created,
                     "예" if r.get("revoked") else "아니오", r.get("id")]
            for col, val in enumerate(cells):
                item = QTableWidgetItem("" if val is None else str(val))
                if col == 3 and r.get("revoked"):
                    item.setForeground(QColor("gray"))
                self.table.setItem(i, col, item)
            self.table.item(i, 0).setData(Qt.UserRole, r)

    def on_add(self):
        name, ok = QInputDialog.getText(self, "API 키 생성", "키 이름:")
        if not ok or not name.strip():
            return
        user, ok = QInputDialog.getText(self, "API 키 생성",
                                        "발급 사용자명(예: truenas_admin):")
        if not ok or not user.strip():
            return
        client = self.main.client()

        def load():
            created = client.create_api_key(name.strip(), user.strip())
            keys = client.api_keys()
            return {"created": created, "keys": keys}

        def done(data):
            key_value = (data or {}).get("created", {}).get("key")
            if key_value:
                QMessageBox.information(
                    self, "API 키 발급 완료",
                    f"앱에 다시 표시되지 않으므로 지금 복사하세요:\n\n{key_value}")
            self.on_loaded((data or {}).get("keys"))

        self.main.run_async(load, done)

    def on_revoke(self):
        row = self.table.currentRow()
        if row < 0:
            self.main.show_message("폐기할 키를 선택하세요.")
            return
        entry = self.table.item(row, 0).data(Qt.UserRole)
        key_id = (entry or {}).get("id")
        if QMessageBox.question(self, "키 폐기",
                                f"API 키 '{(entry or {}).get('name')}' 을(를) 폐기할까요?\n"
                                "폐기된 키로는 더 이상 접속할 수 없습니다.") != QMessageBox.Yes:
            return
        client = self.main.client()
        self.main.run_async(
            lambda: (client.revoke_api_key(key_id), "API 키 폐기 완료"),
            self.main.reload_entity(self),
        )


def _static_route_page(main: "MainWindow") -> QWidget:
    """정적 라우트 목록 + 추가(대상/게이트웨이 입력) + 삭제"""
    page = ListPage(
        main,
        lambda: main.client().static_routes(),
        columns=[("destination", "대상", "raw"), ("gateway", "게이트웨이", "raw"),
                 ("description", "설명", "raw")],
        actions=[
            ("추가",
             lambda c, r: c.add_static_route(
                 r["destination"], r["gateway"], r.get("description", "")),
             None),
            ("삭제",
             lambda c, r: c.delete_static_route(r.get("id")),
             "정적 라우트를 삭제할까요?"),
        ],
        note="추가 버튼은 대상(SRC 또는 CIDR)/게이트웨이를 입력한 뒤 실행합니다.",
    )
    _wire_add_static_route(page)
    return page


def _wire_add_static_route(page: ListPage) -> None:
    """ListPage의 '추가' 버튼을 입력 대화상자 + 생성 API로 연결"""
    for i, (label, _handler, _confirm) in enumerate(page.actions):
        if label == "추가":
            action_button = None
            for w in page.findChildren(QPushButton):
                if w.text() == label:
                    action_button = w
                    break
            if action_button is not None:
                # 기본 처리(엔티티 액션 실행)를 끊고 추가 대화상자로 교체한다.
                try:
                    action_button.clicked.disconnect()
                except (RuntimeError, TypeError):
                    pass  # 연결된 슬롯이 없으면 무시
                action_button.clicked.connect(lambda: _add_static_route_dialog(page))


def _add_static_route_dialog(page: ListPage) -> None:
    destination, ok = QInputDialog.getText(page, "정적 라우트 추가",
                                           "대상(예: 192.168.10.0/24):")
    if not ok or not destination.strip():
        return
    gateway, ok = QInputDialog.getText(page, "정적 라우트 추가",
                                       "게이트웨이(예: 192.168.10.1):")
    if not ok or not gateway.strip():
        return
    desc, ok = QInputDialog.getText(page, "정적 라우트 추가", "설명(선택):")
    if not ok:
        return
    client = page.main.client()
    page.main.run_async(
        lambda: (client.add_static_route(destination.strip(), gateway.strip(), desc.strip()),
                 "정적 라우트 추가 완료"),
        page.main.reload_entity(page),
    )


def _network_report(client) -> str:
    """네트워크 요약 텍스트(인터페이스 IP + 기본 게이트웨이 + DNS)"""
    lines = []
    try:
        s = client.network_summary()
        for iface, v in (s.get("ips") or {}).items():
            v4 = ", ".join(v.get("IPV4") or []) or "-"
            v6 = ", ".join(v.get("IPV6") or []) or "-"
            lines.append(f"인터페이스 {iface}: IPv4 {v4} / IPv6 {v6}")
        gates = ", ".join(str(g) for g in (s.get("default_routes") or [])) or "-"
        lines.append(f"기본 게이트웨이: {gates}")
        ns = ", ".join(str(n) for n in (s.get("nameservers") or [])) or "-"
        lines.append(f"DNS: {ns}")
    except TruenasError as err:
        lines.append(f"요약 조회 실패: {err}")
    try:
        cfg = client.network_configuration()
        lines.append(f"호스트명: {cfg.get('hostname', '-')} / 도메인: {cfg.get('domain', '-')}")
    except TruenasError:
        pass
    return "\n".join(lines) or "데이터 없음"


def render_value(val: Any, kind: str) -> str:
    if val is None:
        return "-"
    if kind == "bytes":
        return fmt_bytes(val)
    if kind == "bool":
        return "예" if val else "아니오"
    if kind == "time":
        return fmt_epoch(val)
    if kind == "celsius":
        try:
            return f"{float(val):0.1f}"
        except (TypeError, ValueError):
            return "-"
    if kind == "list":
        if isinstance(val, (list, tuple)):
            return ", ".join(str(x.get("path", x) if isinstance(x, dict) else x) for x in val) or "-"
        return "-"
    if isinstance(val, (dict, list)):
        import json
        return json.dumps(val, ensure_ascii=False)[:120]
    return str(val)


class EntityCreateDialog(QDialog):
    """create_fields 사양으로 폼을 동적으로 생성하는 다이얼로그"""

    def __init__(self, parent: QWidget, spec: EntitySpec, dataset_choices):
        super().__init__(parent)
        self.setWindowTitle(f"{spec.title} 추가")
        self.spec = spec
        self.editors: dict = {}

        form = QFormLayout(self)
        for field in spec.create_fields:
            key = field["key"]
            label = field.get("label", key)
            kind = field.get("kind", "text")
            if kind == "password":
                edit = password_line()
                form.addRow(label, edit)
            elif kind == "bool":
                check = QCheckBox()
                form.addRow(label, check)
                self.editors[key] = check
                continue
            elif kind == "choice_datasets":
                combo = QComboBox()
                combo.addItems(dataset_choices or ["(데이터셋 불러오려면 새로고침)"])
                form.addRow(label, combo)
                self.editors[key] = combo
                continue
            elif kind == "number":
                edit = QLineEdit()
                edit.setPlaceholderText("숫자")
                form.addRow(label, edit)
            else:
                edit = QLineEdit()
                form.addRow(label, edit)
            self.editors[key] = edit

        bb = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        bb.accepted.connect(self.accept)
        bb.rejected.connect(self.reject)
        form.addRow(bb)

    def values(self) -> dict:
        out = {}
        for key, editor in self.editors.items():
            if isinstance(editor, QComboBox):
                out[key] = editor.currentText()
            elif isinstance(editor, QCheckBox):
                out[key] = editor.isChecked()
            else:
                out[key] = editor.text().strip()
        return out


class EntityEditDialog(QDialog):
    """EntitySpec.edit_fields 로 기존 항목을 편집(PUT)한다."""

    def __init__(self, parent: QWidget, spec: EntitySpec, entry: dict):
        super().__init__(parent)
        self.setWindowTitle(f"{spec.title} 편집")
        self.spec = spec
        self.editors: dict = {}

        form = QFormLayout(self)
        entry = entry or {}
        for field in spec.edit_fields:
            key = field["key"] if isinstance(field, dict) else field.key
            label = (field.get("label", key) if isinstance(field, dict) else field.label)
            kind = (field.get("kind", "text") if isinstance(field, dict) else field.kind)
            current = entry.get(key)

            if kind == "bool":
                check = QCheckBox()
                check.setChecked(bool(current) if current is not None else False)
                form.addRow(label, check)
                self.editors[key] = check
                continue

            edit = QLineEdit()
            if kind == "password":
                edit = password_line()
                edit.setPlaceholderText("변경 시에만 입력")
            else:
                if current is not None:
                    if kind == "list":
                        try:
                            edit.setText(", ".join(str(x) for x in current))
                        except (TypeError, ValueError):
                            edit.setText(str(current))
                    else:
                        edit.setText(str(current))
            form.addRow(label, edit)
            self.editors[key] = edit

        bb = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        bb.accepted.connect(self.accept)
        bb.rejected.connect(self.reject)
        form.addRow(bb)

    def values(self) -> dict:
        out = {}
        for key, editor in self.editors.items():
            if isinstance(editor, QCheckBox):
                out[key] = editor.isChecked()
            else:
                text = editor.text().strip()
                field_kind = self._kind(key)
                if field_kind == "list" and text:
                    out[key] = [s.strip() for s in text.split(",") if s.strip()]
                else:
                    out[key] = text
        return out

    def _kind(self, key: str) -> str:
        for field in self.spec.edit_fields:
            k = field["key"] if isinstance(field, dict) else field.key
            if k == key:
                return (field.get("kind", "text") if isinstance(field, dict) else field.kind)
        return "text"# ------------------------- 특수 화면: NAS 현황 / 알림 / 서비스 / 스크럽

class NasOverviewPage(QWidget):
    """저장된 모든 NAS의 사용량을 한 화면에서. 카드(또는 전환 버튼) 클릭 시 해당 NAS로 전환."""

    def __init__(self, main: "MainWindow"):
        super().__init__()
        self.main = main
        self.cards_layout = QVBoxLayout()

        settings_btn = QPushButton("연결 설정 열기")
        settings_btn.clicked.connect(self._open_settings)
        refresh_btn = QPushButton("전체 새로고침")
        refresh_btn.clicked.connect(self.refresh)

        host = QWidget()
        host.setLayout(self.cards_layout)
        scroll = QScrollArea()
        scroll.setWidget(host)
        scroll.setWidgetResizable(True)

        outer = QVBoxLayout()
        outer.addWidget(scroll, stretch=1)
        footer = QHBoxLayout()
        footer.addStretch(1)
        footer.addWidget(settings_btn)
        footer.addWidget(refresh_btn)
        outer.addLayout(footer)
        self.setLayout(outer)
        self.refresh()

    def _open_settings(self):
        self.main.show_connection_page()

    def refresh(self):
        while self.cards_layout.count():
            item = self.cards_layout.takeAt(0)
            w = item.widget()
            if w is not None:
                w.deleteLater()

        profiles = self.main.config.profiles()
        rows = profiles.get("list", []) or []
        if not rows:
            self.cards_layout.addWidget(QLabel("저장된 NAS가 없습니다. 연결 설정에서 추가하세요."))
            return
        active, _ = self.main.config.active_profile()
        for item in rows:
            card = _NasCard(self.main, item, is_active=item.get("name") == active)
            self.cards_layout.addWidget(card)
            card.start_load()


class _NasCard(QFrame):
    """한 NAS의 요약 카드. 카드(또는 전환 버튼)를 클릭하면 해당 NAS로 전환한다."""

    def __init__(self, main: "MainWindow", item: dict, is_active: bool):
        super().__init__()
        self.main = main
        self.item = item
        self.name = str(item.get("name") or "-")
        self.setAutoFillBackground(True)
        self.setCursor(Qt.PointingHandCursor)
        self.setStyleSheet(
            "_NasCard { background: rgba(128,128,128,0.09); border: 1px solid rgba(128,128,128,0.25); border-radius: 8px; }"
        )
        self._ring = RingGauge(self.name, diameter=120)

        self.title = QLabel(self.name)
        self.title.setStyleSheet("background: transparent; border: none; font-weight: bold; font-size: 14px;")
        self.badge = QLabel("현재 연결" if is_active else "")
        if is_active:
            self.badge.setStyleSheet(
                "background: transparent; border: none; color: #3478f6; padding: 1px 8px;")
        self.detail = QLabel("조회 중...")
        self.detail.setWordWrap(True)
        self.detail.setStyleSheet("background: transparent; border: none;")
        self.pools_line = QLabel("")
        self.pools_line.setWordWrap(True)
        self.pools_line.setStyleSheet("background: transparent; border: none;")

        header = QHBoxLayout()
        header.addWidget(self.title)
        header.addWidget(self.badge)
        header.addStretch(1)
        if not is_active:
            switch_btn = QPushButton("전환")
            switch_btn.clicked.connect(self._switch)
            header.addWidget(switch_btn)

        row = QHBoxLayout()
        row.addWidget(self._ring)
        info_col = QVBoxLayout()
        info_col.addWidget(self.detail)
        info_col.addWidget(self.pools_line)
        row.addLayout(info_col, stretch=1)

        inner = QVBoxLayout(self)
        inner.addLayout(header)
        inner.addLayout(row)

    def mousePressEvent(self, event):
        self._switch()

    def _switch(self):
        self.main.switch_profile(self.name)

    def start_load(self):
        self.main.run_async(self._load_row, self.on_loaded)

    def _load_row(self) -> dict:
        item = self.item
        client = TruenasClient(
            str(item.get("base_url") or ""), str(item.get("api_key") or ""),
            verify_tls=bool(item.get("verify_tls")), port=str(item.get("port") or "") or None,
            auth_mode=item.get("auth_mode") or None, basic_user=item.get("basic_user") or None)
        row: dict = {"pools": [], "alerts": 0, "ok": False}
        try:
            row["pools"] = client.pools()
            row["alerts"] = len([a for a in (client.alerts() or []) if not a.get("dismissed")])
            info = client.system_info()
            row["version"] = str(info.get("version") or "-")
            row["ok"] = bool(info or row["pools"])
        except Exception as e:  # 연결 실패한 NAS도 카드에 표시
            row["error"] = str(e)
        return row

    def on_loaded(self, data: dict):
        if not data.get("ok"):
            self._ring.set_percent(None)
            self.detail.setText("연결 실패 — 연결 설정에서 주소/키를 확인하세요.")
            self.detail.setStyleSheet("color: #e03131; background: transparent; border: none;")
            self.pools_line.setText(str(data.get("error") or ""))
            return
        self.detail.setText(f"버전 {data.get('version', '-')} · 활성 알림 {data.get('alerts', 0)} 건")
        pools = data.get("pools") or []
        lines: list = []
        first_pct = None
        for p in pools:
            size = int(p.get("size") or 0)
            used = int(p.get("allocated") or 0)
            pct = (used / size * 100.0) if size > 0 else 0.0
            if first_pct is None:
                first_pct = pct
            if p.get("healthy") is False:
                lines.append(f"[주의] {p.get('name')}: {pct:0.0f}% ({fmt_bytes(used)}/{fmt_bytes(size)})")
            else:
                lines.append(f"{p.get('name')}: {pct:0.0f}% ({fmt_bytes(used)}/{fmt_bytes(size)})")
        self.pools_line.setText("\n".join(lines) if lines else "풀(스토리지) 없음")
        self._ring.set_percent(first_pct if first_pct is not None else 0.0)


class AlertPage(QWidget):
    def __init__(self, main: "MainWindow"):
        super().__init__()
        self.main = main
        self.table = QTableWidget()
        self.table.setColumnCount(4)
        self.table.setHorizontalHeaderLabels(["심각도", "분류", "내용", "무시됨"])
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.table.setEditTriggers(QTableWidget.NoEditTriggers)
        del_btn = QPushButton("선택 알림 무시(dismiss)")
        restore_btn = QPushButton("무시 알림 복원(restore)")
        del_btn.clicked.connect(self.on_dismiss)
        restore_btn.clicked.connect(self.on_restore)
        refresh_btn = QPushButton("새로고침")
        refresh_btn.clicked.connect(self.refresh)
        btns = QHBoxLayout()
        btns.addStretch(1)
        btns.addWidget(del_btn)
        btns.addWidget(restore_btn)
        btns.addWidget(refresh_btn)
        outer = QVBoxLayout()
        outer.addWidget(self.table, stretch=2)
        outer.addLayout(btns)
        self.setLayout(outer)
        self.refresh()

    def refresh(self):
        client = self.main.client()
        if client is None:
            self.main.show_message("먼저 연결을 저장하세요.")
            return
        self.main.run_async(client.all_alerts, self.on_loaded)

    def on_loaded(self, alerts):
        alerts = alerts or []
        self.table.setRowCount(len(alerts))
        for row, alert in enumerate(alerts):
            cells = [str(alert.get("level") or alert.get("severity") or "").upper(),
                     alert.get("klass"),
                     alert.get("formatted") or alert.get("alert"),
                     "예" if alert.get("dismissed") else "아니오"]
            for col, val in enumerate(cells):
                item = QTableWidgetItem("" if val is None else str(val))
                if col == 0:
                    item.setForeground(status_color("CRITICAL" if val == "CRITICAL" else val))
                self.table.setItem(row, col, item)
            self.table.item(row, 0).setData(Qt.UserRole, alert.get("id"))
            if alert.get("dismissed"):
                self.table.item(row, 3).setForeground(QColor("gray"))
        if not alerts:
            self.main.show_message("알림이 없습니다.")

    def on_dismiss(self):
        row = self.table.currentRow()
        if row < 0:
            self.main.show_message("무시할 알림을 선택하세요.")
            return
        alert_id = self.table.item(row, 0).data(Qt.UserRole)
        client = self.main.client()
        self.main.run_async(
            lambda: (client.alert_dismiss(alert_id), "알림을 무시 처리했습니다."),
            self.main.reload_entity(self),
        )

    def on_restore(self):
        row = self.table.currentRow()
        if row < 0:
            self.main.show_message("복원할 알림을 선택하세요.")
            return
        alert_id = self.table.item(row, 0).data(Qt.UserRole)
        client = self.main.client()
        self.main.run_async(
            lambda: (client.alert_restore(alert_id), "알림을 복원했습니다."),
            self.main.reload_entity(self),
        )


class ServicePage(QWidget):
    def __init__(self, main: "MainWindow"):
        super().__init__()
        self.main = main
        self.table = QTableWidget()
        self.table.setColumnCount(3)
        self.table.setHorizontalHeaderLabels(["서비스", "상태", "인증 유형"])
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.table.setEditTriggers(QTableWidget.NoEditTriggers)
        self.table.cellClicked.connect(self._on_click)
        self.table.itemDoubleClicked.connect(self._on_toggle)
        restart_btn = QPushButton("선택 서비스 재시작")
        restart_btn.clicked.connect(self.on_restart)
        refresh_btn = QPushButton("새로고침")
        refresh_btn.clicked.connect(self.refresh)
        reboot_btn = QPushButton("시스템 재부팅")
        reboot_btn.clicked.connect(self.on_reboot)
        shutdown_btn = QPushButton("시스템 종료")
        shutdown_btn.clicked.connect(self.on_shutdown)
        note = QLabel("서비스 항목을 더블클릭하면 시작/중지가 전환됩니다.")
        outer = QVBoxLayout()
        outer.addWidget(note)
        outer.addWidget(self.table, stretch=2)
        btn_row = QHBoxLayout()
        btn_row.addWidget(restart_btn)
        btn_row.addStretch(1)
        btn_row.addWidget(reboot_btn)
        btn_row.addWidget(shutdown_btn)
        btn_row.addWidget(refresh_btn)
        outer.addLayout(btn_row)
        self.setLayout(outer)
        self.refresh()

    def refresh(self):
        client = self.main.client()
        if client is None:
            self.main.show_message("먼저 연결을 저장하세요.")
            return
        self.main.run_async(client.services, self.on_loaded)

    def on_loaded(self, services):
        services = services or []
        self.table.setRowCount(len(services))
        for row, svc in enumerate(services):
            running = "실행 중" if svc.get("state") == "RUNNING" else "중지"
            cells = [svc.get("service"), running, str(svc.get("pids") or "-")]
            for col, val in enumerate(cells):
                item = QTableWidgetItem("" if val is None else str(val))
                if col == 1:
                    item.setForeground(QColor("green") if svc.get("state") == "RUNNING" else QColor("gray"))
                self.table.setItem(row, col, item)
            self.table.item(row, 0).setData(Qt.UserRole,
                                            (svc.get("service"), svc.get("state")))
        if not services:
            self.main.show_message("서비스 데이터가 없습니다.")

    def _on_click(self, *_):
        pass

    def on_restart(self):
        row = self.table.currentRow()
        if row < 0:
            self.main.show_message("재시작할 서비스를 선택하세요.")
            return
        service_name = self.table.item(row, 0).data(Qt.UserRole)
        service_name = service_name[0] if isinstance(service_name, tuple) else service_name
        client = self.main.client()
        self.main.run_async(
            lambda: (client.service_restart(service_name), f"서비스 {service_name} 재시작 완료"),
            self.main.reload_entity(self),
        )

    def on_reboot(self):
        if QMessageBox.warning(self, "시스템 재부팅",
                               "TrueNAS를 재부팅할까요?\n실행 중인 앱/서비스가 중단됩니다.") != QMessageBox.Yes:
            return
        client = self.main.client()
        self.main.run_async(
            lambda: (client.system_reboot(), "재부팅 명령을 보냈습니다. 몇 분 후 다시 연결하세요."),
            lambda *_: self.main.show_message("재부팅 시작됨"),
        )

    def on_shutdown(self):
        if QMessageBox.warning(self, "시스템 종료",
                               "TrueNAS 전원을 끌까요?\n실행 중인 앱/서비스가 중단됩니다.") != QMessageBox.Yes:
            return
        client = self.main.client()
        self.main.run_async(
            lambda: (client.system_shutdown(), "종료 명령을 보냈습니다."),
            lambda *_: self.main.show_message("종료 시작됨"),
        )

    def _on_toggle(self, item):
        row = item.row()
        data = self.table.item(row, 0).data(Qt.UserRole)
        service_name, state = data
        client = self.main.client()
        if state == "RUNNING":
            self.main.run_async(
                lambda: (client.service_stop(service_name), "서비스 중지 완료"),
                self.main.reload_entity(self),
            )
        else:
            self.main.run_async(
                lambda: (client.service_start(service_name), "서비스 시작 완료"),
                self.main.reload_entity(self),
            )


class ScrubPage(QWidget):
    def __init__(self, main: "MainWindow"):
        super().__init__()
        self.main = main
        self.table = QTableWidget()
        self.table.setColumnCount(4)
        self.table.setHorizontalHeaderLabels(["풀", "주기", "상태", "설명"])
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.table.setEditTriggers(QTableWidget.NoEditTriggers)
        run_btn = QPushButton("지금 스크럽 실행")
        run_btn.clicked.connect(self.on_run)
        refresh_btn = QPushButton("새로고침")
        refresh_btn.clicked.connect(self.refresh)
        btns = QHBoxLayout()
        btns.addStretch(1)
        btns.addWidget(run_btn)
        btns.addWidget(refresh_btn)
        outer = QVBoxLayout()
        outer.addWidget(self.table, stretch=2)
        outer.addLayout(btns)
        self.setLayout(outer)
        self.refresh()

    def refresh(self):
        client = self.main.client()
        if client is None:
            self.main.show_message("먼저 연결을 저장하세요.")
            return
        self.main.run_async(client.scrub_tasks, self.on_loaded)

    def on_loaded(self, scrubs):
        scrubs = scrubs or []
        self.table.setRowCount(len(scrubs))
        for row, scrub in enumerate(scrubs):
            pool = scrub.get("pool") or {}
            state = ""
            if isinstance(scrub.get("scan"), dict):
                state = scrub["scan"].get("state") or ""
            cells = [pool.get("name"), str(scrub.get("interval") or "-"), state,
                     scrub.get("description") or ""]
            for col, val in enumerate(cells):
                self.table.setItem(row, col, QTableWidgetItem("" if val is None else str(val)))
            self.table.item(row, 0).setData(Qt.UserRole, scrub.get("id"))
        if not scrubs:
            self.main.show_message("스크럽 작업이 없습니다.")

    def on_run(self):
        row = self.table.currentRow()
        if row < 0:
            self.main.show_message("스크럽을 실행할 작업을 선택하세요.")
            return
        scrub_id = self.table.item(row, 0).data(Qt.UserRole)
        client = self.main.client()
        self.main.run_async(
            lambda: (client.scrub_run(scrub_id), "스크럽을 백그라운드로 실행했습니다."),
            self.main.reload_entity(self),
        )


# ------------------------- 기존 전용 화면 (풀 / 스냅샷)

class PoolsPage(QWidget):
    def __init__(self, main: "MainWindow"):
        super().__init__()
        self.main = main
        self.list = QListWidget()
        refresh_btn = QPushButton("풀 새로고침")
        refresh_btn.clicked.connect(self.refresh)
        outer = QVBoxLayout()
        outer.addWidget(refresh_btn)
        outer.addWidget(self.list)
        self.setLayout(outer)
        self.refresh()

    def refresh(self):
        client = self.main.client()
        if client is None:
            self.main.show_message("먼저 연결을 저장하세요.")
            return
        self.main.run_async(client.pools, self.on_loaded)

    def on_loaded(self, pools):
        self.list.clear()
        for pool in pools or []:
            name = pool.get("name") or "-"
            status = pool.get("status") or "-"
            used = fmt_bytes(pool.get("allocated"))
            size = fmt_bytes(pool.get("size"))
            frag = pool.get("fragmentation")
            frag_txt = f", 단편화 {frag:0.0f}%" if isinstance(frag, (int, float)) else ""
            item = QListWidgetItem(f"● {name}  [{status}]  {used} / {size}{frag_txt}")
            item.setForeground(status_color(status))
            self.list.addItem(item)
            topo = pool.get("topology") or {}
            for disk in (topo.get("data") or []):
                self.list.addItem(f"   └ 디스크 {disk.get('name', '-')}")
        if not pools:
            self.list.addItem("풀 데이터가 없습니다.")


class SnapshotsPage(QWidget):
    def __init__(self, main: "MainWindow"):
        super().__init__()
        self.main = main
        self.datasets: list = []

        self.repl_list = QListWidget()
        self.snap_table = self._snap_table()

        add_btn = QPushButton("스냅샷 생성")
        add_btn.clicked.connect(self.on_add)
        del_btn = QPushButton("선택 스냅샷 삭제")
        del_btn.clicked.connect(self.on_delete)
        rb_btn = QPushButton("선택 스냅샷롤백")
        rb_btn.clicked.connect(self.on_rollback)
        cl_btn = QPushButton("선택 스냅샷 클론")
        cl_btn.clicked.connect(self.on_clone)
        refresh_btn = QPushButton("새로고침")
        refresh_btn.clicked.connect(self.refresh)

        outer = QVBoxLayout()
        outer.addWidget(QLabel("복제 작업"))
        outer.addWidget(self.repl_list, stretch=1)
        outer.addWidget(QLabel("ZFS 스냅샷"))
        outer.addWidget(self.snap_table, stretch=2)
        btns = QHBoxLayout()
        btns.addStretch(1)
        btns.addWidget(add_btn)
        btns.addWidget(rb_btn)
        btns.addWidget(cl_btn)
        btns.addWidget(del_btn)
        btns.addWidget(refresh_btn)
        outer.addLayout(btns)
        self.setLayout(outer)
        self.refresh()

    def _snap_table(self) -> QTableWidget:
        table = QTableWidget()
        table.setColumnCount(3)
        table.setHorizontalHeaderLabels(["스냅샷 이름", "데이터셋", "생성 시각"])
        table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        table.setEditTriggers(QTableWidget.NoEditTriggers)
        return table

    def refresh(self):
        client = self.main.client()
        if client is None:
            self.main.show_message("먼저 연결을 저장하세요.")
            return

        def load():
            # 스냅샷 목록은 필수, 복제/데이터셋은 선택 데이터(한 곳이 404여도 목록 전체가 안 비도록)
            data = {"snaps": None, "repl": None, "ds": None}
            data["snaps"] = client.snapshots()
            try:
                data["repl"] = client.replications()
            except TruenasError as err:
                data["repl"] = None
                data["repl_err"] = str(err)
            try:
                data["ds"] = [d.get("name") for d in client.datasets()
                              if (d.get("type") or "FILESYSTEM") == "FILESYSTEM"]
            except TruenasError as err:
                data["ds"] = None
                data["ds_err"] = str(err)
            return data

        self.main.run_async(load, self.on_loaded)

    def on_loaded(self, data):
        self.repl_list.clear()
        for task in data.get("repl") or []:
            flag = "▶" if task.get("enabled", True) else "⏸"
            label = task.get("name") or f"Task #{task.get('id')}"
            self.repl_list.addItem(f"{flag} {label}  -> {task.get('target_dataset', '-')}")
        if data.get("repl_err"):
            self.repl_list.addItem(f"복제 목록 조회 실패 - {data['repl_err']}")
        elif not (data.get("repl") or []):
            self.repl_list.addItem("복제 작업이 없습니다.")

        snaps = sorted(data.get("snaps") or [], key=lambda s: s.get("name") or "")
        self.snap_table.setRowCount(len(snaps))
        for row, snap in enumerate(snaps):
            cells = [snap.get("name"), snap.get("dataset"), fmt_epoch(snap.get("taken_at"))]
            for col, val in enumerate(cells):
                self.snap_table.setItem(row, col, QTableWidgetItem("" if val is None else str(val)))
        self.datasets = [d for d in (data.get("ds") or []) if d]
        if data.get("ds_err"):
            self.main.show_message(f"데이터셋 목록 조회 실패 - {data['ds_err']}")

    def on_add(self):
        dlg = CreateSnapshotDialog(self, self.datasets)
        if dlg.exec() != QDialog.Accepted:
            return
        dataset, name, recursive = dlg.values()
        if not name:
            self.main.show_message("스냅샷 이름을 입력하세요.")
            return
        client = self.main.client()
        self.main.run_async(
            lambda: (client.create_snapshot(dataset, name, recursive),
                     f"스냅샷 {dataset}@{name} 생성 완료"),
            self.main.reload_entity(self),
        )

    def on_delete(self):
        row = self.snap_table.currentRow()
        if row < 0:
            self.main.show_message("삭제할 스냅샷을 테이블에서 선택하세요.")
            return
        full_name = self.snap_table.item(row, 0).text()
        if QMessageBox.question(self, "삭제",
                                f"스냅샷 '{full_name}'을(를) 삭제할까요?\n되돌릴 수 없습니다.") != QMessageBox.Yes:
            return
        client = self.main.client()
        self.main.run_async(
            lambda: (client.delete_snapshot(full_name), f"스냅샷 {full_name} 삭제 완료"),
            self.main.reload_entity(self),
        )

    def on_rollback(self):
        row = self.snap_table.currentRow()
        if row < 0:
            self.main.show_message("롤백할 스냅샷을 테이블에서 선택하세요.")
            return
        full_name = self.snap_table.item(row, 0).text()
        ans = QMessageBox.question(
            self, "스냅샷 롤백",
            f"데이터셋을 스냅샷 '{full_name}' 시점으로 되돌릴까요?\n"
            "이후 변경사항/스냅샷은 삭제되며 되돌릴 수 없습니다.")
        if ans != QMessageBox.Yes:
            return
        client = self.main.client()
        self.main.run_async(
            lambda: (client.rollback_snapshot(full_name), f"스냅샷 {full_name} 롤백 완료"),
            self.main.reload_entity(self),
        )

    def on_clone(self):
        row = self.snap_table.currentRow()
        if row < 0:
            self.main.show_message("클론할 스냅샷을 테이블에서 선택하세요.")
            return
        full_name = self.snap_table.item(row, 0).text()
        src_ds = full_name.split("@")[0]
        dst, ok = QInputDialog.getText(self, "스냅샷 클론",
                                       f"{full_name} 을 새 데이터셋으로 클론합니다.\n새 데이터셋 이름:",
                                       text=f"{src_ds}_clone")
        if not ok or not dst.strip():
            return
        client = self.main.client()
        self.main.run_async(
            lambda: (client.clone_snapshot(full_name, dst.strip()), f"클론 {dst.strip()} 생성 완료"),
            self.main.reload_entity(self),
        )


class CreateSnapshotDialog(QDialog):
    def __init__(self, parent: QWidget, datasets):
        super().__init__(parent)
        self.setWindowTitle("스냅샷 생성")
        self.dataset_combo = QComboBox()
        self.dataset_combo.addItems(datasets or ["(데이터셋을 불러오려면 새로고침)"])
        self.name_edit = QLineEdit()
        self.recursive_check = QCheckBox("하위 데이터셋 모두 재귀 생성")
        form = QFormLayout(self)
        form.addRow("데이터셋", self.dataset_combo)
        form.addRow("스냅샷 이름", self.name_edit)
        form.addRow("", self.recursive_check)
        bb = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        bb.accepted.connect(self.accept)
        bb.rejected.connect(self.reject)
        form.addRow(bb)

    def values(self):
        return (self.dataset_combo.currentText(),
                self.name_edit.text().strip(),
                self.recursive_check.isChecked())


# ------------------------- 보조 대화상자

class AddUserDialog(QDialog):
    def __init__(self, parent: QWidget):
        super().__init__(parent)
        self.setWindowTitle("사용자 추가")
        self.username_edit = QLineEdit()
        self.full_edit = QLineEdit()
        self.password_edit = password_line()
        self.confirm_edit = password_line()
        self.smb_check = QCheckBox("SMB 접근 허용")
        self.smb_check.setChecked(True)
        form = QFormLayout(self)
        form.addRow("사용자 이름", self.username_edit)
        form.addRow("표시 이름", self.full_edit)
        form.addRow("비밀번호 (8자 이상)", self.password_edit)
        form.addRow("비밀번호 확인", self.confirm_edit)
        form.addRow("", self.smb_check)
        bb = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        bb.accepted.connect(self.accept)
        bb.rejected.connect(self.reject)
        form.addRow(bb)

    def values(self):
        return (self.username_edit.text().strip(),
                self.full_edit.text().strip(),
                self.password_edit.text(),
                self.smb_check.isChecked())


# ------------------------- 앱 / 가상머신 화면

class AppsPage(QWidget):
    """앱(Applications) 목록과 시작/정지/재배포/삭제"""

    ACTIONS = [("start", "시작"), ("stop", "정지"), ("redeploy", "재배포"), ("upgrade", "업그레이드")]

    def __init__(self, main: "MainWindow"):
        super().__init__()
        self.main = main
        self.table = QTableWidget()
        self.table.setColumnCount(4)
        self.table.setHorizontalHeaderLabels(["앱 이름", "버전", "상태", "호출레스"])
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.table.setEditTriggers(QTableWidget.NoEditTriggers)
        self.table.cellClicked.connect(self._on_select)

        btns = QHBoxLayout()
        for action, label in self.ACTIONS:
            btn = QPushButton(label)
            btn.clicked.connect(lambda _=False, a=action: self.on_action(a))
            btns.addWidget(btn)
        del_btn = QPushButton("삭제")
        del_btn.clicked.connect(self.on_delete)
        btns.addWidget(del_btn)
        btns.addStretch(1)
        refresh_btn = QPushButton("새로고침")
        refresh_btn.clicked.connect(self.refresh)
        btns.addWidget(refresh_btn)

        note = QLabel("설치(신규 앱 배포)는 TrueNAS 웹 UI의 '앱' 화면에서 설정 스키마를 따라 수행하는 것이 안전합니다. 이 화면은 설치된 앱의 관리(시작/정지/재배포/업그레이드/삭제)를 담당합니다.")
        note.setWordWrap(True)

        outer = QVBoxLayout()
        outer.addWidget(note)
        outer.addWidget(self.table, stretch=1)
        outer.addLayout(btns)
        self.setLayout(outer)
        self.refresh()

    def refresh(self):
        client = self.main.client()
        if client is None:
            self.main.show_message("먼저 연결을 저장하세요.")
            return
        self.main.run_async(client.apps, self.on_loaded)

    def on_loaded(self, apps):
        apps = apps or []
        self.table.setRowCount(len(apps))
        for row, app in enumerate(apps):
            state = app.get("state") or "-"
            version = str(app.get("version") or "-")
            if app.get("upgrade_available"):
                version = f"{version} → {app.get('latest_version') or '?'}"
            containers = app.get("containers") or []
            hosts = ", ".join(str(c.get("hostname") or "-") for c in containers) or "-"
            cells = [app.get("name"), version, state, hosts]
            for col, val in enumerate(cells):
                item = QTableWidgetItem("" if val is None else str(val))
                if col == 2:
                    item.setForeground(QColor("green") if "RUNNING" in str(state).upper()
                                       else QColor("gray"))
                self.table.setItem(row, col, item)
            self.table.item(row, 0).setData(Qt.UserRole, app.get("name"))
        if not apps:
            self.main.show_message("설치된 앱이 없습니다. (Docker 풀이 설정되지 않은 경우 TrueNAS 웹 UI의 '앱' 화면에서 풀을 지정하세요)")

    def _selected_name(self):
        row = self.table.currentRow()
        if row < 0:
            return None
        return self.table.item(row, 0).data(Qt.UserRole)

    def _on_select(self, *_):
        pass

    def on_action(self, action: str):
        name = self._selected_name()
        if not name:
            self.main.show_message("작업할 앱을 표에서 선택하세요.")
            return
        label = dict(self.ACTIONS).get(action, action)
        client = self.main.client()
        self.main.run_async(
            lambda: (client.app_action(name, action), f"앱 {name} {label} 완료"),
            self.main.reload_entity(self),
        )

    def on_delete(self):
        name = self._selected_name()
        if not name:
            self.main.show_message("삭제할 앱을 표에서 선택하세요.")
            return
        if QMessageBox.question(self, "앱 삭제",
                                f"앱 '{name}'과 그 데이터셋을 삭제할까요?\n되돌릴 수 없습니다.") != QMessageBox.Yes:
            return
        client = self.main.client()
        self.main.run_async(
            lambda: (client.app_delete(name), f"앱 {name} 삭제 완료"),
            self.main.reload_entity(self),
        )


class CreateVMDialog(QDialog):
    def __init__(self, parent: QWidget, pools, include_iscsi: bool = False):
        super().__init__(parent)
        self.setWindowTitle("VM 생성")
        self.name_edit = QLineEdit()
        self.vcpu_edit = QLineEdit("1")
        self.mem_edit = QLineEdit("4")
        self.disk_edit = QLineEdit("20")
        self.iso_edit = QLineEdit()
        self.iso_edit.setPlaceholderText("공란 가능 (/mnt/... ISO 경로)")
        self.nic_edit = QLineEdit()
        self.nic_edit.setPlaceholderText("공란 가능 (예: br0 또는 인터페이스)")
        self.pool_combo = QComboBox()
        self.pool_combo.addItems([p.get("name") for p in pools if p.get("name")] or ["저장된 연결 후 새로고침"])
        self.autostart_check = QCheckBox("부팅 시 자동 시작")
        self.autostart_check.setChecked(True)
        form = QFormLayout(self)
        form.addRow("VM 이름", self.name_edit)
        form.addRow("vCPU 수", self.vcpu_edit)
        form.addRow("메모리 (GB)", self.mem_edit)
        form.addRow("디스크 크기 (GB, ZVOL 신규 생성)", self.disk_edit)
        form.addRow("디스크 생성 풀", self.pool_combo)
        form.addRow("ISO 경로 (CD-ROM)", self.iso_edit)
        form.addRow("NIC 연결(브리지/인터페이스)", self.nic_edit)
        form.addRow("", self.autostart_check)
        bb = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        bb.accepted.connect(self.accept)
        bb.rejected.connect(self.reject)
        form.addRow(bb)

    def values(self) -> dict:
        try:
            vcpu = max(1, int(self.vcpu_edit.text() or 1))
        except ValueError:
            vcpu = 1
        try:
            mem_gib = max(1, int(self.mem_edit.text() or 4))
        except ValueError:
            mem_gib = 4
        try:
            disk_gib = max(1, int(self.disk_edit.text() or 20))
        except ValueError:
            disk_gib = 20
        return {
            "name": self.name_edit.text().strip(),
            "vcpus": vcpu,
            "mem_gib": mem_gib,
            "disk_gib": disk_gib,
            "pool": self.pool_combo.currentText(),
            "iso": self.iso_edit.text().strip(),
            "nic": self.nic_edit.text().strip(),
            "autostart": self.autostart_check.isChecked(),
        }


class VMPage(QWidget):
    """가상머신 목록/생성/시작/정지/재시작/전원 끄기/삭제"""

    ACTIONS = [("start", "시작"), ("stop", "정지"), ("restart", "재시작"), ("poweroff", "전원 끄기")]

    def __init__(self, main: "MainWindow"):
        super().__init__()
        self.main = main
        self.table = QTableWidget()
        self.table.setColumnCount(6)
        self.table.setHorizontalHeaderLabels(["ID", "이름", "상태", "vCPU", "메모리", "자동시작"])
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.table.setEditTriggers(QTableWidget.NoEditTriggers)
        self.table.setSelectionBehavior(QTableWidget.SelectRows)

        btns = QHBoxLayout()
        for action, label in self.ACTIONS:
            btn = QPushButton(label)
            btn.clicked.connect(lambda _=False, a=action: self.on_action(a))
            btns.addWidget(btn)
        del_btn = QPushButton("삭제")
        del_btn.clicked.connect(self.on_delete)
        btns.addWidget(del_btn)
        add_btn = QPushButton("VM 생성")
        add_btn.clicked.connect(self.on_create)
        btns.addWidget(add_btn)
        btns.addStretch(1)
        refresh_btn = QPushButton("새로고침")
        refresh_btn.clicked.connect(self.refresh)
        btns.addWidget(refresh_btn)

        outer = QVBoxLayout()
        outer.addWidget(self.table, stretch=1)
        outer.addLayout(btns)
        self.setLayout(outer)
        self.refresh()

    def refresh(self):
        client = self.main.client()
        if client is None:
            self.main.show_message("먼저 연결을 저장하세요.")
            return
        self.main.run_async(client.vms, self.on_loaded)

    def on_loaded(self, vms):
        vms = vms or []
        self.table.setRowCount(len(vms))
        for row, vm in enumerate(vms):
            status = vm.get("status") or {}
            state = status.get("state") or vm.get("state") or "-"
            mem = vm.get("memory")
            cells = [vm.get("id"), vm.get("name"), state, vm.get("vcpus"),
                     fmt_bytes((mem or 0) * 1024 * 1024) if mem else "-",
                     "예" if vm.get("autostart") else "아니오"]
            for col, val in enumerate(cells):
                item = QTableWidgetItem("" if val is None else str(val))
                if col == 2:
                    item.setForeground(QColor("green") if str(state).upper() == "RUNNING"
                                       else QColor("gray"))
                self.table.setItem(row, col, item)
            self.table.item(row, 0).setData(Qt.UserRole, vm.get("id"))
        if not vms:
            self.main.show_message("가상머신이 없습니다. 'VM 생성'으로 만들 수 있습니다.")

    def _selected_id(self):
        row = self.table.currentRow()
        if row < 0:
            return None
        vm_id = self.table.item(row, 0).data(Qt.UserRole)
        return vm_id if vm_id is not None else None

    def on_action(self, action: str):
        vm_id = self._selected_id()
        if vm_id is None:
            self.main.show_message("작업할 VM을 표에서 선택하세요.")
            return
        label = dict(self.ACTIONS).get(action, action)
        client = self.main.client()
        self.main.run_async(
            lambda: (client.vm_action(vm_id, action), f"VM #{vm_id} {label} 완료"),
            self.main.reload_entity(self),
        )

    def on_delete(self):
        vm_id = self._selected_id()
        if vm_id is None:
            self.main.show_message("삭제할 VM을 표에서 선택하세요.")
            return
        if QMessageBox.question(self, "VM 삭제",
                                f"VM #{vm_id}을(를) 삭제할까요?\n디스크는 삭제되지 않습니다.") != QMessageBox.Yes:
            return
        client = self.main.client()
        self.main.run_async(
            lambda: (client.vm_delete(vm_id), f"VM #{vm_id} 삭제 완료"),
            self.main.reload_entity(self),
        )

    def on_create(self):
        client = self.main.client()
        if client is None:
            self.main.show_message("먼저 연결을 저장하세요.")
            return
        dlg = CreateVMDialog(self, client.pools())
        if dlg.exec() != QDialog.Accepted:
            return
        values = dlg.values()
        if not values["name"]:
            self.main.show_message("VM 이름을 입력하세요.")
            return

        def build_body():
            devices = []
            devices.append({
                "dtype": "DISK",
                "attributes": {
                    "type": "AHCI",
                    "create_zvol": True,
                    "zvol_name": f"{values['pool']}/{values['name']}-disk",
                    "zvol_volsize": values["disk_gib"] * 1024 ** 3,
                },
            })
            if values["iso"]:
                devices.append({"dtype": "CDROM", "attributes": {"path": values["iso"]}})
            nic = {"dtype": "NIC", "attributes": {"type": "VIRTIO"}}
            if values["nic"]:
                nic["attributes"]["nic_attach"] = values["nic"]
            devices.append(nic)
            body = {
                "name": values["name"],
                "vcpus": values["vcpus"],
                "cores": values["vcpus"],
                "threads": 1,
                "memory": values["mem_gib"] * 1024,
                "autostart": values["autostart"],
                "devices": devices,
            }
            client.create_vm(body)
            return f"VM {values['name']} 생성 완료"

        self.main.run_async(build_body, self.main.reload_entity(self))


# ------------------------- 앱 업데이트 화면
class UpdatesPage(QWidget):
    """앱 내 업데이트 확인: releases/VERSION 과 현재 빌드 버전을 비교해
    새 버전이 있으면 다운로드 페이지를 열어준다."""

    def __init__(self, main: "MainWindow"):
        super().__init__()
        self.main = main

        self.info_lbl = QLabel()
        self.info_lbl.setWordWrap(True)
        self.status_lbl = QLabel("")
        self.status_lbl.setWordWrap(True)

        self.check_btn = QPushButton(t("업데이트 확인", "Check for updates"))
        self.check_btn.clicked.connect(self.on_check)
        self.open_btn = QPushButton(t("다운로드 페이지 열기", "Open download page"))
        self.open_btn.clicked.connect(self.open_download)
        self.open_btn.setEnabled(False)

        btns = QHBoxLayout()
        btns.addWidget(self.check_btn)
        btns.addWidget(self.open_btn)
        btns.addStretch(1)

        note = QLabel(t(
            "새 버전이 확인되면 NaDeck.exe(Windows) 또는 NaDeck-macOS.dmg(macOS)를\n"
            "다운로드해 실행/설치하면 됩니다. 기존 설정은 자동으로 유지됩니다.",
            "When a new version is found, download NaDeck.exe (Windows) or\n"
            "NaDeck-macOS.dmg (macOS) and run/ install it. Settings are kept."))
        note.setWordWrap(True)

        outer = QVBoxLayout()
        outer.addWidget(self.info_lbl)
        outer.addWidget(self.status_lbl)
        outer.addLayout(btns)
        outer.addWidget(note)
        outer.addStretch(1)
        self.setLayout(outer)
        self.refresh_label()

    def refresh_label(self):
        self.info_lbl.setText(t(f"현재 버전: {APP_VERSION}", f"Current version: {APP_VERSION}"))

    def on_check(self):
        import requests
        self.main.show_message(t("업데이트 확인 중...", "Checking for updates..."), sticky=True)

        def fetch():
            resp = requests.get(UPDATE_BASE + "/VERSION", timeout=10)
            resp.raise_for_status()
            text = resp.text.strip()
            if not text or len(text) > 32 or not all(c.isdigit() or c == "." for c in text):
                raise ValueError(t("버전 형식이 올바르지 않습니다", "Invalid version format"))
            return text

        self.main.run_async(fetch, self.on_latest)

    def on_latest(self, latest: str):
        self.refresh_label()
        if _is_newer(latest, APP_VERSION):
            self.status_lbl.setText(t(
                f"새 버전 {latest} 이 있습니다. 다운로드 페이지에서 NaDeck.exe를 받아 실행하세요.",
                f"New version {latest} available. Get NaDeck.exe from the download page."))
            self.status_lbl.setStyleSheet("color: orange;")
            self.open_btn.setEnabled(True)
        else:
            self.status_lbl.setText(t("최신 버전을 사용하고 있습니다.", "You are up to date."))
            self.status_lbl.setStyleSheet("")
            self.open_btn.setEnabled(False)
        self.main.show_message(t("업데이트 확인 완료", "Update check done"))

    def open_download(self):
        from PySide6.QtGui import QDesktopServices
        from PySide6.QtCore import QUrl
        QDesktopServices.openUrl(QUrl(DOWNLOAD_PAGE))


def _is_newer(latest: str, current: str) -> bool:
    def parts(s: str):
        return [int(x) if x.strip().isdigit() else 0 for x in s.split(".")]
    a, b = parts(latest), parts(current)
    for i in range(max(len(a), len(b))):
        x = a[i] if i < len(a) else 0
        y = b[i] if i < len(b) else 0
        if x != y:
            return x > y
    return False


# ------------------------- 기능 카탈로그


class Catalog:
    @staticmethod
    def _entity_spec(title, endpoint, columns, **kw):
        return EntitySpec(title=title, endpoint=endpoint, columns=columns, **kw)

    @staticmethod
    def groups(main: "MainWindow") -> list:
        """[(카테고리, [(표시이름, 위젯 팩토리)])] 형태의 전체 기능 카탈로그"""
        smb = EntitySpec(
            title="SMB 공유", endpoint="/sharing/smb",
            columns=[("name", "이름", "raw"), ("path", "경로", "raw"),
                     ("purpose", "유형", "raw"), ("comment", "설명", "raw"),
                     ("enabled", "활성", "bool")],
            id_field="id",
            create_fields=[{"key": "name", "label": "공유 이름", "kind": "text"},
                           {"key": "path", "label": "데이터셋 경로 (/mnt/...)", "kind": "choice_datasets"},
                           {"key": "comment", "label": "설명", "kind": "text"}],
            edit_fields=[{"key": "comment", "label": "설명", "kind": "text"},
                         {"key": "enabled", "label": "활성", "kind": "bool"},
                         {"key": "readonly", "label": "읽기 전용", "kind": "bool"},
                         {"key": "browsable", "label": "탐색 가능", "kind": "bool"}],
        )
        nfs = EntitySpec(
            title="NFS 공유", endpoint="/sharing/nfs",
            columns=[("id", "ID", "raw"), ("path", "경로", "raw"),
                     ("networks", "네트워크", "list"), ("hosts", "호스트", "list"),
                     ("ro", "읽기전용", "bool")],
            id_field="id",
            edit_fields=[{"key": "comment", "label": "설명", "kind": "text"},
                         {"key": "hosts", "label": "호스트(콤마 구분)", "kind": "list"},
                         {"key": "networks", "label": "네트워크(콤마 구분)", "kind": "list"},
                         {"key": "ro", "label": "읽기 전용", "kind": "bool"}],
        )
        iscsi = EntitySpec(
            title="iSCSI 대상", endpoint="/iscsi/target",
            columns=[("target_name", "대상 이름", "raw"), ("alias", "별명", "raw")],
            id_field="id", read_only=True,
        )
        dataset = EntitySpec(
            title="데이터셋", endpoint="/pool/dataset",
            columns=[("name", "이름", "raw"), ("pool", "풀", "raw"),
                     ("type", "유형", "raw"), ("comments", "설명", "raw"),
                     ("used", "사용량", "bytes")],
            id_field="name",
            create_fields=[{"key": "dataset_path", "label": "상위 데이터셋", "kind": "choice_datasets"},
                           {"key": "name", "label": "이름", "kind": "text"},
                           {"key": "comments", "label": "설명", "kind": "text"}],
            create_defaults={"type": "FILESYSTEM"},
        )
        disk = EntitySpec(
            title="디스크", endpoint="/disk",
            columns=[("name", "장치", "raw"), ("model", "모델", "raw"),
                     ("serial", "시리얼", "raw"), ("size", "용량", "bytes"),
                     ("temperature", "온도(℃)", "celsius"),
                     ("rotationrate", "RPM", "raw")],
            read_only=True,
        )
        replication = EntitySpec(
            title="복제 작업", endpoint="/replication",
            columns=[("name", "이름", "raw"), ("direction", "방향", "raw"),
                     ("target_dataset", "대상", "raw"), ("enabled", "활성", "bool")],
            read_only=True,
        )
        users = EntitySpec(
            title="사용자", endpoint="/user",
            columns=[("username", "사용자", "raw"), ("uid", "UID", "raw"),
                     ("full_name", "표시 이름", "raw"), ("shell", "셸", "raw"),
                     ("smb", "SMB", "bool")],
            id_field="id",
            create_fields=[{"key": "username", "label": "사용자 이름", "kind": "text"},
                           {"key": "full_name", "label": "표시 이름", "kind": "text"},
                           {"key": "password", "label": "비밀번호 (8자 이상)", "kind": "password"},
                           {"key": "smb", "label": "SMB 접근 허용", "kind": "bool"}],
            create_defaults={"group_create": True},
            edit_fields=[{"key": "full_name", "label": "표시 이름", "kind": "text"},
                         {"key": "shell", "label": "셸(/usr/bin/nologin 등)", "kind": "text"},
                         {"key": "locked", "label": "잠금", "kind": "bool"},
                         {"key": "smb", "label": "SMB 접근 허용", "kind": "bool"}],
        )
        groups_spec = EntitySpec(
            title="그룹", endpoint="/group",
            columns=[("group", "그룹", "raw"), ("gid", "GID", "raw"),
                     ("builtin", "시스템", "bool"), ("smb", "SMB", "bool")],
            id_field="id",
        )
        cron = EntitySpec(
            title="Cron 작업", endpoint="/cronjob",
            columns=[("title", "제목", "raw"), ("command", "명령", "raw"),
                     ("schedule", "주기", "list"), ("enabled", "활성", "bool")],
            id_field="id",
            create_fields=[{"key": "title", "label": "제목", "kind": "text"},
                           {"key": "command", "label": "명령", "kind": "text"},
                           {"key": "schedule", "label": "주기(cron식: cron:<expr>)", "kind": "text"}],
        )
        rsync = EntitySpec(
            title="Rsync 작업", endpoint="/rsynctask",
            columns=[("desc", "설명", "raw"), ("direction", "방향", "raw"),
                     ("remotehost", "호스트", "raw"), ("enabled", "활성", "bool")],
            read_only=True,
        )
        cloudsync = EntitySpec(
            title="Cloud Sync", endpoint="/cloudsync",
            columns=[("description", "설명", "raw"), ("direction", "방향", "raw"),
                     ("credentials", "자격증명", "raw"), ("enabled", "활성", "bool")],
            read_only=True,
        )
        iface = EntitySpec(
            title="인터페이스", endpoint="/interface",
            columns=[("name", "이름", "raw"), ("state", "상태", "raw"),
                     ("type", "유형", "raw"), ("mtu", "MTU", "raw")],
            read_only=True,
        )
        cert = EntitySpec(
            title="인증서", endpoint="/certificate",
            columns=[("name", "이름", "raw"), ("issued", "발급일", "time"),
                     ("expires_at", "만료일", "raw"), ("self_signed", "자가서명", "bool")],
            read_only=True,
        )

        return [
            ("NAS 현황", [
                ("전체 보기", lambda: NasOverviewPage(main)),
            ]),
            ("시스템", [
                ("대시보드", lambda: DashboardPage(main)),
                ("알림", lambda: AlertPage(main)),
                ("서비스", lambda: ServicePage(main)),
                ("부팅 환경", lambda: ListPage(
                    main,
                    lambda: main.client().boot_environments(),
                    columns=[("id", "환경", "raw"), ("dataset", "데이터셋", "raw"),
                             ("activated", "부팅 활성", "bool"), ("created", "생성일", "time"),
                             ("used", "용량", "raw"), ("keep", "유지", "bool")],
                    actions=[("활성화",
                              lambda c, r: c.activate_boot_environment(r.get("id")),
                              "다음 부팅에 이 환경을 사용할까요?\n(현재 실행 중 시스템에는 영향 없음)"),
                             ("유지 전환",
                              lambda c, r: c.toggle_keep_boot_environment(
                                  r.get("id"), not bool(r.get("keep"))),
                              None),
                             ("삭제",
                              lambda c, r: c.destroy_boot_environment(r.get("id")),
                              "부팅 환경을 삭제할까요?\n되돌릴 수 없습니다.")])),
                ("시스템 업데이트", lambda: UpdateSystemPage(main)),
                ("감사 로그", lambda: ListPage(
                    main,
                    lambda: main.client().audit_log(limit=100),
                    columns=[("timestamp", "시각", "time"), ("username", "사용자", "raw"),
                             ("address", "주소", "raw"), ("event", "이벤트", "raw"),
                             ("service", "서비스", "raw"), ("success", "성공", "bool")])),
            ]),
            ("스토리지", [
                ("스토리지 풀", lambda: PoolsPage(main)),
                ("데이터셋", lambda: EntityPage(main, dataset)),
                ("디스크", lambda: EntityPage(main, disk)),
                ("스냅샷 / 복제", lambda: SnapshotsPage(main)),
                ("복제 작업", lambda: EntityPage(main, replication)),
                ("스크럽 작업", lambda: ScrubPage(main)),
            ]),
            ("공유", [
                ("SMB", lambda: EntityPage(main, smb)),
                ("NFS", lambda: EntityPage(main, nfs)),
                ("iSCSI", lambda: EntityPage(main, iscsi)),
            ]),
            ("네트워크", [
                ("인터페이스", lambda: EntityPage(main, iface)),
                ("네트워크 요약", lambda: TextPage(
                    main,
                    lambda: _network_report(main.client()))),
                ("정적 라우트", lambda: _static_route_page(main)),
            ]),
            ("앱/가상머신", [
                ("앱 관리", lambda: AppsPage(main)),
                ("앱 카탈로그", lambda: AppCatalogPage(main)),
                ("가상머신", lambda: VMPage(main)),
            ]),
            ("계정", [
                ("사용자", lambda: EntityPage(main, users)),
                ("그룹", lambda: EntityPage(main, groups_spec)),
                ("API 키", lambda: ApiKeyPage(main)),
            ]),
            ("작업", [
                ("Cron 작업", lambda: EntityPage(main, cron)),
                ("Rsync", lambda: EntityPage(main, rsync)),
                ("Cloud Sync", lambda: EntityPage(main, cloudsync)),
            ]),
            ("보안", [
                ("인증서", lambda: EntityPage(main, cert)),
            ]),
            ("설정", [
                ("연결 설정", lambda: ConnectionPage(main)),
                ("앱 업데이트", lambda: UpdatesPage(main)),
            ]),
        ]


# ------------------------- 메인 윈도우 (카테고리 사이드바)

from PySide6.QtWidgets import (  # noqa: E402
    QTreeWidget, QTreeWidgetItem, QStackedWidget,
)


class MainWindow(QWidget):
    def __init__(self):
        super().__init__()
        self.config = Config()
        self.pool = QThreadPool.globalInstance()

        self.setWindowTitle("NaDeck — TrueNAS 관리")
        self.resize(1080, 700)

        self.info_label = QLabel("준비됨")
        self.info_label.setWordWrap(True)
        # show_message()의 2초 자동 지우기 타이머
        self._msg_timer: Optional[QTimer] = None

        # 여러 TrueNAS를 다중 관리: 좌측 상단에서 관리할 NAS를 선택해 전환한다.
        # 전환하면 모든 화면(페이지)을 새 NAS 기준으로 다시 만든다.
        active_name, active_item = self.config.active_profile()
        self.nas_combo = QComboBox()
        self.nas_combo.setEditable(False)
        self.nas_combo.currentTextChanged.connect(self.switch_profile)
        nas_row = QHBoxLayout()
        nas_row.addWidget(QLabel(t("NAS 선택", "NAS")))
        nas_row.addWidget(self.nas_combo, stretch=1)

        left = QVBoxLayout()
        left.addLayout(nas_row)
        self.tree = QTreeWidget()
        self.tree.setHeaderHidden(True)
        left.addWidget(self.tree, 1)
        left_widget = QWidget()
        left_widget.setLayout(left)

        self.stack = QStackedWidget()
        self.pages = []
        self._build_pages()

        self.tree.itemClicked.connect(self._on_tree_click)

        body = QHBoxLayout()
        body.addWidget(left_widget, 0)
        # 사이드바 폭을 콘텐츠(인터페이스 화면 등)가 좌우하지 않게 고정 (밀림 방지)
        self.tree.setFixedWidth(230)
        body.addWidget(self.stack, stretch=1)

        self._repopulate(selected=active_name)

        outer = QVBoxLayout()
        outer.addWidget(self.info_label)
        outer.addLayout(body, stretch=1)
        self.setLayout(outer)

    def _build_pages(self):
        """카탈로그 사양으로 트리+페이지(스택)를 새로 만든다.
        NAS 전환 시 호출되어 활성 NAS 기준으로 화면 전체가 다시 로딩된다."""
        self.tree.clear()
        self.pages = []
        while self.stack.count():
            widget = self.stack.widget(0)
            self.stack.removeWidget(widget)
            widget.deleteLater()

        groups = Catalog.groups(self)
        for gi, (cat_name, items) in enumerate(groups):
            top = QTreeWidgetItem([cat_name])
            top.setData(0, Qt.UserRole, ("category", gi))
            self.tree.addTopLevelItem(top)
            for item_name, factory in items:
                child = QTreeWidgetItem(["    " + item_name])
                page = factory()
                self.pages.append(page)
                child.setData(0, Qt.UserRole, ("page", self.stack.count(), None))
                top.addChild(child)
                self.stack.addWidget(page)
        self.conn_page = next((p for p in self.pages if isinstance(p, ConnectionPage)), None)
        self.update_page = next((p for p in self.pages if isinstance(p, UpdatesPage)), None)
        self.tree.expandAll()

    def _repopulate(self, selected=None):
        """저장된 프로파일 목록으로 NAS 선택 콤보를 다시 채운다."""
        if selected is None:
            selected, _ = self.config.active_profile()
        self.nas_combo.blockSignals(True)
        self.nas_combo.clear()
        for item_name, _ in self.config.profiles().get("list", []):
            self.nas_combo.addItem(item_name)
        if selected:
            index = self.nas_combo.findText(selected)
            if index >= 0:
                self.nas_combo.setCurrentIndex(index)
        self.nas_combo.blockSignals(False)

    def refresh_nas_list(self):
        """ConnectionPage가 프로파일을 추가/삭제한 뒤 콤보를 갱신한다."""
        self._repopulate()

    def show_connection_page(self):
        """NAS 현황/설정 진입: 연결 설정 화면(트리의 설정 -> 연결 설정)으로 이동."""
        try:
            for i in range(self.tree.topLevelItemCount()):
                top = self.tree.topLevelItem(i)
                if top.data(0, Qt.UserRole) and top.data(0, Qt.UserRole)[0] == "category":
                    for j in range(top.childCount()):
                        child = top.child(j)
                        data = child.data(0, Qt.UserRole)
                        page_index = data[1] if data and data[0] == "page" else None
                        if page_index is not None and self.stack.widget(page_index) is self.conn_page:
                            self.stack.setCurrentIndex(page_index)
                            return
        except Exception:
            pass

    def switch_profile(self, name: str):
        """콤보에서 NAS를 선택하면 활성 프로파일을 바꾸고
        모든 화면을 새 NAS 기준으로 다시 만든다."""
        if not name:
            return
        current, _item = self.config.active_profile()
        if current == name:
            return
        data = self.config.profiles()
        data["active"] = name
        self.config.save_profiles(data)
        self._build_pages()
        self.show_message(t(f"{name} 연결로 전환했습니다.", f"Switched to {name}."))

    def _on_tree_click(self, item, _column):
        kind, value, *_ = item.data(0, Qt.UserRole)
        if kind == "page":
            self.stack.setCurrentIndex(value)

    def show_message(self, text: str, sticky: bool = False):
        """하단 상태 메시지 표시.
        기본은 MSG_TIMEOUT_MS(2초) 후 자동으로 사라진다(오류 안내 포함).
        sticky=True면 '테스트 중' 같은 진행 표시로, 완료 메시지가 교체할 때까지 유지한다."""
        self.info_label.setText(text)
        if self._msg_timer is None:
            self._msg_timer = QTimer(self)
            self._msg_timer.setSingleShot(True)
            self._msg_timer.timeout.connect(lambda: self.info_label.setText(""))
        if sticky:
            self._msg_timer.stop()
        else:
            self._msg_timer.start(MSG_TIMEOUT_MS)

    def choice_datasets(self):
        client = self.client()
        if client is None:
            return []
        try:
            ds = client.datasets()
            return sorted([d.get("name") for d in ds
                           if (d.get("type") or "FILESYSTEM") == "FILESYSTEM"
                           and d.get("name")])
        except TruenasError:
            return []
        except Exception:
            return []

    def client(self) -> Optional[TruenasClient]:
        cfg = self.config.load()
        if not cfg.get("base_url") or not cfg.get("api_key"):
            return None
        return TruenasClient(
            base_url=cfg["base_url"],
            api_key=cfg["api_key"],
            verify_tls=cfg.get("verify_tls", True),
            port=str(cfg.get("port") or ""),
            auth_mode=str(cfg.get("auth_mode") or "api_key"),
            basic_user=str(cfg.get("basic_user") or ""),
        )

    def run_async(self, fn: Callable, on_done: Callable):
        worker = Worker(fn)
        worker.signals.done.connect(on_done)
        worker.signals.failed.connect(self.on_error)
        self.pool.start(worker)

    def on_error(self, msg: str):
        self.show_message(msg)

    def reload_entity(self, page: QWidget) -> Callable:
        if isinstance(page, SnapshotsPage):
            return self.reload_snapshots(page)

        def handle(result):
            if isinstance(result, tuple) and len(result) == 2 and isinstance(result[1], str):
                self.show_message(result[1])
            else:
                self.show_message("작업 완료")
            page.refresh()
        return handle

    def reload_snapshots(self, page: SnapshotsPage) -> Callable:
        def handle(result):
            msg = result[1] if isinstance(result, tuple) and len(result) == 2 and isinstance(result[1], str) else "작업 완료"
            self.show_message(msg)
            page.refresh()
        return handle

    def test_done(self, info):
        self.conn_page.result_list.clear()
        self.conn_page.result_list.addItem(
            t("연결 테스트 성공", "Connection test passed")
            + f" - {info.get('hostname', '?')} ({info.get('version', '?')})"
        )
        self.show_message(t("연결 테스트 성공", "Connection test passed"))

    def pools_test_done(self, data):
        for name, status in data or []:
            self.conn_page.result_list.addItem(f"- 풀 {name} [{status}]")


def main():
    # 시작 시 저장된 언어 설정을 API 오류 메시지에 즉시 적용
    truenas_api.set_language(current_language())
    app = QApplication(sys.argv)
    icon_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "TrueNAS.ico")
    if os.path.isfile(icon_path):
        app.setWindowIcon(QIcon(icon_path))
    window = MainWindow()
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
