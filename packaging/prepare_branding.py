#!/usr/bin/env python3
"""Resize the cleared, pre-lettered banner; no generated or third-party inputs."""
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
def main():
    source=ROOT/'docs/branding/kinegra-amp-banner.png'
    with Image.open(source) as image:
        image=image.convert('RGB')
        for name,size in [('tv_banner_320x180.png',(320,180)),('boot_splash_1280x720.png',(1280,720))]:
            image.resize(size,Image.Resampling.LANCZOS).save(ROOT/'app/assets/branding'/name,'PNG',optimize=True)
if __name__=='__main__': main()
