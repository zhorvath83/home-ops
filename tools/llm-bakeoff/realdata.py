"""Valós adatos bake-off: paperless és sure minta értékelése a helyi modellel — csak olvas, semmit nem ír vissza.

Az open-webui podban fut; a stdin a paperless_export.py és a sure_export.rb kimenetéből összefűzött JSON
({"paperless": ..., "sure": ...}). Egy JSON dokumentumot ír ki: "summary" (összesített metrikák) és
"details" (dokumentumonkénti/tranzakciónkénti összevetés, a felhasználó helyi átnézéséhez).
"""
import json
import os
import re
import sys
import time
import urllib.request

BASE = os.environ["OPENAI_API_BASE_URL"]
HEADERS = {"Authorization": f"Bearer {os.environ['OPENAI_API_KEY']}", "Content-Type": "application/json"}


def chat(messages, max_tokens=400, **extra):
    body = {"messages": messages, "max_tokens": max_tokens, "temperature": 0.1, **extra}
    req = urllib.request.Request(BASE + "/chat/completions", data=json.dumps(body).encode(), headers=HEADERS)
    return json.load(urllib.request.urlopen(req, timeout=1800))


def parse_json(text):
    m = re.search(r"\{.*\}|\[.*\]", text or "", re.S)
    try:
        return json.loads(m.group(0)) if m else None
    except ValueError:
        return None


def norm(value):
    return re.sub(r"\s+", " ", str(value or "")).strip().casefold()


def run_paperless(data):
    system = ("Magyar dokumentumokat dolgozol fel egy dokumentumkezelőben. Válaszolj KIZÁRÓLAG egy JSON objektummal: "
              "title (rövid magyar cím), correspondent (pontosan egy a listából, vagy null), document_type (pontosan egy a "
              "listából), created (a dokumentum kelte, YYYY-MM-DD), tags (0-3 elem, csak a listából).\n\n"
              f"Partnerek: {json.dumps(data['correspondents'], ensure_ascii=False)}\n"
              f"Dokumentumtípusok: {json.dumps(data['document_types'], ensure_ascii=False)}\n"
              f"Tagek: {json.dumps(data['tags'], ensure_ascii=False)}")
    details, seconds = [], []
    for doc in data["documents"]:
        t = time.time()
        r = chat([{"role": "system", "content": system}, {"role": "user", "content": doc["content"]}])
        seconds.append(time.time() - t)
        got = parse_json(r["choices"][0]["message"].get("content")) or {}
        got_tags = {norm(x) for x in got.get("tags") or [] if isinstance(x, str)}
        want_tags = {norm(x) for x in doc["tags"]}
        details.append({
            "id": doc["id"], "valid_json": bool(got),
            "correspondent_ok": norm(got.get("correspondent")) == norm(doc["correspondent"]),
            "type_ok": norm(got.get("document_type")) == norm(doc["document_type"]),
            "date_ok": got.get("created") == doc["created"],
            "tag_precision": len(got_tags & want_tags) / len(got_tags) if got_tags else None,
            "tag_recall": len(got_tags & want_tags) / len(want_tags) if want_tags else None,
            "current": {k: doc[k] for k in ("title", "correspondent", "document_type", "created", "tags")},
            "local": got, "prompt_s": round(r["timings"]["prompt_ms"] / 1000, 1),
        })
    n = len(details)

    def rate(key):
        return round(sum(d[key] for d in details) / n, 2)

    def avg(key):
        vals = [d[key] for d in details if d[key] is not None]
        return round(sum(vals) / len(vals), 2) if vals else None

    summary = {"docs": n, "valid_json": rate("valid_json"), "correspondent": rate("correspondent_ok"),
               "document_type": rate("type_ok"), "created": rate("date_ok"),
               "tag_precision": avg("tag_precision"), "tag_recall": avg("tag_recall"),
               "seconds_per_doc": round(sum(seconds) / n, 1)}
    return summary, details


def run_sure(data, batch=10):
    system = ("Banki tranzakciókat kategorizálsz. Minden tranzakcióhoz válassz PONTOSAN egy kategóriát a listából. "
              'Válaszolj KIZÁRÓLAG egy JSON listával, elemei {"tx": <sorszám>, "category": <kategória>}.\n\n'
              f"Kategóriák: {json.dumps(data['categories'], ensure_ascii=False)}")
    txs = data["transactions"]
    details = []
    for start in range(0, len(txs), batch):
        chunk = txs[start:start + batch]
        listing = "\n".join(f"{i + 1}. {t['name']} | {t['merchant'] or '-'} | {t['amount']} {t['currency']}"
                            for i, t in enumerate(chunk))
        r = chat([{"role": "system", "content": system}, {"role": "user", "content": listing}], 800)
        got = parse_json(r["choices"][0]["message"].get("content"))
        mapping = {}
        if isinstance(got, list):
            mapping = {int(e["tx"]): e.get("category") for e in got
                       if isinstance(e, dict) and str(e.get("tx", "")).isdigit()}
        for i, t in enumerate(chunk):
            details.append({"name": t["name"], "merchant": t["merchant"], "expected": t["category"],
                            "got": mapping.get(i + 1), "ok": norm(mapping.get(i + 1)) == norm(t["category"])})
    summary = {"transactions": len(details), "correct": sum(d["ok"] for d in details),
               "distinct_expected": len({d["expected"] for d in details})}
    return summary, details


ACCOUNTS = [{"id": "acc-1", "name": "Folyószámla"}, {"id": "acc-2", "name": "Megtakarítás"}]
TRANSACTIONS = {"acc-1": [{"date": "2026-10-03", "name": "SPAR", "category": "Élelmiszer", "amount": -8430},
                          {"date": "2026-10-07", "name": "LIDL", "category": "Élelmiszer", "amount": -5640},
                          {"date": "2026-10-09", "name": "MOL", "category": "Közlekedés", "amount": -15200},
                          {"date": "2026-09-28", "name": "TESCO", "category": "Élelmiszer", "amount": -12000}],
                "acc-2": []}
TOOLS = [
    {"type": "function", "function": {"name": "list_accounts", "description": "A felhasználó bankszámláinak listája.",
                                      "parameters": {"type": "object", "properties": {}}}},
    {"type": "function", "function": {
        "name": "get_transactions", "description": "Egy számla tranzakciói egy adott hónapban.",
        "parameters": {"type": "object", "properties": {
            "account_id": {"type": "string"}, "month": {"type": "string", "description": "YYYY-MM"}},
            "required": ["account_id", "month"]}}},
]


def call_tool(name, args):
    if name == "list_accounts":
        return ACCOUNTS
    if name == "get_transactions":
        return [t for t in TRANSACTIONS.get(args.get("account_id"), []) if t["date"].startswith(args.get("month", ""))]
    return {"error": f"unknown tool {name}"}


def run_multistep():
    messages = [{"role": "user", "content": "Mennyit költöttem 2026 októberében élelmiszerre a folyószámlámról?"}]
    calls = []
    for _ in range(6):
        msg = chat(messages, 400, tools=TOOLS)["choices"][0]["message"]
        messages.append(msg)
        if not msg.get("tool_calls"):
            answer = msg.get("content") or ""
            return {"tool_calls": calls, "answer": answer,
                    "correct_sum": "14070" in answer.replace(" ", "").replace(".", "").replace(" ", "")}
        for c in msg["tool_calls"]:
            args = parse_json(c["function"]["arguments"]) or {}
            calls.append({"name": c["function"]["name"], "args": args})
            messages.append({"role": "tool", "tool_call_id": c.get("id", "0"),
                             "content": json.dumps(call_tool(c["function"]["name"], args), ensure_ascii=False)})
    return {"tool_calls": calls, "answer": None, "correct_sum": False}


def main():
    data = json.load(sys.stdin)
    p_sum, p_det = run_paperless(data["paperless"])
    s_sum, s_det = run_sure(data["sure"])
    multi = run_multistep()
    print(json.dumps({"summary": {"paperless": p_sum, "sure": s_sum,
                                  "multistep": {"calls": [c["name"] for c in multi["tool_calls"]],
                                                "correct_sum": multi["correct_sum"]}},
                      "details": {"paperless": p_det, "sure": s_det, "multistep": multi}}, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
