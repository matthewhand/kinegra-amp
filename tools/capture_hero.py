#!/usr/bin/env python3
"""Render a silent, synthetic-only hero animation from the current app source."""
from pathlib import Path
import argparse, os, subprocess, shutil, json, hashlib

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists():
        parser.error('Choose a new output directory')
    output.mkdir(parents=True)
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1', METHEXIS_SOURCE_TEST='1')
    env.pop('DISPLAY', None)
    preview = output / 'preview'
    subprocess.run(['python3', str(ROOT/'tools/build_preview.py'), '--godot', str(args.godot), '--output', str(preview)], env=env, check=True)
    app = preview / 'app'
    titles = [('Review sample 1','Prism Circuit'),('Review sample 2','Midnight Geometry'),('Review sample 3','Signal Garden'),('Review sample 4','Glass Horizon')]
    for path in (app/'scripts').glob('*.gd'):
        text=path.read_text()
        for old,new in titles:
            text=text.replace(old,new)
        path.write_text(text)
    shutil.copy2(ROOT/'tools/capture_hero.gd', app/'capture_hero.gd')
    frames=output/'frames'
    frames.mkdir()
    env['KINEGRA_AMP_HERO_FRAMES']=str(frames)
    for key,name in [('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache')]:
        target=output/'capture-state'/name
        target.mkdir(parents=True)
        env[key]=str(target)
    p=subprocess.run(['xvfb-run','-a',str(args.godot),'--path',str(app),'--audio-driver','Dummy','--script','res://capture_hero.gd'],env=env,capture_output=True,text=True,timeout=180)
    (output/'capture.log').write_text(p.stdout+p.stderr)
    if p.returncode or any(x in p.stdout+p.stderr for x in ['SCRIPT ERROR','Parse Error']):
        raise RuntimeError('Capture failed; inspect capture.log')
    assert len(list(frames.glob('frame-*.png')))==96
    font=ROOT/'app/assets/fonts/DejaVuSans.ttf'
    caption='STAGED DESKTOP PREVIEW - Generated audio and artwork - No live account or camera'
    filters=f"pad=iw:ih+40:0:0:color=0x091122,drawtext=fontfile='{font}':text='{caption}':fontcolor=0xcbd5e1:fontsize=16:x=16:y=h-28,split[a][b];[a]palettegen=stats_mode=diff:max_colors=256[p];[b][p]paletteuse=dither=sierra2_4a"
    gif=output/'kinegra-amp-hero-1.0.10.gif'
    subprocess.run(['ffmpeg','-hide_banner','-nostdin','-v','error','-threads','2','-framerate','6','-i',str(frames/'frame-%03d.png'),'-filter_complex',filters,'-map_metadata','-1','-an','-loop','0',str(gif)],check=True)
    (output/'hero.json').write_text(json.dumps({'application':'Kinegra Amp','version':'1.0.10','frames':96,'fps':6,'silent':True,'synthetic_only':True,'device_capture':False,'camera_or_account_access':False,'sha256':hashlib.sha256(gif.read_bytes()).hexdigest()},indent=2)+'\n')
    print('HERO_READY='+str(gif))

if __name__=='__main__': main()
