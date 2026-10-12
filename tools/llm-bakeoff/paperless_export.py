"""Paperless dokumentumminta exportja a valós adatos bake-offhoz — csak olvas, semmit nem ír.

A paperless podban, a Django shellben fut:
  kubectl exec -i -n selfhosted deploy/paperless -- python3 manage.py shell < tools/llm-bakeoff/paperless_export.py
Egyetlen JSON sort ír ki (EXPORT: előtaggal): a legutóbbi dokumentumok szövege és jelenlegi metaadatai, valamint a választható listák.
"""
import json

from documents.models import Correspondent, Document, DocumentType, Tag

SAMPLE_SIZE = 15
MAX_CHARS = 4000
AI_TAGS = {"AI-processing", "AI-OCR"}

docs = (Document.objects.select_related("correspondent", "document_type").prefetch_related("tags")
        .exclude(content="").order_by("-added")[:SAMPLE_SIZE])
payload = {
    "correspondents": sorted(Correspondent.objects.values_list("name", flat=True)),
    "document_types": sorted(DocumentType.objects.values_list("name", flat=True)),
    "tags": sorted(t for t in Tag.objects.values_list("name", flat=True) if t not in AI_TAGS),
    "documents": [{
        "id": d.id,
        "content": d.content[:MAX_CHARS],
        "title": d.title,
        "correspondent": d.correspondent.name if d.correspondent else None,
        "document_type": d.document_type.name if d.document_type else None,
        "created": d.created.isoformat()[:10] if d.created else None,
        "tags": sorted(t.name for t in d.tags.all() if t.name not in AI_TAGS),
    } for d in docs],
}
print("EXPORT:" + json.dumps(payload, ensure_ascii=False))
