# 릴리스 아티팩트 생성기 (Website/releases/ 아래에 다운로드 파일 생성)
#
# 사용(로컬 macOS에서):
#   1) ./package.sh                      # dist/NaDeck.app 빌드
#   2) python3 Website/make_releases.py  # zip 생성
#
# 만들어지는 파일:
#   releases/NaDeck-macOS.dmg     macOS 설치 DMG (NaDeck.app + Applications 심볼릭 링크)
#   releases/NaDeck.exe           Windows 단일 실행 SFX(7zSD 모듈, 내장 런타임, 더블클릭 실행)
#   releases/NaDeck-Windows.zip   Windows 포터블 zip(대체용, 내장 런타임)
#   releases/build-info.json      빌드 시각(웹페이지 표시용)
# 소스 공유는 하지 않는 것이 방침(2026-10-18 사용자 확정)이라 전체 소스 zip은 생성하지 않는다.

import datetime
import os
import shutil
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Website", "releases")


def zip_dir(src_dir: str, zip_path: str, skip: tuple = (".build", ".venv", "__pycache__", "node_modules")):
    """폴더를 zip으로 압축 (내부 최상위에 이름을 유지해 압축 해제 시 이름이 나오게 한다)"""
    os.makedirs(os.path.dirname(zip_path), exist_ok=True)
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(src_dir):
            dirs[:] = [d for d in dirs if not any(s in d for s in skip)]
            for file in files:
                if any(s in file for s in skip):
                    continue
                full = os.path.join(root, file)
                rel = os.path.relpath(full, os.path.dirname(src_dir))
                zf.write(full, rel)


def main():
    os.makedirs(OUT, exist_ok=True)

    mac_app = os.path.join(ROOT, "dist", "NaDeck.app")
    # macOS DMG: dmg 스테이징(NaDeck.app + Applications 링크) 후 UDZO로 패킹
    mac_zip = os.path.join(OUT, "NaDeck-macOS.dmg")
    if os.path.isdir(mac_app):
        staging = os.path.join(ROOT, ".dmg_staging")
        shutil.rmtree(staging, ignore_errors=True)
        os.makedirs(staging, exist_ok=True)
        shutil.copytree(mac_app, os.path.join(staging, "NaDeck.app"))
        try:
            os.symlink("/Applications", os.path.join(staging, "Applications"))
        except Exception:
            pass
        ret = os.system(
            "hdiutil create -srcfolder '%s' -volname NaDeck -format UDZO -ov '%s' > /dev/null 2>&1"
            % (staging, mac_zip))
        shutil.rmtree(staging, ignore_errors=True)
        if ret == 0:
            print(f"OK  NaDeck-macOS.dmg ({os.path.getsize(mac_zip) // 1024} KiB)")
        else:
            print("(실패) hdiutil DMG 생성 오류")
    else:
        print("(건너뜀) dist/NaDeck.app 없음 - ./package.sh 먼저 실행")    # Windows 단일 exe: 7zSD SFX 모듈 + config + 7z 아카이브 결합 (다운로드 -> 더블클릭)
    runtime_root = os.path.join(ROOT, "WindowsApp", "portable_win", "NaDeckWin")
    sfx_mod = os.path.join(ROOT, "Tools", "sfx", "7zSD.sfx")
    win_exe = os.path.join(OUT, "NaDeck.exe")
    if os.path.isdir(runtime_root) and os.path.isfile(sfx_mod):
        app_src = os.path.join(ROOT, "WindowsApp")
        app_cache = os.path.join(runtime_root, "app")
        tmp_compile = os.path.join(ROOT, ".release_tmp_compile")
        shutil.rmtree(tmp_compile, ignore_errors=True)
        os.makedirs(tmp_compile, exist_ok=True)
        for src_name in ("main.py", "truenas_api.py"):
            src_path = os.path.join(app_src, src_name)
            if os.path.isfile(src_path):
                shutil.copy2(src_path, os.path.join(tmp_compile, src_name))
        # 앱 버전 단일 소스(VERSION 파일)를 exe 안의 모듈로 심어
        # 앱 내 업데이트 확인이 서버의 VERSION 파일과 비교하게 한다.
        version = ""
        version_path = os.path.join(ROOT, "VERSION")
        if os.path.isfile(version_path):
            with open(version_path, encoding="utf-8") as vf:
                version = vf.read().strip()
        if not version:
            version = "1.0.0"
        with open(os.path.join(tmp_compile, "nadeck_version.py"), "w", encoding="utf-8") as vf:
            vf.write('__version__ = "%s"\n' % version)
        ret = os.system(
            "cd \"%s\" && python3.9 -m compileall -b -q ." % tmp_compile
        )
        for src_name, pyc_name in (("main.py", "NaDeck.pyc"), ("truenas_api.py", "truenas_api.pyc"),
                                   ("nadeck_version.py", "nadeck_version.pyc")):
            pyc_src = os.path.join(tmp_compile, src_name.replace(".py", ".pyc"))
            if os.path.isfile(pyc_src):
                shutil.copy2(pyc_src, os.path.join(app_cache, pyc_name))
        shutil.rmtree(tmp_compile, ignore_errors=True)
        if ret != 0:
            print("(경고) pyc 컴파일 실패 - 캐시의 이전 pyc 사용")
        ar7z = os.path.join(OUT, "_nadeck_ar.7z")
        if os.path.exists(ar7z):
            os.remove(ar7z)
        ret2 = os.system(
            "cd '%s' && 7zz a -t7z -mx=7 '%s' . > /dev/null 2>&1" % (runtime_root, ar7z))
        if ret2 == 0 and os.path.isfile(ar7z):
            conf = os.path.join(OUT, "_sfx_config.txt")
            with open(conf, "w", encoding="utf-8") as f:
                f.write(
                    ";!@Install@!UTF-8!\n"
                    "Title=\"NaDeck 실행\"\n"
                    "ExtractTitle=\"NaDeck 실행 중...\"\n"
                    "RunProgram=\"hidcon:NaDeck.bat\"\n"
                    ";!@InstallEnd@!\n")
            with open(win_exe, "wb") as out:
                out.write(open(sfx_mod, "rb").read())
                out.write(open(conf, "rb").read())
                out.write(open(ar7z, "rb").read())
            os.remove(ar7z)
            os.remove(conf)
            print(f"OK  NaDeck.exe ({os.path.getsize(win_exe) // 1024} KiB)")
        else:
            print("(실패) 7zz 아카이브 생성 오류 - exe 미생성")
    else:
        print("(건너뜀) SFX 모듈/런타임 캐시 없음")


    with open(os.path.join(OUT, "build-info.json"), "w", encoding="utf-8") as f:
        now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
        f.write('{"built_at": "%s"}' % now)
    print("OK  build-info.json")

    # 앱 내 업데이트 확인용: VERSION 파일을 그대로 공개 경로에 배포한다.
    version_src = os.path.join(ROOT, "VERSION")
    if os.path.isfile(version_src):
        with open(version_src, encoding="utf-8") as vf:
            version = vf.read().strip()
        with open(os.path.join(OUT, "VERSION"), "w", encoding="utf-8") as f:
            f.write(version + "\n")
        print(f"OK  VERSION ({version})")


if __name__ == "__main__":
    main()
