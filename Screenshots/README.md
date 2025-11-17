# App Store Subscription Screenshots

This folder contains subscription review screenshots required by Apple for in-app purchase review.

## Files

### pro-monthly-review.png
- **Purpose:** Review screenshot for Pro Monthly subscription ($1.99/month)
- **Dimensions:** 1024 x 1024 pixels
- **Format:** PNG, 72 dpi, RGB
- **Size:** ~495 KB
- **Shows:** App logo, $1.99 pricing, 4 Pro features with checkmarks

### pro-annual-review.png
- **Purpose:** Review screenshot for Pro Annual subscription ($19.99/year)
- **Dimensions:** 1024 x 1024 pixels
- **Format:** PNG, 72 dpi, RGB
- **Size:** ~512 KB
- **Shows:** App logo, "SAVE 17%" badge, $19.99 pricing, 4 Pro features with checkmarks

## Apple Requirements

These screenshots must meet Apple's exact specifications:
- ✅ Dimensions: 1024 x 1024 pixels (exactly)
- ✅ DPI: 72 dpi
- ✅ Color Space: RGB (not CMYK)
- ✅ Format: PNG or JPG
- ✅ Corners: No rounded corners (flattened)
- ✅ File Size: Under 5MB

## How to Use

1. Go to **App Store Connect** → Your App
2. Navigate to **Monetization** → **Subscriptions**
3. Select **Pro Monthly** subscription
4. Scroll to **Review Information** section
5. Click **Screenshot** → Upload `pro-monthly-review.png`
6. Repeat for **Pro Annual** subscription with `pro-annual-review.png`

## How to Regenerate

If you need to update the screenshots (e.g., change pricing, features, or branding):

### Method 1: From SVG Source Files
```bash
cd /Users/chadbrown/projects/TheEqualizer/docs
qlmanage -t -s 1024 -o ../Screenshots pro-monthly-review.svg pro-annual-review.svg
cd ../Screenshots
mv pro-monthly-review.svg.png pro-monthly-review.png
mv pro-annual-review.svg.png pro-annual-review.png
```

### Method 2: Edit SVG Files Directly
1. Open `docs/pro-monthly-review.svg` or `docs/pro-annual-review.svg` in a text editor
2. Edit prices, features, or colors
3. Run the regeneration commands above

### Brand Colors Used
- Primary Purple: `#A855F7`
- Accent Magenta: `#C026D3`
- Success Green: `#10b981` (for "SAVE 17%" badge on annual)

## Verification

To verify images meet Apple's requirements:
```bash
sips -g pixelWidth -g pixelHeight -g dpiWidth -g dpiHeight -g space pro-monthly-review.png
```

Expected output:
```
pixelWidth: 1024
pixelHeight: 1024
dpiWidth: 72.000
dpiHeight: 72.000
space: RGB
```

## Related Documentation

- **Complete Submission Guide:** `APP_STORE_SUBMISSION_GUIDE.md` (in project root)
- **SVG Source Files:** `docs/pro-monthly-review.svg`, `docs/pro-annual-review.svg`
- **App Store Listing:** `APP_STORE_LISTING.md` (in project root)

## Notes

- These screenshots are ONLY for Apple's review process
- They show Apple reviewers what subscribers get
- They are NOT displayed to end users in the App Store
- Update whenever subscription pricing or features change
- Keep consistent with actual app functionality

---

**Last Updated:** 2025-01-16
**App Version:** 1.3 (Build 3)
