"""Generate isolated gull calls. Key comes from environment or stdin, never saved.

Requires numpy and soundfile. Existing clips are kept to avoid repeat charges.
"""
import io
import json
import os
import sys
import hashlib
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError
import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'resources/audio/wildlife/gulls'
RAW = ROOT / '.codex/gull-audio-raw'
CALLS = [
    ('contact_01', 2.5, 'A single adult European herring gull gives one clear mid-pitched kyow contact call.', -19),
    ('contact_02', 3.0, 'One adult herring gull gives two short nasal kee-ah contact calls, separated by a brief pause.', -19),
    ('contact_03', 2.5, 'One large adult herring gull makes a low raspy yaw call with a slightly descending ending.', -19),
    ('contact_04', 3.0, 'One herring gull gives a bright rising kee-ow and a softer answering note from the same bird.', -19),
    ('long_01', 4.5, 'One adult herring gull gives its characteristic rhythmic laughing long call: a few slow notes then a quick descending series.', -18),
    ('long_02', 4.5, 'A single adult European herring gull makes a throaty long call, beginning low and rising into several clear laughing cries.', -18),
    ('long_03', 4.0, 'One adult herring gull delivers a high clear territorial long call with five unevenly spaced laughing notes.', -18),
    ('quiet_01', 3.0, 'One resting adult herring gull makes two gentle low clucking contact notes, relaxed and close.', -26),
    ('quiet_02', 3.0, 'One resting herring gull gives a soft nasal mewing murmur and a short quiet chuckle.', -26),
    ('quiet_03', 3.0, 'One relaxed herring gull gives three subdued throaty auk-auk contact notes with small pauses.', -26),
    ('alarm_01', 2.5, 'One startled adult herring gull gives two sharp urgent kek-kek alarm barks.', -17),
    ('alarm_02', 3.0, 'One adult herring gull gives a sudden harsh alarm cry followed by three short rapid warning notes.', -17),
]


def main():
    key = os.environ.get('ELEVENLABS_API_KEY') or sys.stdin.read().strip()
    if not key:
        raise SystemExit('Missing ElevenLabs API key')
    DEST.mkdir(parents=True, exist_ok=True)
    RAW.mkdir(parents=True, exist_ok=True)
    receipt_path = DEST / 'generation.json'
    receipt = json.loads(receipt_path.read_text(encoding='utf-8')) if receipt_path.exists() else {
        'provider': 'ElevenLabs', 'model': 'eleven_text_to_sound_v2',
        'api_documentation': 'https://elevenlabs.io/docs/api-reference/text-to-sound-effects/convert',
        'entries': []}
    existing = {row['id']: row for row in receipt['entries']}
    for name, duration, description, target_db in CALLS:
        target = DEST / (name + '.wav')
        if target.exists() and name in existing:
            print('KEEP', name, flush=True)
            continue
        prompt = description + ' Realistic natural bird sound, isolated dry close microphone recording of ONE bird only. No flock, ocean, wind, music, speech, human imitation, echo or other background sounds. Begin and end with a little silence.'
        raw_path = RAW / (name + '.mp3')
        meta_path = RAW / (name + '.json')
        if raw_path.exists():
            raw = raw_path.read_bytes()
            meta = json.loads(meta_path.read_text(encoding='utf-8'))
        else:
            payload = json.dumps({'text': prompt, 'duration_seconds': duration, 'loop': False,
                'prompt_influence': 0.4, 'model_id': 'eleven_text_to_sound_v2'}).encode()
            request = Request('https://api.elevenlabs.io/v1/sound-generation?output_format=mp3_44100_128',
                data=payload, headers={'xi-api-key': key, 'Content-Type': 'application/json'})
            try:
                with urlopen(request, timeout=100) as response:
                    raw = response.read()
                    meta = {'credits': response.headers.get('character-cost'),
                        'request_id': response.headers.get('request-id')}
            except HTTPError as error:
                # No request headers or secrets in diagnostics.
                detail = json.loads(error.read().decode()).get('detail', {})
                print('GENERATION_FAILED', name, error.code, detail, flush=True)
                raise SystemExit(1)
            raw_path.write_bytes(raw)
            meta_path.write_text(json.dumps(meta), encoding='utf-8')
        samples, rate = sf.read(io.BytesIO(raw), dtype='float32', always_2d=True)
        mono = samples.mean(axis=1)
        mono -= np.mean(mono)
        peak = float(np.max(np.abs(mono)))
        if peak < 0.005 or not np.isfinite(mono).all():
            raise SystemExit('Generated clip failed signal check: ' + name)
        active = np.flatnonzero(np.abs(mono) > max(0.002, peak * 0.015))
        if active.size:
            margin = int(rate * 0.07)
            mono = mono[max(0, active[0] - margin):min(len(mono), active[-1] + margin + 1)]
        rms = float(np.sqrt(np.mean(mono ** 2)))
        gain = min(10 ** (target_db / 20) / max(rms, 1e-6), 0.78 / max(peak, 1e-6))
        mono *= gain
        fade = min(int(rate * 0.015), len(mono) // 4)
        mono[:fade] *= np.linspace(0, 1, fade)
        mono[-fade:] *= np.linspace(1, 0, fade)
        sf.write(target, mono, rate, subtype='PCM_16')
        row = {'id': name, 'path': 'wildlife/gulls/' + target.name, 'prompt': prompt,
            'description': description, 'loop': False, 'channels': 1, 'sample_rate': rate,
            'duration_seconds': duration, 'actual_seconds': len(mono) / rate,
            'peak_db': float(20 * np.log10(np.max(np.abs(mono)))),
            'rms_db': float(20 * np.log10(np.sqrt(np.mean(mono ** 2)))),
            'sha256': hashlib.sha256(target.read_bytes()).hexdigest(), **meta}
        existing[name] = row
        receipt['entries'] = list(existing.values())
        receipt_path.write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
        print('GENERATED', name, round(row['actual_seconds'], 2), 'seconds; credits', meta['credits'], flush=True)
    manifest_path = ROOT / 'resources/audio/manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    paths = {r['path'] for r in receipt['entries']}
    manifest['entries'] = [r for r in manifest['entries'] if r['path'] not in paths]
    for row in receipt['entries']:
        manifest['entries'].append({**row, 'bus': 'Ambience', 'status': 'connected',
            'trigger': 'Individual gull spatial call schedule / disturbance',
            'review': 'Mono signal, level and duration checked; listening review in gull workshop'})
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    envelopes = {}
    for clip in DEST.glob('*.wav'):
        samples, rate = sf.read(clip, dtype='float32')
        stride = round(rate / 50)
        envelopes[clip.stem] = [round(float(np.clip((np.sqrt(np.mean(samples[i:i+stride] ** 2)) - .005) * 12, 0, 1)), 4)
            for i in range(0, len(samples), stride)]
    (DEST / 'envelopes.json').write_text(json.dumps(envelopes, separators=(',', ':')) + '\n', encoding='utf-8')
    print('GULL_CALL_LIBRARY', len(receipt['entries']), 'clips', flush=True)


if __name__ == '__main__':
    main()
