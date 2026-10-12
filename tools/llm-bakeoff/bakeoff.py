"""Helyi LLM bake-off tesztkészlet a llama-cpp backendhez (local-ai-stack roadmap, 4. lépés).

Az open-webui podban fut, amely ismeri a backend URL-t és a saját API kulcsát:
  kubectl exec -i -n ai deploy/open-webui -c open-webui -- python3 - < tools/llm-bakeoff/bakeoff.py
Minden tesztadat szintetikus; egyetlen JSON dokumentumot ír ki sebesség-, minőség- és tool-calling eredményekkel.
"""
import json
import os
import re
import time
import urllib.request

BASE = os.environ["OPENAI_API_BASE_URL"]
KEY = os.environ["OPENAI_API_KEY"]
HEADERS = {"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}


def chat(messages, max_tokens=300, **extra):
    body = {"messages": messages, "max_tokens": max_tokens, "temperature": 0.2, **extra}
    req = urllib.request.Request(BASE + "/chat/completions", data=json.dumps(body).encode(), headers=HEADERS)
    return json.load(urllib.request.urlopen(req, timeout=1800))


def timing(r):
    tm = r["timings"]
    return {"prompt_n": tm["prompt_n"], "prompt_tps": round(tm["prompt_per_second"], 1),
            "prompt_s": round(tm["prompt_ms"] / 1000, 1), "gen_n": tm["predicted_n"],
            "gen_tps": round(tm["predicted_per_second"], 2)}


def parse_json(text):
    m = re.search(r"\{.*\}|\[.*\]", text or "", re.S)
    try:
        return json.loads(m.group(0)) if m else None
    except ValueError:
        return None


def content(r):
    return r["choices"][0]["message"].get("content") or ""


def run_speed():
    prompt = [{"role": "user", "content": "Írj egy kb. 150 szavas bekezdést a Balatonról."}]
    return [timing(chat(prompt, 250, cache_prompt=False)) for _ in range(3)]


def run_long_prompt():
    para = ("A magyar közigazgatásban az elektronikus ügyintézés az elmúlt években jelentősen bővült. "
            "Az ügyfélkapun keresztül ma már a legtöbb hatósági eljárás elindítható, a dokumentumok pedig "
            "hitelesített formában érkeznek meg a tárhelyre. ")
    doc = " ".join(f"{i}. szakasz: {para}" for i in range(1, 120))
    r = chat([{"role": "user", "content": doc + "\n\nFoglald össze egy mondatban a fenti szöveg lényegét!"}],
             60, cache_prompt=False)
    return {"answer": content(r), **timing(r)}


HUNGARIAN = [
    "Javítsd ki a helyesírási hibákat, csak a javított mondatot add vissza: 'Tegnap el mentünk a boltba, de nem volt nyitva mert ünnep nap volt.'",
    "Javítsd ki, csak a javított szöveget add vissza: 'A gyerekek az udvaron játszotak, mikor elkezdet esni az eső.'",
    "Írd át hivatalos, udvarias stílusba: 'Figyelj, a számla még mindig nincs kifizetve, intézd már el légyszi.'",
    "Írd át közvetlen, baráti hangnembe: 'Tisztelt Kolléga! Tájékoztatom, hogy a holnapi értekezlet elmarad.'",
    "Foglald össze 2 mondatban: A Magyar Nemzeti Bank az alapkamatot változatlanul hagyta, mivel az infláció a várakozásoknak megfelelően alakult, ugyanakkor a forint árfolyama ingadozott. A döntéshozók szerint a következő negyedévben óvatos lazításra lehet számítani, ha a külső környezet stabil marad.",
    "Mi Magyarország fővárosa, és melyik folyó szeli ketté?",
    "Ki írta a Toldit, és melyik évszázadban élt?",
    "Mikor volt a mohácsi csata?",
    "Magyarázd el egy 10 évesnek, mi az a kamatos kamat (max 4 mondat).",
    "Fordítsd magyarra természetes hangzással: 'The meeting has been postponed until further notice due to unforeseen circumstances.'",
]


def run_hungarian():
    results = []
    for p in HUNGARIAN:
        r = chat([{"role": "user", "content": p}], 250)
        results.append({"prompt": p, "answer": content(r), **timing(r)})
    return results


PAPERLESS_DOCS = [
    ("SZÁMLA\nSzámla sorszáma: E-2026-004512\nKibocsátó: MVM Next Energiakereskedelmi Zrt., 1081 Budapest, II. János Pál pápa tér 20.\nVevő: Kovács Péter\nTeljesítés: 2026.09.30\nKelt: 2026.10.02\nVillamosenergia-díj szeptember: 18 450 Ft\nFizetendő: 18 450 Ft",
     "mvm", "2026-10-02"),
    ("NAV - Nemzeti Adó- és Vámhivatal\nÉrtesítés\nTárgy: 2025. évi személyijövedelemadó-bevallási tervezet elkészült\nKelt: Budapest, 2026. március 15.\nTisztelt Adózó! Tájékoztatjuk, hogy a bevallási tervezet megtekinthető az eSZJA oldalon.",
     "nav", "2026-03-15"),
    ("Szerződés\nmely létrejött a Telekom Nyrt. (szolgáltató) és Horváth Anna (előfizető) között\nTárgy: Mobil előfizetés, Magenta Max díjcsomag, 24 hónap határozott idő\nKelt: Szeged, 2026. június 3.",
     "telekom", "2026-06-03"),
]
PAPERLESS_PROMPT = ("Az alábbi dokumentumból adj vissza KIZÁRÓLAG egy JSON objektumot ezekkel a kulcsokkal: "
                    "title (rövid magyar cím), tags (1-3 magyar címke listája), correspondent (kibocsátó szervezet "
                    "rövid neve), document_type (pl. Számla, Értesítés, Szerződés), created (YYYY-MM-DD).\n\n")


def run_paperless():
    results = []
    for doc, correspondent, created in PAPERLESS_DOCS:
        r = chat([{"role": "user", "content": PAPERLESS_PROMPT + doc}], 200)
        j = parse_json(content(r))
        is_obj = isinstance(j, dict)
        results.append({
            "valid_json": is_obj and all(k in j for k in ("title", "tags", "correspondent", "document_type", "created")),
            "correspondent_ok": is_obj and correspondent in str(j.get("correspondent", "")).lower(),
            "date_ok": is_obj and j.get("created") == created,
            "output": j if is_obj else content(r), **timing(r)})
    return results


CATEGORIES = ["Élelmiszer", "Rezsi", "Közlekedés", "Szórakozás", "Egészség", "Ruházat", "Étterem", "Fizetés", "Lakbér", "Egyéb"]
TRANSACTIONS = [
    ("SPAR MAGYARORSZAG KFT 8.430 HUF", "Élelmiszer"), ("MOL TOLTOALLOMAS 15.200 HUF", "Közlekedés"),
    ("NETFLIX.COM 4.490 HUF", "Szórakozás"), ("DM DROGERIE MARKT 3.120 HUF", "Egészség"),
    ("BKK BERLET 8.950 HUF", "Közlekedés"), ("ELMU-EMASZ VILLANY 12.300 HUF", "Rezsi"),
    ("H&M HENNES 19.990 HUF", "Ruházat"), ("WOLT HU 6.780 HUF", "Étterem"),
    ("MUNKABER JOVAIRAS +685.000 HUF", "Fizetés"), ("LIDL 5.640 HUF", "Élelmiszer"),
    ("BENU GYOGYSZERTAR 2.890 HUF", "Egészség"), ("ALBERLET OKTOBER -220.000 HUF", "Lakbér"),
]


def run_categorize():
    listing = "\n".join(f"{i + 1}. {t}" for i, (t, _) in enumerate(TRANSACTIONS))
    prompt = ("Sorold be a tranzakciókat ezek közül a kategóriák közül: " + ", ".join(CATEGORIES) +
              '. Válaszolj KIZÁRÓLAG egy JSON listával, elemei {"tx": <sorszám 1-től>, "category": <kategória>}.\n\n' + listing)
    r = chat([{"role": "user", "content": prompt}], 600)
    j = parse_json(content(r))
    got = {}
    if isinstance(j, list):
        got = {int(e.get("tx", 0)): e.get("category") for e in j if isinstance(e, dict) and str(e.get("tx", "")).isdigit()}
    misses = [{"tx": t, "expected": c, "got": got.get(i + 1)} for i, (t, c) in enumerate(TRANSACTIONS) if got.get(i + 1) != c]
    return {"valid_json": isinstance(j, list), "correct": len(TRANSACTIONS) - len(misses), "total": len(TRANSACTIONS),
            "misses": misses, **timing(r)}


TOOLS = [{"type": "function", "function": {
    "name": "get_account_balance", "description": "Visszaadja egy bankszámla aktuális egyenlegét.",
    "parameters": {"type": "object", "properties": {"account": {"type": "string", "enum": ["folyószámla", "megtakarítás"]}},
                   "required": ["account"]}}}]


def run_tool_call():
    question = {"role": "user", "content": "Mennyi pénz van a megtakarítási számlámon?"}
    r = chat([question], 200, tools=TOOLS)
    msg = r["choices"][0]["message"]
    calls = msg.get("tool_calls") or []
    if not calls:
        return {"tool_called": False, "answer": msg.get("content")}
    args = parse_json(calls[0]["function"]["arguments"]) or {}
    result = {"role": "tool", "tool_call_id": calls[0].get("id", "0"), "content": json.dumps({"balance_huf": 1250000})}
    r2 = chat([question, msg, result], 150, tools=TOOLS)
    return {"tool_called": True, "name": calls[0]["function"]["name"], "args": args,
            "args_ok": args.get("account") == "megtakarítás", "final_answer": content(r2)}


def main():
    models = json.load(urllib.request.urlopen(urllib.request.Request(BASE + "/models", headers=HEADERS), timeout=30))
    out = {"model": models["data"][0]["id"], "started": time.strftime("%Y-%m-%dT%H:%M:%S")}
    for name, fn in [("speed", run_speed), ("long_prompt", run_long_prompt), ("hungarian", run_hungarian),
                     ("paperless", run_paperless), ("categorize", run_categorize), ("tool_call", run_tool_call)]:
        out[name] = fn()
    out["finished"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    print(json.dumps(out, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
