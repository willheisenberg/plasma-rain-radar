import unittest

# All known DWD rain colors from the legend (RGB, all alpha=255)
RAIN_COLORS = [
    (51, 255, 255),   # 0.1 - 0.2 mm/h (Cyan)
    (26, 204, 154),   # 0.2 - 0.4 mm/h (Green-cyan)
    (1, 153, 52),     # 0.4 - 1.0 mm/h (Dark green)
    (77, 179, 27),    # 1.0 - 2.0 mm/h (Light green)
    (153, 204, 1),    # 2.0 - 4.0 mm/h (Yellow-green)
    (204, 230, 1),    # 4.0 - 8.0 mm/h (Yellow)
    (255, 255, 1),    # 8.0 - 12.0 mm/h (Bright yellow)
    (255, 196, 1),    # 12.0 - 15.0 mm/h (Orange)
    (255, 137, 1),    # 15.0 - 25.0 mm/h (Dark orange)
    (255, 69, 1),     # 25.0 - 35.0 mm/h (Red-orange)
    (254, 0, 0),      # 35.0 - 45.0 mm/h (Red)
    (229, 0, 76),     # 45.0 - 75.0 mm/h (Crimson)
    (204, 0, 152),    # 75.0 - 100.0 mm/h (Magenta)
    (102, 0, 203),    # 100.0 - 150.0 mm/h (Purple)
    (0, 0, 254),      # > 150 mm/h (Blue)
]

# Known DWD border colors and backgrounds
GRAY_COLORS = [(126, 126, 126), (128, 124, 128)]
PINK_COLORS = [
    (251, 0, 255), (252, 0, 255), (255, 0, 255), (165, 85, 167),
    (247, 0, 255), (226, 32, 255), (159, 96, 159), (141, 114, 141),
]

def should_discard(r, g, b, a=255):
    rf, gf, bf = r / 255.0, g / 255.0, b / 255.0
    
    # 1. Gray check
    is_gray = (abs(rf - gf) <= 0.03 and 
               abs(rf - bf) <= 0.03 and 
               abs(gf - bf) <= 0.03) and (a > 0)
    if is_gray:
        return True
        
    # 2. Pink check
    minRB = min(rf, bf)
    is_pink = (abs(rf - bf) <= 0.19) and (minRB > 0.01) and (gf < minRB - 0.02)
    if is_pink:
        return True
        
    # 3. Blend check
    is_blend = (minRB > 0.3) and (gf > 0.05)
    if is_blend:
        return True
        
    return False

class TestShaderLogic(unittest.TestCase):
    def test_rain_colors_preserved(self):
        """Verify that all official DWD rain colors are preserved."""
        for r, g, b in RAIN_COLORS:
            with self.subTest(color=(r, g, b)):
                self.assertFalse(should_discard(r, g, b), f"Rain color ({r},{g},{b}) was incorrectly discarded!")

    def test_gray_backgrounds_discarded(self):
        """Verify that gray background colors are discarded."""
        for r, g, b in GRAY_COLORS:
            with self.subTest(color=(r, g, b)):
                self.assertTrue(should_discard(r, g, b), f"Gray color ({r},{g},{b}) was not discarded!")

    def test_pink_borders_discarded(self):
        """Verify that pink border colors are discarded."""
        for r, g, b in PINK_COLORS:
            with self.subTest(color=(r, g, b)):
                self.assertTrue(should_discard(r, g, b), f"Pink border ({r},{g},{b}) was not discarded!")

    def test_blended_borders_discarded(self):
        """Verify that blends of pink with cyan, green, and yellow are discarded."""
        pink_color = (255, 0, 255)
        # Test blending with cyan/green/yellow rain colors
        test_rain_baselines = [
            (51, 255, 255),  # Cyan
            (26, 204, 154),  # Green
            (77, 179, 27),   # Light Green
            (204, 230, 1),   # Yellow
        ]
        for rc in test_rain_baselines:
            # 50% blend
            r = int(pink_color[0] * 0.5 + rc[0] * 0.5)
            g = int(pink_color[1] * 0.5 + rc[1] * 0.5)
            b = int(pink_color[2] * 0.5 + rc[2] * 0.5)
            with self.subTest(blend=f"50% blend of pink and {rc}"):
                self.assertTrue(should_discard(r, g, b), f"Blended boundary color ({r},{g},{b}) was not discarded!")

if __name__ == "__main__":
    unittest.main()
