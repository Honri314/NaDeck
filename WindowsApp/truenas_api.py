# TrueNAS SCALE REST API 클라이언트
# /api/v2.0 + X-API-Key 인증 (자체 서명 인증서 허용 옵션 포함)
import datetime
import json
import re
from typing import Any, Dict, List, Optional
from urllib.parse import quote

import requests

V2 = "/api/v2.0"


# 언어 설정: "ko"(한국어, 기본) 또는 "en"
LANGUAGE = "ko"


def set_language(value: str) -> None:
    global LANGUAGE
    LANGUAGE = "en" if str(value).lower() == "en" else "ko"


def _msg(ko: str, en: str) -> str:
    return en if LANGUAGE == "en" else ko


def _friendly_connection_error(err: Exception) -> str:
    """영어 원문 연결 오류(accept, errno 등)를 한국어 안내로 변환"""
    text = str(err)
    low = text.lower()
    if "connection refused" in low:
        base = _msg(
            "연결이 거부되었습니다 - 주소/포트를 확인하고 TrueNAS 전원과 방화벽을 확인하세요.",
            "Connection refused - check address/port and that TrueNAS is running.")
    elif "nodename nor servname" in low or "name or service not known" in low:
        base = _msg(
            "호스트 이름을 찾을 수 없습니다 - 주소 철자와 네트워크(DNS)를 확인하세요.",
            "Host not found - check the address spelling and DNS.")
    elif "no route to host" in low or "timed out" in low or "timedout" in low:
        base = _msg(
            "서버에 접근할 수 없습니다 - 네트워크, 포트, 방화벽을 확인하세요.",
            "Unreachable - check network, port and firewall.")
    else:
        base = _msg(
            "서버에 연결하지 못했습니다 - 주소/포트를 확인하세요.",
            "Could not connect to the server - check address/port.")
    detail = text if text else ""
    return base if not detail else f"{base}\n({detail})"


class TruenasError(Exception):
    pass


def normalize_base_url(raw: str) -> str:
    """주소 정규화: 일반 IP/LAN 호스트뿐 아니라 테일스케일(Tailscale)의
    100.x.x.x IP 또는 매직DNS 이름(*.ts.net)도 지원"""
    s = (raw or "").strip()
    if not s:
        return s
    low = s.lower()
    if not low.startswith("http://") and not low.startswith("https://"):
        s = "https://" + s
    while s.endswith("/"):
        s = s[:-1]
    if not s.lower().endswith(V2):
        s += V2
    return s


def apply_port(base_url: str, port: Optional[str]) -> str:
    """포트(선택)를 호스트 뒤에 붙인다. 기본: https 443 / http 80.
    이미 host:port 형태면 무시한다."""
    expr = str(port or "").strip()
    if not expr:
        return base_url
    match = re.match(r"^(https?://)([^/:]+)(:\d+)?(/.*)?$", base_url)
    if not match:
        return base_url
    if match.group(3):
        return base_url
    return f"{match.group(1)}{match.group(2)}:{expr}{match.group(4) or ''}"


class TruenasClient:
    def __init__(self, base_url: str, api_key: str, verify_tls: bool = True,
                 timeout: int = 30, port: Optional[str] = None,
                 auth_mode: Optional[str] = None, basic_user: Optional[str] = None):
        self.base_url = apply_port(normalize_base_url(base_url), port)
        self.api_key = api_key
        self.verify = verify_tls
        self.timeout = timeout
        # 인증 방식 폴백: "api_key"(기본) / "bearer" / "basic"
        self.auth_mode = auth_mode or "api_key"
        self.basic_user = basic_user or ""

    # ---------------------------------- 저수준

    def _request(self, method: str, path: str, body: Optional[Dict[str, Any]] = None) -> Any:
        if not self.base_url or not self.api_key:
            raise TruenasError(_msg(
                "주소와 API 키를 먼저 설정하세요.",
                "Set the address and API key first.",
            ))
        url = f"{self.base_url}{path}"
        # API 키를 정리 후 전송 (공백/줄바꿈/따옴표 자동 제거)
        api_key = str(self.api_key or "").strip().strip("\"'")
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json",
        }
        # 인증은 설정된 방식(api_key/bearer/basic)에 따른다.
        import base64
        if self.auth_mode == "bearer":
            headers["Authorization"] = f"Bearer {api_key}"
        elif self.auth_mode == "basic":
            raw = f"{self.basic_user}:{api_key}"
            headers["Authorization"] = "Basic " + base64.b64encode(raw.encode()).decode()
        else:
            headers["X-API-Key"] = api_key
        if isinstance(body, dict):
            for key, value in body.items():
                if isinstance(value, datetime.datetime):
                    body[key] = value.isoformat()
        try:
            resp = requests.request(
                method, url,
                headers=headers,
                data=json.dumps(body) if body is not None else None,
                verify=self.verify,
                timeout=self.timeout,
            )
        except requests.exceptions.SSLError:
            raise TruenasError(_msg(
                "TLS 인증서를 신뢰할 수 없습니다. 설정에서 'TLS 인증서 검증'을 끄고(자체 서명 인증서 허용) 다시 시도하세요.",
                "Untrusted TLS certificate. Try disabling certificate verification in settings.",
            ))
        except requests.exceptions.ConnectionError as err:
            raise TruenasError(_friendly_connection_error(err))
        except requests.exceptions.Timeout:
            raise TruenasError(_msg(
                "응답 시간 초과 (timeout).",
                "Response timed out.",
            ))

        if resp.status_code >= 400:
            try:
                obj = resp.json()
                detail = obj.get("error") or obj.get("message") or (resp.text[:300] if resp.text else "")
            except ValueError:
                detail = (resp.text[:300] if resp.text else "")
            status = resp.status_code
            detail_low = (detail or "").lower()
            if status in (401, 403):
                if "api" in detail_low and ("invalid" in detail_low or "key" in detail_low):
                    base = _msg(
                        "API 키가 올바르지 않습니다.\n"
                        "TrueNAS 웹 UI(Credential -> API Keys)에서 키의 Copy 버튼으로 전체를 복사한 뒤,\n"
                        "공백/줄바꿈/따옴표 없이 붙여넣었는지 확인하세요.\n"
                        "키를 지우고 다시 발급해도 좋습니다.",
                        "The API key is invalid.\n"
                        "Copy the full key via the Copy button in the TrueNAS web UI and paste it without spaces or quotes.\n"
                        "You can also revoke and re-create the key.")
                else:
                    base = _msg("인증 실패 - API 키를 확인하세요.",
                                "Authentication failed - check your API key.")
            elif status == 404:
                base = _msg("엔드포인트를 찾을 수 없습니다 - TrueNAS 버전을 확인하세요.",
                            "Endpoint not found - check your TrueNAS version.")
            elif status in (400, 422):
                base = _msg("요청이 거부되었습니다", "The request was rejected")
            elif status >= 500:
                base = _msg("서버 오류", "Server error")
            else:
                base = _msg("연결 오류", "Connection error")
            # 404는 어떤 경로가 없는지 그대로 보여준다 (원인 파악 지연 방지)
            if status == 404:
                detail = f"경로: {path}" + (f", 서버 원문: {detail}" if detail else "")
            text = base if not detail else f"{base}\n({detail})"
            raise TruenasError(f"HTTP {status}: {text}")
        try:
            return resp.json()
        except ValueError:
            return None

    def get(self, path: str, query: Optional[Dict[str, str]] = None) -> Any:
        if query:
            qs = "&".join(f"{k}={quote(str(v))}" for k, v in query.items())
            path = f"{path}?{qs}"
        return self._request("GET", path)

    def get_list(self, path: str) -> List[dict]:
        """일부 엔드포인트는 단일 오브젝트로 응답하므로 리스트로 안전 변환"""
        data = self.get(path)
        if isinstance(data, list):
            return data
        if data is None:
            return []
        return [data]

    def post(self, path: str, body: Any) -> Any:
        return self._request("POST", path, body)

    def put(self, path: str, body: Dict[str, Any]) -> Any:
        return self._request("PUT", path, body)

    def delete(self, path: str) -> None:
        self._request("DELETE", path)

    # ---------------------------------- 고수준 API

    def system_info(self) -> Dict[str, Any]:
        return self.get("/system/info") or {}

    # ---------------------------------- reporting 폴백
    # v25.10에서는 /system/cpu, /system/memory 가 REST에 존재하지 않으며,
    # CPU/메모리 사용률은 POST /reporting/get_data 로 계산한다.

    def _reporting_components(self, graph: str) -> List[dict]:
        # 25.10 실장비 스펙상 유일한 라우트는 /reporting/get_data 이다.
        try:
            result = self.post("/reporting/get_data", {"graphs": [{"name": graph}]})
        except TruenasError:
            return []
        if isinstance(result, dict):
            result = [result]
        if isinstance(result, list):
            comps = [c for c in result if isinstance(c, dict) and c.get("name") == graph]
            if comps:
                return comps
        return []

    def cpu_core_usages(self) -> List[Dict[str, float]]:
        """코어별 사용률: [{"name": "cpu0", "percent": 13.0}, ...]
        25.10 실측: cpu 그래프 시리즈 cpu0..cpuN (단위 %)"""
        for comp in self._reporting_components("cpu"):
            sample = self._reporting_sample(comp)
            if not sample:
                continue
            cores: List[Dict[str, float]] = []
            vals: List[float] = []
            for k, v in sample.items():
                if not re.fullmatch(r"cpu\d+", str(k)):
                    continue
                n = self._num(v)
                if n is None:
                    continue
                cores.append({"name": str(k), "value": n})
                vals.append(n)
            if not vals:
                continue
            if max(vals) <= 1.0:            # 0~1 분율 -> % 보정
                cores = [{**c, "value": c["value"] * 100.0} for c in cores]
            cores.sort(key=lambda c: int(re.sub(r"\D", "", c["name"]) or 0))
            return cores
        return []

    def disk_temperatures(self) -> Dict[str, float]:
        """25.10: POST /disk/temperatures {} -> {"sda": 32.0, ...} (섭씨)"""
        result = self.post("/disk/temperatures", {})
        if not isinstance(result, dict):
            return {}
        out: Dict[str, float] = {}
        for k, v in result.items():
            n = self._num(v)
            if n is not None:
                out[str(k)] = n
        return out

    @staticmethod
    def _as_int(v: Any) -> Optional[int]:
        try:
            return int(v)
        except (TypeError, ValueError):
            return None

    @staticmethod
    def _num(v: Any) -> Optional[float]:
        try:
            return float(v)
        except (TypeError, ValueError):
            return None

    def _reporting_sample(self, comp: dict) -> Dict[str, Any]:
        """최신 샘플을 dict로 반환.
        v25.10 문서 기준 data는 딕셕너리 배열({시리즈명: 값}), aggregations.mean도 사용 가능.
        구형(리스트 행 + legend) 형식도 함께 지원한다."""
        if not isinstance(comp, dict):
            return {}
        data = comp.get("data") or []
        if isinstance(data, list) and data:
            last = data[-1]
            if isinstance(last, dict):
                return last
            legend = comp.get("legend") or []
            if isinstance(last, (list, tuple)) and legend:
                pairs = list(zip([str(x) for x in legend], list(last)))
                return dict(pairs)
        aggs = comp.get("aggregations")
        if isinstance(aggs, dict) and isinstance(aggs.get("mean"), dict) and aggs["mean"]:
            return aggs["mean"]
        return {}

    def _pick_all(self, sample: Dict[str, Any], *names: str) -> List[float]:
        """시리즈 키 매칭: 키 마지막 세그먼트(예: 'cpu.user' -> 'user')로 찾는다."""
        buckets: Dict[str, List[float]] = {}
        for k, v in sample.items():
            suffix = str(k).split(".")[-1].lower()
            n = self._num(v)
            if n is None:
                continue
            buckets.setdefault(suffix, []).append(n)
        for want in names:
            if want in buckets:
                return buckets[want]
        return []

    def alerts(self) -> List[dict]:
        # v25.10: /alert 는 웹소켓 전용, 모듈 라우트는 /alert/list 이다.
        return [a for a in self.get_list("/alert/list") if not a.get("dismissed")]

    def all_alerts(self) -> List[dict]:
        return self.get_list("/alert/list")

    def alert_restore(self, alert_id) -> None:
        # v25.10: POST /alert/restore 본문 = alert uuid 문자열
        self.post("/alert/restore", str(alert_id))

    # ---------------------------------- 부팅 환경 (웹 대시보드 동급)

    def boot_environments(self) -> List[dict]:
        return self.get_list("/boot/environment/query")

    def activate_boot_environment(self, env_id: str) -> None:
        self.post("/boot/environment/activate", {"id": env_id})

    def destroy_boot_environment(self, env_id: str) -> None:
        self.post("/boot/environment/destroy", {"id": env_id})

    def toggle_keep_boot_environment(self, env_id: str, keep: bool) -> None:
        self.post("/boot/environment/keep", {"id": env_id, "value": keep})

    # ---------------------------------- API 키

    def api_keys(self) -> List[dict]:
        return self.get_list("/api_key")

    def create_api_key(self, name: str, username: str) -> dict:
        return self.post("/api_key", {"name": name, "username": username})

    def revoke_api_key(self, key_id: str) -> None:
        self.delete(f"/api_key/id/{quote(str(key_id), safe='')}")

    # ---------------------------------- 시스템 업데이트

    def update_status(self) -> dict:
        return self.get("/update/status") or {}

    def update_available_versions(self) -> List[dict]:
        return self.get_list("/update/available_versions")

    def update_run(self, reboot: bool = True) -> dict:
        # 주의: réel 업그레이드 수행(재부팅 포함 가능). UI에서 이중 확인 후 호출.
        return self.post("/update/run", {"reboot": reboot})

    # ---------------------------------- 감사 로그

    def audit_log(self, limit: int = 100, services: Optional[List[str]] = None) -> List[dict]:
        body: Dict[str, Any] = {
            "services": services or ["MIDDLEWARE"],
            "query-options": {"limit": limit, "order_by": ["-timestamp"]},
        }
        return self.post("/audit/query", body) or []

    # ---------------------------------- 네트워크 요약

    def network_summary(self) -> dict:
        return self.get("/network/general/summary") or {}

    def network_configuration(self) -> dict:
        return self.get("/network/configuration") or {}

    # ---------------------------------- 정적 라우트

    def static_routes(self) -> List[dict]:
        return self.get_list("/staticroute")

    def add_static_route(self, destination: str, gateway: str, description: str = "") -> dict:
        body: Dict[str, Any] = {"destination": destination, "gateway": gateway}
        if description:
            body["description"] = description
        return self.post("/staticroute", body)

    def delete_static_route(self, route_id: int) -> None:
        self.delete(f"/staticroute/id/{route_id}")

    # ---------------------------------- 편집(PUT) 도우미

    def edit_entity(self, spec, row_id: Any, body: Dict[str, Any]) -> dict:
        """EntityPage 편집: spec.edit_url(row_id) 은 PUT 경로를 만들어준다."""
        return self.put(spec.edit_url(row_id), body)

    def update_user(self, user_id: int, body: Dict[str, Any]) -> dict:
        return self.put(f"/user/id/{user_id}", body)

    def update_smb_share(self, share_id: int, body: Dict[str, Any]) -> dict:
        return self.put(f"/sharing/smb/id/{share_id}", body)

    def update_nfs_share(self, share_id: int, body: Dict[str, Any]) -> dict:
        return self.put(f"/sharing/nfs/id/{share_id}", body)

    # ---------------------------------- 앱 카탈로그

    def app_catalog(self) -> List[dict]:
        """465여 개 앱: readme HTML 은 제외하고 필요한 필드만 반환"""
        keep = ("name", "train", "latest_human_version", "latest_app_version",
                "description", "categories", "location", "support", "healthy")
        rows = self.get_list("/app/available")
        return [{k: r.get(k) for k in keep if k in r} for r in rows]

    def app_categories(self) -> List[str]:
        return self.get_list("/app/categories") or []

    def pools(self) -> List[dict]:
        return self.get_list("/pool")

    def cpu_usage(self) -> Optional[float]:
        try:
            cpus = self.get_list("/system/cpu")
            data = cpus[0].get("data") if cpus else None
            if data:
                return float(data[-1])
        except (TruenasError, IndexError, KeyError, ValueError, TypeError):
            pass
        return self._cpu_from_reporting()

    def _cpu_from_reporting(self) -> Optional[float]:
        # 25.10 실측: cpu 그래프 시리즈 = [time, cpu(전체%), cpu0..cpuN(코어별 %)]
        for comp in self._reporting_components("cpu"):
            sample = self._reporting_sample(comp)
            if not sample:
                continue
            overall = self._pick_all(sample, "cpu")
            if overall:
                pct = overall[-1]
                # 전 구간 값이 0~1 이면 분율로 본다(0~100 % 대비)
                if max(overall) <= 1.0:
                    pct *= 100.0
                return min(max(pct, 0.0), 100.0)
            # 구형 스키마 호환(user/system/idle 시리즈)
            users = self._pick_all(sample, "user")
            systems = self._pick_all(sample, "system")
            idles = self._pick_all(sample, "idle")
            samples: List[float] = []
            if users or systems:
                count = max(len(users), len(systems))
                for i in range(count):
                    u = users[i] if i < len(users) else (users[-1] if users else 0.0)
                    s = systems[i] if i < len(systems) else (systems[-1] if systems else 0.0)
                    samples.append(u + s)
            elif idles:
                samples = [100.0 - idle for idle in idles]
            if samples:
                pct = sum(samples) / len(samples)
                # 값이 0~1 분율로 오는 경우 백분율로 보정
                raw = users + systems + idles
                if raw and max(raw) <= 1.0 and max(raw) > 0.0:
                    pct *= 100.0
                return min(max(pct, 0.0), 100.0)
        return None

    def memory_usage(self) -> Dict[str, float]:
        # v25.10: /system/memory 는 REST에 존재하지 않으므로 바로 reporting 폴백.
        return self._memory_from_reporting()

    def _memory_from_reporting(self) -> Dict[str, float]:
        # 25.10 실측: memory 그래프 시리즈 = [time, available(바이트)].
        # 전체 크기는 /system/info 의 physmem 로 구한다.
        for comp in self._reporting_components("memory"):
            sample = self._reporting_sample(comp)
            if not sample:
                continue
            avail_vals = self._pick_all(sample, "available")
            if not avail_vals:
                continue
            avail = float(avail_vals[-1])
            total = None
            try:
                total = self._num((self.system_info() or {}).get("physmem"))
            except TruenasError:
                pass
            if not total or total <= 0:
                continue
            used_pct = min(max((1.0 - avail / total) * 100.0, 0.0), 100.0)
            return {"free": round(100.0 - used_pct, 1), "used": round(used_pct, 1)}
        return {}

    def smb_shares(self) -> List[dict]:
        return self.get_list("/sharing/smb")

    def nfs_shares(self) -> List[dict]:
        return self.get_list("/sharing/nfs")

    def add_smb_share(self, name: str, path: str, comment: str = "") -> dict:
        body: Dict[str, Any] = {"name": name, "path": path}
        if comment:
            body["comment"] = comment
        return self.post("/sharing/smb", body)

    def delete_smb_share(self, share_id: int) -> None:
        self.delete(f"/sharing/smb/id/{share_id}")

    def delete_nfs_share(self, share_id: int) -> None:
        self.delete(f"/sharing/nfs/id/{share_id}")

    def snapshots(self) -> List[dict]:
        return self.get_list("/pool/snapshot")

    def datasets(self) -> List[dict]:
        return self.get_list("/pool/dataset")

    def create_snapshot(self, dataset: str, name: str, recursive: bool = False) -> dict:
        body: Dict[str, Any] = {"dataset": dataset, "name": name, "recursive": recursive}
        return self.post("/pool/snapshot", body)

    def delete_snapshot(self, full_name: str) -> None:
        self.delete(f"/pool/snapshot/id/{quote(full_name, safe='')}")

    def replications(self) -> List[dict]:
        return self.get_list("/replication")

    def users(self) -> List[dict]:
        return self.get_list("/user")

    def services(self) -> List[dict]:
        return self.get_list("/service")

    def service_start(self, service_name: str) -> None:
        # v25.10: /service/start 본문 = 서비스 이름 문자열 (id가 아님)
        self.post("/service/start", service_name)

    def service_stop(self, service_name: str) -> None:
        self.post("/service/stop", service_name)

    def service_restart(self, service_name: str) -> None:
        # v25.10: /service/restart 본문 = {service: 이름}
        self.post("/service/restart", {"service": service_name})

    # ---------------------------------- 시스템 전원 (웹 대시보드 동급)

    def system_reboot(self) -> dict:
        return self.post("/system/reboot",
                         {"reason": "NaDeck 앱에서 요청한 재부팅"})

    def system_shutdown(self) -> dict:
        return self.post("/system/shutdown",
                         {"reason": "NaDeck 앱에서 요청한 종료"})

    # ---------------------------------- 스냅샷 롤백/클론

    def rollback_snapshot(self, full_name: str, recursive: bool = False) -> None:
        body: Dict[str, Any] = {"id": full_name}
        if recursive:
            body["options"] = {"recursive": True}
        self.post("/pool/snapshot/rollback", body)

    def clone_snapshot(self, full_name: str, dst: str) -> dict:
        return self.post("/pool/snapshot/clone",
                         {"snapshot": full_name, "dataset_dst": dst})

    # ---------------------------------- 앱(Applications)

    def apps(self) -> List[dict]:
        return self.get_list("/app")

    def app_action(self, app_name: str, action: str) -> None:
        """action: start/stop/redeploy/upgrade
        v25.10 라우트: POST /app/<action> (본문=앱 이름 문자열),
        upgrade는 POST /app/upgrade (본문={app_name, options?})"""
        if action == "upgrade":
            self.post("/app/upgrade", {"app_name": app_name})
        else:
            self.post(f"/app/{action}", app_name)

    def app_delete(self, app_name: str) -> None:
        # v25.10: DELETE /app/id/<app_name>
        self.delete(f"/app/id/{quote(app_name, safe='')}")

    # ---------------------------------- 가상머신(VM)

    def vms(self) -> List[dict]:
        return self.get_list("/vm")

    def vm_status(self, vm_id: int) -> dict:
        # v25.10: POST /vm/id/<id>/status
        return self.post(f"/vm/id/{vm_id}/status", {}) or {}

    def vm_action(self, vm_id: int, action: str) -> None:
        """action: start/stop/restart/poweroff (v25.10: POST /vm/id/<id>/<action>)"""
        self.post(f"/vm/id/{vm_id}/{action}", {})

    def vm_delete(self, vm_id: int) -> None:
        # v25.10: DELETE /vm/id/<id>
        self.delete(f"/vm/id/{vm_id}")

    def create_vm(self, body: Dict[str, Any]) -> dict:
        """v25.10: POST /vm 로 기본 VM 생성(본문에 devices 없음),
        이후 장치 디스크/CDROM/NIC은 POST /vm/device 로 부착한다.
        body["devices"]가 있으면 생성 후 순서대로 부착한다."""
        devices = body.pop("devices", []) or []
        vm = self.post("/vm", body)
        vm_id = vm.get("id") if isinstance(vm, dict) else None
        if vm_id is None and devices:
            raise TruenasError(_msg(
                "VM 생성 응답에 id가 없어 장치를 부착하지 못했습니다.",
                "VM create response has no id; devices not attached."))
        for dev, order in zip(devices, range(len(devices))):
            # main.py 형식 {dtype, attributes} 와 평평한 attrs 형식 모두 수용
            if isinstance(dev, dict) and "attributes" in dev:
                attrs = dict(dev.get("attributes") or {})
                attrs.setdefault("dtype", dev.get("dtype"))
            else:
                attrs = dict(dev or {})
            self.post("/vm/device", {"vm": vm_id, "attributes": attrs,
                                     "order": order})
        return vm

    def scrub_tasks(self) -> List[dict]:
        return self.get_list("/pool/scrub")

    def scrub_run(self, scrub_id: int) -> None:
        # v25.10: POST /pool/scrub/run 본문 = {name: 풀 이름}
        pool_name = None
        for s in self.get_list("/pool/scrub"):
            if self._as_int(s.get("id")) == scrub_id:
                pool_name = s.get("pool") or s.get("name")
                break
        if not pool_name:
            raise TruenasError(_msg(
                f"스크럽 id {scrub_id}에 해당하는 풀을 찾지 못했습니다.",
                f"Pool for scrub id {scrub_id} not found."))
        self.post("/pool/scrub/run", {"name": pool_name})

    def alert_dismiss(self, alert_id) -> None:
        # v25.10: POST /alert/dismiss 본문 = alert uuid 문자열
        self.post("/alert/dismiss", str(alert_id), )

    def add_user(self, username: str, password: str, full_name: str = "",
                 samba: bool = True) -> dict:
        body: Dict[str, Any] = {
            "username": username,
            "password": password,
            "group_create": True,
        }
        if full_name:
            body["full_name"] = full_name
        if samba:
            body["smb"] = True
        return self.post("/user", body)

    def delete_user(self, user_id: int) -> None:
        self.delete(f"/user/id/{user_id}")

    def diagnose(self) -> List[str]:
        """단계별 연결 진단: 주소 해석 -> API 키 요약 -> 실제 서버 응답.
        401/403이면 인증 방식별 폴백 실험까지 수행합니다.
        반환: (진단 줄들, 성공한 인증 방식 또는 None)"""
        self.found_auth = None
        lines = [f"단계 1 - 해석된 주소: {self.base_url}"]
        key = str(self.api_key or "").strip().strip("\"'")
        if len(key) > 8:
            lines.append(f"단계 2 - API 키: {key[:4]}...{key[-4:]} (길이 {len(key)})")
        else:
            lines.append(
                "단계 2 - API 키: (입력값이 너무 짧습니다 - "
                "웹 UI Copy 버튼으로 전체 키를 붙여넣었는지 확인)")
        lines.append("단계 3 - 서버 요청 시도 중... (/system/info)")
        try:
            info = self.system_info()
            lines.append(
                f"성공: {info.get('hostname', '?')} ({info.get('version', '?')}) - 인증 정상")
            return (lines, None)
        except TruenasError as err:
            text = str(err)
            lines.append(f"실패: {text}")

            if "401" in text or "403" in text:
                lines.append("- 인증 방식별 자동 실험을 시작합니다...")
                for label, mode in (("X-API-Key", "api_key"),
                                    ("Bearer", "bearer"),
                                    ("Basic", "basic")):
                    if mode == "basic" and not self.basic_user.strip():
                        lines.append("- 인증 방식 Basic: (사용자 이름 미입력 - 건너뜀)")
                        continue
                    saved_mode, saved_user = self.auth_mode, self.basic_user
                    self.auth_mode, self.basic_user = mode, self.basic_user
                    try:
                        info = self.system_info()
                        lines.append(
                            f"- 인증 방식 {label} -> 성공! 이 방식을 저장합니다.")
                        self.found_auth = mode
                        lines.append(
                            f"재연결 성공: {info.get('hostname', '?')} "
                            f"({info.get('version', '?')})")
                        return (lines, self.found_auth)
                    except TruenasError as probe_err:
                        probe_msg = str(probe_err).split("\n")[0]
                        lines.append(f"- 인증 방식 {label} -> {probe_msg}")
                    finally:
                        self.auth_mode, self.basic_user = saved_mode, saved_user
                lines.append(
                    "- 모든 인증 방식 실패. 키를 재발급(Copy 버튼)하거나, "
                    "Basic 인증용 TrueNAS 사용자 이름을 입력하고 다시 진단하세요.")
            else:
                lines.append(
                    "도움말: 주소/포트, 네트워크(또는 테일스케일), "
                    "키 복사 방식(Copy 버튼)을 순서대로 확인하세요.")
        return (lines, None)
