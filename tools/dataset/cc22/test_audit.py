#!/usr/bin/env python3
"""Fixture-only QA for the CameraCoach HTML template and offline embedder.

All pictures and annotations created here are arbitrary test fixtures.
They must not be counted as real CameraCoach dataset evidence.
"""
import collections
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from PIL import Image
import build_embedded_audit as B

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def fixture(root: Path):
    (root/"media").mkdir(parents=True)
    colors=[(48,80,140),(56,88,145),(63,95,153),(40,143,117)]
    paths=["media/t_0.png","media/t_1.png","media/t_2.png","media/after.png"]
    for name,color in zip(paths,colors):
        Image.new("RGB",(256,192),color).save(root/name)
    checks={name:sha(root/name) for name in paths}
    all_rows=[];all_verifiers=[]
    for source,count,groups,splits,per_group in [
       ("v19",3353,479,[312,56,111],7),
       ("v20",1536,128,[80,24,24],12)]:
        split_choices=(["train"]*splits[0]+["validation"]*splits[1]+["test"]*splits[2])
        for g in range(groups):
            scene=("cc20-t-%05d"%g) if source=="v20" else ("fixture-v19-%04d"%g)
            origin=(source+":"+scene)
            split=split_choices[g]
            if source=="v20":
                for j in range(2):
                    parameters=[[0.,0.,0.,0.,0.,0.,1.,0.,0.,0.,0.,0.,1.,0.,1.],[.3,0.,0.,0.,0.,0.,1.,0.,0.,0.,0.,0.,1.,1.,1.]][j]
                    all_verifiers.append({
                      "scene_id":scene,"origin_group":origin,
                      "action":{"id":"keep" if j==0 else "truck_0.3","dx_m":parameters[0],"yaw_deg":0.,"focal_factor":1.,"cost":float(j)},
                      "measurements":[[{"visible_surface_fraction":.8,"fully_in_frame":True} for _ in range(2)] for _ in range(5)],
                      "path_feasible":True,"times":[0,.25,.5,.75,1.],
                      "after_media":[{"path":"media/after.png","sha256":checks["media/after.png"],"t_s":1.}]})
            for k in range(per_group):
                dec=["recommend","keep","ask","abstain"][k%4]
                actions=[
                  {"native_index":0,"parameters":[0.,0.,0.,0.,0.,0.,1.,0.,0.,0.,0.,0.,1.,0.,1. if source=="v20" else 0.],"available":True},
                  {"native_index":1,"parameters":[.3,0.,0.,0.,0.,0.,1.,0.,0.,0.,0.,0.,1.,1.,1. if source=="v20" else 0.],"available":True},
                ]
                target=1 if dec=="recommend" else 0 if dec=="keep" else None
                rid=scene+":"+str(k%2)+":goal_"+str(k)
                all_rows.append({
                  "schema":"cameracoach.unified-actions.v21.1","record_id":source+":"+rid,"origin_group":origin,"split":split,
                  "observations":{
                    "history":[{"path":paths[i],"time_s":[-.4,-.2,0.][i],"sha256":checks[paths[i]]} for i in range(3)],
                    "tap_xy":[.5,.5],"goal_known":dec not in ["ask"],"preserve_dark_tone":False,
                    "goal":[{"metric":"visible_surface_sample_fraction" if source=="v20" else "visible_pixel_fraction","minimum":.5,"maximum":None,"scope":"endpoint"}] if dec!="ask" else [],
                    "optics":[1.,0.,0.],"optics_known":[True,False,False],
                    "actions":actions,"observation_cutoff_s":0.
                  },
                  "targets":{"decision":dec,"chosen_index":target,"success":[True,True],"success_known":[True,True],"decision_known":True,"human_utility":None},
                  "provenance":{"native_source":source,"native_record_id":rid,"label_authority":"UNIT_FIXTURE_NOT_REAL"}
                })
    assert len(all_rows)==4889
    assert collections.Counter(r["split"] for r in all_rows)=={"train":3144,"validation":680,"test":1065}
    with (root/"records.jsonl").open("w",encoding="utf-8") as f:
        for r in all_rows:f.write(json.dumps(r,ensure_ascii=False)+"\n")
    with (root/"verifier_sequences.jsonl").open("w",encoding="utf-8") as f:
        for r in all_verifiers:f.write(json.dumps(r,ensure_ascii=False)+"\n")

def main():
    here=Path(__file__).parent
    with tempfile.TemporaryDirectory(prefix="cc22-fixture-") as directory:
        root=Path(directory);folder=root/"TEST_FIXTURES_ONLY";fixture(folder)
        out=root/"QA_TEST_EMBEDDED.html"
        subprocess.run([sys.executable,str(here/"build_embedded_audit.py"),
          "--dataset",str(folder),"--template",str(here/"CameraCoach_Quality_Audit.html"),
          "--out",str(out),"--count","180","--contrasts","30"],check=True,stdout=subprocess.DEVNULL)
        html=out.read_text(encoding="utf-8")
        match=re.search(r'<script id="embedded-data" type="application/json">(.*?)</script>',html,re.S)
        assert match, "Missing embedded sample"
        payload=json.loads(match.group(1))
        assert len(payload["sample_ids"])==180 and payload["sample_unique_origins"]==180
        assert len(payload["records"])>=180 and len(payload["images"])==4
        assert len(payload["verifier_sequences"])>=200
        assert all(x.startswith("data:image/jpeg;base64,") for x in payload["images"].values())
        assert not re.search(r'<script[^>]*\bsrc=',html), "External JS is forbidden"
        assert not re.search(r'<link[^>]*\bhref=.*\.css',html), "External CSS is forbidden"
        assert "BEGIN PRIVATE KEY" not in html and "PRIVATE_transport_key_DO_NOT_PUBLISH.pem" not in payload["images"]
        assert json.loads(out.with_suffix(".receipt.json").read_text())["new_training_rows"]==0
        print("CC22_UNIT_FIXTURE_PASS "+json.dumps({
          "fixture_only":True,"verified_rows":len(payload["records"]),
          "primary_cases":len(payload["sample_ids"]),"unique_scene_groups":payload["sample_unique_origins"],
          "embedded_image_files":len(payload["images"]),"runtime_model_calls":0,
          "real_cameracoach_media_in_this_test":0,
          "source_html_bytes":(here/"CameraCoach_Quality_Audit.html").stat().st_size
        }))
        # Optionally run real browser E2E with Playwright if installed.
        try:
            from playwright.sync_api import sync_playwright
        except ImportError:
            print("CC22_BROWSER_E2E_SKIPPED_playwright_unavailable")
            return
        with sync_playwright() as p:
            browser=p.chromium.launch(headless=True,args=["--no-sandbox"])
            page=browser.new_page(viewport={"width":1400,"height":900},accept_downloads=True)
            page.goto(out.as_uri())
            page.wait_for_selector("#workspace:not(.hidden)",timeout=20000)
            assert page.locator("#caseList button.case").count()==180
            assert page.locator("#statCases").inner_text()=="180"
            assert page.locator("#detail .frame img").count()>=4
            page.locator('#detail button[data-rating="wrong"]').click()
            assert "1" in page.locator("#statDone").inner_text()
            with page.expect_download() as info:
                page.locator("#exportJson").click()
            downloaded=info.value
            saved=root/"audit-result.json";downloaded.save_as(saved)
            data=json.loads(saved.read_text())
            assert data["sample_count"]==180
            assert sum(x["review_rating"]=="wrong" for x in data["reviews"])==1
            page.locator("#blindBtn").click()
            assert "вкл." in page.locator("#blindBtn").inner_text()
            # Regular folder import is tested with the same fixture, in a second page.
            page2=browser.new_page(viewport={"width":1350,"height":900})
            page2.goto((here/"CameraCoach_Quality_Audit.html").as_uri())
            page2.locator("#folderInput").set_input_files(str(folder))
            page2.wait_for_selector("#workspace:not(.hidden)",timeout=30000)
            assert page2.locator("#caseList button.case").count()==180
            assert page2.locator("#detail img").count()>=3
            browser.close()
            print("CC22_BROWSER_E2E_PASS "+json.dumps({"embedded_import":True,"folder_import":True,"notes_export":True,"blind_mode":True,"real_cameracoach_media":0}))

if __name__=="__main__":
    main()
