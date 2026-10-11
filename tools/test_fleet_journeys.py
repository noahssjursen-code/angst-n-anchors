"""Run every non-draft stock vessel in an isolated Godot world process.

python tools/test_fleet_journeys.py --godot PATH [--vessel ID] [--cycles 2]
Report files and every rendered capture go in the machine screenshot archive.
"""
import argparse
import datetime
import json
from pathlib import Path
import re
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--vessel', action='append', default=[])
    parser.add_argument('--cycles', type=int, default=2)
    parser.add_argument('--timeout', type=int, default=1200)
    parser.add_argument('--seed', type=int, default=424242)
    parser.add_argument('--speed', type=float, default=8.0)
    parser.add_argument('--headless', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    archive = Path.home() / 'Pictures' / 'machinescreenshots'
    output = archive / ('fleet-suite-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
    output.mkdir(parents=True)
    presets = []
    for path in sorted((root / 'resources/data/vessels/prebuilt').glob('*.json')):
        data = json.loads(path.read_text(encoding='utf-8-sig'))
        if not data.get('draft', False):
            presets.append((data['id'], path))
    if args.vessel:
        unknown = set(args.vessel) - {p[0] for p in presets}
        if unknown:
            parser.error('Unknown/non-stock vessel IDs: ' + ', '.join(sorted(unknown)))
        presets = [p for p in presets if p[0] in args.vessel]
    results = []
    for vessel_id, path in presets:
        log = output / (path.stem + '.log')
        cmd = [args.godot, '--path', str(root)]
        cmd += ['--headless'] if args.headless else ['--windowed', '--resolution', '1280x720']
        cmd += ['tests/fleet_world_journey.tscn', '--', '--shipyard-playtest',
                '--vessel=' + vessel_id, '--cycles=' + str(max(1, args.cycles)),
                '--seed=' + str(args.seed), '--speed=' + str(args.speed)]
        print('Testing', vessel_id, flush=True)
        timed_out = False
        with log.open('w', encoding='utf-8') as stream:
            process = subprocess.Popen(cmd, cwd=root, stdout=stream, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + args.timeout
            while process.poll() is None:
                time.sleep(.5)
                text = log.read_text(encoding='utf-8', errors='replace')
                fatal = 'Failed to load script "res://tests/fleet_world_journey.gd"' in text
                timed_out = time.monotonic() >= deadline
                if fatal or timed_out:
                    if sys.platform == 'win32':
                        subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
                    else:
                        process.kill()
                    break
            exit_code = process.wait(timeout=10)
        text = log.read_text(encoding='utf-8', errors='replace')
        reports = re.findall(r'FLEET REPORT (.+/report\.json) (\w+)', text)
        errors = [line for line in text.splitlines() if 'SCRIPT ERROR:' in line or line.startswith('ERROR:')]
        passed = exit_code == 0 and bool(reports) and reports[-1][1] == 'passed' and not errors
        result = {'vessel': vessel_id, 'passed': passed, 'exit_code': exit_code,
                  'timeout': timed_out, 'engine_errors': errors[:20], 'log': str(log),
                  'report': reports[-1][0] if reports else None}
        results.append(result)
        (output / 'summary.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
        print('PASS' if passed else 'FAIL', vessel_id, flush=True)
    print('Fleet suite report:', output / 'summary.json', flush=True)
    return 0 if results and all(r['passed'] for r in results) else 1


if __name__ == '__main__':
    sys.exit(main())
