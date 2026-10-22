"""Deliver verified ACaM media actually released by the authors.
This is NOT the complete official benchmark: missing originals remain explicit
quarantine records, never synthetic replacements or training examples.
"""
from pathlib import Path
p=Path(__file__).with_name('curate_acam.py')
s=p.read_text()
needle="assert not unmatched and not badanswers and summary['invalid_media']==0,summary"
assert s.count(needle)==1
replacement='''
blocked=[]
for u in unmatched:
 source_rows=[json.loads(line) for line in (root/'native'/u['file']).read_text().splitlines() if line.strip()]
 native=source_rows[u['row']]
 blocked.append({**u,'native_annotation':native,'status':'quarantine','training_eligible':False,'official_evaluation_eligible':False,'reason':'native_media_not_resolved_from_author_released_archives','published_explanation':'ACaM authors state 454 CameraBench originals are not redistributed; CameraBench publicly offers GIF previews, originals by request. No GIF replacement was performed.'})
write_json(root/'blocked_original_media.json',blocked)
summary['complete_official_benchmark']=False if blocked else True
summary['all_annotation_rows_accounted_for']=len(records)+len(blocked)==summary['annotation_rows']
summary['unavailable_original_rows']=len(blocked)
summary['scope']='available author-released native videos plus complete annotations and explicit missing-original quarantine'
summary['missing_media_substituted']=0
summary['human_operator_utility_labels']=0
write_json(root/'QA.json',summary)
assert not badanswers and summary['invalid_media']==0 and summary['all_annotation_rows_accounted_for'],summary
'''
s=s.replace(needle,replacement)
last="package(root,'acam-curated-complete-test')"
assert s.count(last)==1
s=s.replace(last,"""
(root/'README_RU.txt').write_text('ACaM — только фактически доступная часть официального теста.\\nВсе исходные аннотации сохранены. Неразрешённые original-video ссылки находятся в blocked_original_media.json и исключены из evaluation, а не заменены GIF. Это НЕ полный официальный benchmark.\\nrecords.jsonl содержит только однозначно связанные с полученными native-видеофайлами задания; training_eligible=false для всех.\\nПроизводные видео: до 16 кадров, max320, H264 CRF20; аудио удалено. Это preprocessing-вариант теста, не неизменённый full-video benchmark. Все производные полностью декодированы. Оба native ZIP скачаны полностью и каждый member прочитан с проверкой CRC; raw ZIP не включены в компактную поставку. Pinned upstream revision и хеши сохранены.\\nПользовательский intent времени съёмки, причинный эффект рекомендаций и человеческая полезность CameraCoach не размечены. Ограничения источников сохраняются.\\n')
package(root,'acam-available-test-v18')
""")
exec(compile(s,str(p),'exec'),{'__name__':'__main__','__file__':str(p)})
