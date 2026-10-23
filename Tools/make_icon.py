# 앱 아이콘 생성기 (PySide6 QPainter, Pillow)
# 사용: .tnvenv/bin/python Tools/make_icon.py
# 결과:
#   Tools/AppIcon.iconset/*.png   -> iconutil로 AppIcon.icns 변환 (package.sh에서 실행)
#   Tools/TrueNAS_source_512.png / Tools/TrueNAS_source_1024.png (원본)
#   WindowsApp/TrueNAS.ico
#
# 디자인 v3: NAS 장비형 - 진한 남색 배경 + 랙마운트 스토리지 박스(전면 보드,
# 드라이브 베이 4개, 트레이 핸들 + 각 트레이 LED, 하단 통풍구/전원 표시)

import os
import sys

import PySide6

_qt_plugins_platforms = os.path.join(
    os.path.dirname(PySide6.__file__), "Qt", "plugins", "platforms")
if os.path.isdir(_qt_plugins_platforms):
    os.environ.setdefault("QT_QPA_PLATFORM_PLUGIN_PATH", _qt_plugins_platforms)

from PySide6.QtCore import QPointF, QRectF, Qt
from PySide6.QtGui import (
    QColor, QGuiApplication, QLinearGradient, QPainter, QPainterPath, QPen,
    QPixmap, QRadialGradient,
)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "Tools")
ICONSET_DIR = os.path.join(OUT_DIR, "AppIcon.iconset")

_app = QGuiApplication(sys.argv)  # QPixmap 사용 전 필수


def draw_icon(size: int) -> QPixmap:
    pm = QPixmap(size, size)
    pm.fill(Qt.transparent)
    p = QPainter(pm)
    p.setRenderHint(QPainter.Antialiasing)
    s = size / 1024.0

    # 배경: 라운드 스퀘어 + 남색 그라데이션
    margin = int(64 * s)
    radius = int(size * 0.225)
    bg = QRectF(margin, margin, size - margin * 2, size - margin * 2)
    grad = QLinearGradient(QPointF(bg.center().x(), bg.top()), QPointF(bg.center().x(), bg.bottom()))
    grad.setColorAt(0.0, QColor("#14324f"))
    grad.setColorAt(0.55, QColor("#0d2440"))
    grad.setColorAt(1.0, QColor("#08192c"))
    path = QPainterPath()
    path.addRoundedRect(bg, radius, radius)
    p.fillPath(path, grad)

    # 배경 은은한 광택
    sheen = QRadialGradient(bg.center().x(), bg.top() + bg.height() * 0.14, size * 0.55)
    sheen.setColorAt(0.0, QColor(255, 255, 255, 42))
    sheen.setColorAt(1.0, QColor(0, 0, 0, 0))
    p.fillPath(path, sheen)

    # NAS 본체 (전면 보드)
    chassis = QRectF(bg.x() + size * 0.10, bg.y() + size * 0.22, bg.width() * 0.80, bg.height() * 0.58)
    chassis_grad = QLinearGradient(QPointF(chassis.topLeft()), QPointF(chassis.bottomLeft()))
    chassis_grad.setColorAt(0.0, QColor("#4c5a68"))
    chassis_grad.setColorAt(0.12, QColor("#3a4653"))
    chassis_grad.setColorAt(0.55, QColor("#2b3541"))
    chassis_grad.setColorAt(1.0, QColor("#1f2833"))
    cp = QPainterPath()
    cp.addRoundedRect(chassis, size * 0.05, size * 0.05)
    p.fillPath(cp, chassis_grad)

    # 모서리 리벳 4개
    rivet_r = max(2.0, 9 * s)
    for cx_, cy_ in (
        (chassis.left() + size * 0.028, chassis.top() + size * 0.045),
        (chassis.right() - size * 0.028, chassis.top() + size * 0.045),
        (chassis.left() + size * 0.028, chassis.bottom() - size * 0.045),
        (chassis.right() - size * 0.028, chassis.bottom() - size * 0.045),
    ):
        p.setBrush(QColor("#c9d3dd"))
        p.setPen(QPen(QColor("#8b97a4"), max(1.0, 2.5 * s)))
        p.drawEllipse(QPointF(cx_, cy_), rivet_r, rivet_r)

    # 드라이브 베이(트레이) 4개
    tray_left = chassis.left() + chassis.width() * 0.055
    tray_w = chassis.width() * 0.80
    tray_h = chassis.height() * 0.165
    tray_top = chassis.top() + chassis.height() * 0.10
    tray_gap = chassis.height() * 0.195
    for i in range(4):
        ty = tray_top + tray_gap * i
        # 베이 슬롯 (어두운 배경)
        slot = QRectF(tray_left, ty, tray_w, tray_h)
        sp = QPainterPath()
        sp.addRoundedRect(slot, tray_h * 0.22, tray_h * 0.22)
        p.fillPath(sp, QColor("#12181f"))

        # 드라이브 트레이 (금속 느낌)
        tray = QRectF(tray_left + band_size, ty + tray_h * 0.14, tray_w - band_size * 1.6, tray_h * 0.72) if (band_size := size * 0.012) else None
        tp = QPainterPath()
        tp.addRoundedRect(tray, tray_h * 0.2, tray_h * 0.2)
        tgrad = QLinearGradient(QPointF(tray.topLeft()), QPointF(tray.bottomLeft()))
        tgrad.setColorAt(0.0, QColor("#aeb9c4"))
        tgrad.setColorAt(0.5, QColor("#8d99a6"))
        tgrad.setColorAt(1.0, QColor("#6f7c8a"))
        p.fillPath(tp, tgrad)

        # 트레이 슬랏 환기구 선
        line_h = max(1.5, 5 * s)
        for j in range(3):
            ly = tray.top() + tray.height() * (0.22 + 0.28 * j)
            ln = QRectF(tray.left() + tray.width() * 0.07, ly, tray.width() * 0.40, line_h)
            lp = QPainterPath()
            lp.addRoundedRect(ln, line_h / 2, line_h / 2)
            p.fillPath(lp, QColor("#57646f"))

        # 트레이 LED (우측)
        led_x = tray.right() - tray.width() * 0.08
        led_y = tray.center().y()
        led_r = max(2.0, 9 * s)
        color = QColor("#4cd964") if i != 2 else QColor("#f5c542")  # 3번 베이는 액티비티 주황
        p.setBrush(color)
        p.setPen(Qt.NoPen)
        p.drawEllipse(QPointF(led_x, led_y), led_r, led_r)

    # 하단 스트립: LAN 포트 + 전원 LED
    strip_y = chassis.bottom() - chassis.height() * 0.075
    strip = QRectF(chassis.right() - chassis.width() * 0.34, chassis.top() + chassis.height() * 0.845,
                   chassis.width() * 0.30, chassis.height() * 0.08)
    strip = QRectF(strip.left(), strip.top(), strip.width(), strip.height())
    strip_path = QRectF(strip)
    strip_y = chassis.top() + chassis.height() * 0.85
    # (strip 좌표 재계산: 하단 좌측 두 포트)
    port_w = chassis.width() * 0.115
    port_h = chassis.height() * 0.085
    for k in range(2):
        px = chassis.left() + chassis.width() * 0.055 + (port_w + chassis.width() * 0.02) * k
        py = chassis.bottom() - chassis.height() * 0.155
        pr = QRectF(px, py, port_w, port_h)
        ppr = QPainterPath()
        ppr.addRoundedRect(pr, 3 * s, 3 * s)
        p.fillPath(ppr, QColor("#10161d"))
        # 포트 내부 망 (작은 선)
        inner = QRectF(pr.left() + pr.width() * 0.2, pr.top() + pr.height() * 0.35,
                       pr.width() * 0.6, pr.height() * 0.14)
        ip = QPainterPath()
        ip.addRoundedRect(inner, line_h / 2, line_h / 2)
        p.fillPath(ip, QColor("#3b4a58"))

    # 전원 기호 (하단 우측, 녹색 원형 LED)
    power_x = chassis.right() - chassis.width() * 0.075
    power_y = chassis.bottom() - chassis.height() * 0.115
    power_r = max(3.0, 15 * s)
    halo2 = QRadialGradient(power_x, power_y, power_r * 2.2)
    halo2.setColorAt(0.0, QColor(76, 217, 100, 150))
    halo2.setColorAt(1.0, QColor(0, 0, 0, 0))
    p.setBrush(QColor(0, 0, 0, 0))
    p.setPen(Qt.NoPen)
    p.drawEllipse(QPointF(power_x, power_y), power_r * 2.2, power_r * 2.2)
    p.setBrush(QColor("#4cd964"))
    p.drawEllipse(QPointF(power_x, power_y), power_r, power_r)

    p.end()
    return pm


def main():
    os.makedirs(ICONSET_DIR, exist_ok=True)
    pairs = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]
    for name, px in pairs:
        pm = draw_icon(px)
        ok = pm.save(os.path.join(ICONSET_DIR, name), "PNG")
        if not ok:
            print(f"PNG 저장 실패: {name}")
            sys.exit(1)
        print(f"{name}: {px}px")

    # 원본 저장
    big = draw_icon(1024)
    big.save(os.path.join(OUT_DIR, "TrueNAS_source_1024.png"), "PNG")
    half = draw_icon(512)
    half.save(os.path.join(OUT_DIR, "TrueNAS_source_512.png"), "PNG")

    # Windows .ico (Pillow)
    try:
        from PIL import Image
        img = Image.open(os.path.join(OUT_DIR, "TrueNAS_source_1024.png"))
        target = os.path.join(ROOT, "WindowsApp", "TrueNAS.ico")
        img.save(target, format="ICO", sizes=[
            (16, 16), (24, 24), (32, 32), (48, 48),
            (64, 64), (128, 128), (256, 256),
        ])
        print("TrueNAS.ico 생성 완료")
    except Exception as err:
        print(f"ico 생성 실패(선택 사항): {err}")


if __name__ == "__main__":
    main()
