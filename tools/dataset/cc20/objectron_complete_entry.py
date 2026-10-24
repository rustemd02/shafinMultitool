"""Execute the frozen native-frame acquisition with the portable reader."""
from pathlib import Path
import objectron_native_complete as O
import native_reader as R
from real_common import digest
O.tensors=R.video_batches
original_finish=O.finish

def finish(root,label,summary):
    summary['portable_reader_sha256']=digest(Path(R.__file__))
    summary['actual_reader_imports']='numpy, Pillow, PyAV and Python standard library only; no model or network'
    p=root/'DATASET_CARD_RU.md';text=p.read_text()
    text=text.replace('Потоковый tensors() в reproduction_cc20/objectron_native_complete.py','Потоковый batches() в reproduction_cc20/native_reader.py')
    p.write_text(text)
    return original_finish(root,label,summary)
O.finish=finish
if __name__=='__main__':O.main()
