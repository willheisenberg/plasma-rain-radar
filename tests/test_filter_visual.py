#!/usr/bin/env python3
import sys
import os
import urllib.request
import time
from PIL import Image

# Known DWD rain colors (RGB)
RAIN_COLORS = [
    (51, 255, 255), (26, 204, 154), (1, 153, 52), (77, 179, 27), (153, 204, 1),
    (204, 230, 1), (255, 255, 1), (255, 196, 1), (255, 137, 1), (255, 69, 1),
    (254, 0, 0), (229, 0, 76), (204, 0, 152), (102, 0, 203), (0, 0, 254),
]

def check_pixel(r, g, b, a, gray_tolerance=0.03, pink_diff=0.19, pink_min=0.01, pink_g_gap=0.02):
    rf, gf, bf = r / 255.0, g / 255.0, b / 255.0
    
    # 1. Gray check
    is_gray = (abs(rf - gf) <= gray_tolerance and 
               abs(rf - bf) <= gray_tolerance and 
               abs(gf - bf) <= gray_tolerance) and (a > 0)
    
    # 2. Pink check
    minRB = min(rf, bf)
    is_pink = (abs(rf - bf) <= pink_diff) and (minRB > pink_min) and (gf < minRB - pink_g_gap)
    
    # 3. Blend check
    is_blend = (minRB > 0.3) and (gf > 0.05)
    
    return is_gray, is_pink, is_blend

def main():
    import argparse
    parser = argparse.ArgumentParser(description="Test and calibrate radar image cleaning parameters.")
    parser.add_argument("--gray-tol", type=float, default=0.03, help="Max difference between R, G, B for gray (default: 0.03)")
    parser.add_argument("--pink-diff", type=float, default=0.19, help="Max difference between R and B for pink (default: 0.19)")
    parser.add_argument("--pink-min", type=float, default=0.01, help="Min brightness of R and B for pink (default: 0.01)")
    parser.add_argument("--pink-gap", type=float, default=0.02, help="How much lower Green must be than min(R,B) (default: 0.02)")
    parser.add_argument("--input", type=str, help="Path to input image (if empty, downloads a live frame)")
    parser.add_argument("--output", type=str, default="cleaned_test.png", help="Path to save output cleaned image")
    
    args = parser.parse_args()
    
    # Get image
    img_path = args.input
    if not img_path:
        img_path = "live_frame.gif"
        print("Downloading a live frame from DWD...")
        # Get timestamp rounded to 5 mins minus 10 minutes delay
        now = int(time.time()) - 600
        base = (now // 300) * 300
        ts = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(base))
        url = (
            f"https://maps.dwd.de/geoserver/ows?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap"
            f"&LAYERS=dwd:Niederschlagsradar&STYLES=&CRS=EPSG:3857"
            f"&BBOX=222638.98,5621521.49,2115070.32,7673967.65"
            f"&WIDTH=800&HEIGHT=868&FORMAT=image/gif&TRANSPARENT=TRUE&TIME={ts}"
        )
        try:
            urllib.request.urlretrieve(url, img_path)
            print(f"✓ Saved live frame to {img_path}")
        except Exception as e:
            print(f"Failed to download live frame: {e}")
            sys.exit(1)

    print(f"Processing {img_path}...")
    try:
        img = Image.open(img_path).convert("RGBA")
    except Exception as e:
        print(f"Error opening image {img_path}: {e}")
        sys.exit(1)
        
    pixels = img.load()
    w, h = img.size
    
    removed_gray = 0
    removed_pink = 0
    
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
                
            is_gray, is_pink, is_blend = check_pixel(
                r, g, b, a, 
                gray_tolerance=args.gray_tol,
                pink_diff=args.pink_diff,
                pink_min=args.pink_min,
                pink_g_gap=args.pink_gap
            )
            
            if is_gray:
                pixels[x, y] = (0, 0, 0, 0)
                removed_gray += 1
            elif is_pink or is_blend:
                pixels[x, y] = (0, 0, 0, 0)
                removed_pink += 1
                
    img.save(args.output)
    print(f"\nResults with current parameters:")
    print(f"  Removed Gray Pixels: {removed_gray}")
    print(f"  Removed Pink/Blended Pixels: {removed_pink}")
    print(f"  Cleaned image saved to: {args.output}")
    
    # Safety Check: Verify against known rain colors
    print("\nSafety check on official DWD rain colors:")
    safe = True
    for r, g, b in RAIN_COLORS:
        is_gray, is_pink, is_blend = check_pixel(
            r, g, b, 255, 
            gray_tolerance=args.gray_tol,
            pink_diff=args.pink_diff,
            pink_min=args.pink_min,
            pink_g_gap=args.pink_gap
        )
        if is_gray or is_pink or is_blend:
            reason = "GRAY" if is_gray else ("PINK" if is_pink else "BLEND")
            print(f"  ❌ DWD Rain color ({r:3d},{g:3d},{b:3d}) would be REMOVED as {reason}!")
            safe = False
            
    if safe:
        print("  ✅ All DWD rain colors are safe and will NOT be removed.")
    else:
        print("  ⚠️ Warning: These parameters will filter out real rain data!")

if __name__ == "__main__":
    main()
