# The Equalizer - App Store Submission Guide

**Last Updated:** 2025-01-16 (Version 1.3, Build 3)
**Status:** Submitted and waiting for review

---

## Table of Contents
1. [Pre-Submission Checklist](#pre-submission-checklist)
2. [App Information](#app-information)
3. [Pricing & Monetization](#pricing--monetization)
4. [Subscription Setup](#subscription-setup)
5. [Export Compliance](#export-compliance)
6. [App Review Information](#app-review-information)
7. [Developer Name & Branding](#developer-name--branding)
8. [Common Issues & Solutions](#common-issues--solutions)

---

## Pre-Submission Checklist

### Before Each Submission:
- [ ] Update version number (MAJOR.MINOR.PATCH)
- [ ] Update build number (always increment)
- [ ] Test on iPhone SE, iPhone 16, iPhone 16 Pro Max
- [ ] Verify dark mode compatibility
- [ ] Test offline mode and sync recovery
- [ ] Update copyright year if needed: `© 2025 Brownster Bits`
- [ ] Commit all changes to git
- [ ] Archive and upload build to App Store Connect

### First-Time Submission Only:
- [ ] Complete app metadata (name, subtitle, description, keywords)
- [ ] Upload screenshots for all required device sizes
- [ ] Set up subscription products and pricing
- [ ] Configure support URL and marketing URL
- [ ] Set app price to $0.00 (Free)
- [ ] Complete export compliance
- [ ] Provide app review information

---

## App Information

### Basic Details

**App Name:** The Equalizer

**Subtitle (30 chars):** Split Event Costs Fairly

**Primary Category:** Finance

**Secondary Category:** Productivity (optional)

**Copyright:** 2025 Brownster Bits

**Age Rating:** 4+ (No objectionable content)

---

### URLs

**Support URL (Required):**
```
https://brownsterbits.github.io/TheEqualizer/help.html
```

**Marketing URL (Optional but Recommended):**
```
https://brownsterbits.github.io/TheEqualizer/
```

**Privacy Policy URL (Required):**
```
https://brownsterbits.github.io/TheEqualizer/privacy.html
```

**Terms of Service URL (Optional):**
```
https://brownsterbits.github.io/TheEqualizer/terms.html
```

---

### Description & Keywords

See `APP_STORE_LISTING.md` for:
- Promotional Text (170 chars max)
- Full Description (4,000 chars max) - Use `APP_STORE_DESCRIPTION_CLEAN.txt`
- Keywords (100 chars max, comma-separated, no spaces)

**Important:** Use `APP_STORE_DESCRIPTION_CLEAN.txt` for the description - it has special characters removed that App Store Connect rejects (em dashes, bullet points, checkmarks, smart quotes).

---

## Pricing & Monetization

### App Price
**Set to:** $0.00 (Free)

**Why:** The app uses a freemium model with in-app subscriptions for Pro features. Making the app free:
- Removes barrier to entry
- Allows users to try the free tier (1 event limit)
- Maximizes downloads
- Users upgrade when they need Pro features

### In-App Purchases
**Type:** Auto-Renewable Subscriptions

See [Subscription Setup](#subscription-setup) section below.

---

## Subscription Setup

### Subscription Group

**Name:** Pro Subscription (internal only, users don't see this)

**Contains:** 2 subscription products (Monthly and Annual)

---

### Product 1: Pro Monthly

**Reference Name (Internal):** Pro Monthly

**Product ID:** `com.brownsterbits.theequalizer.pro.monthly`
- ⚠️ **Cannot be changed after creation**
- Must be lowercase, alphanumeric, dots and dashes only
- Format: `com.[company].[appname].pro.monthly`

**Duration:** 1 Month

**Price:** $1.99 USD

**Display Name:** Pro Monthly

**Description:**
```
Unlimited events with real-time sync across all devices
```

**Review Screenshot:**
- Location: `Screenshots/pro-monthly-review.png`
- Size: 1024x1024 pixels
- DPI: 72
- Format: PNG
- Requirements: RGB color space, no rounded corners

**Review Notes:**
```
Pro Monthly subscription unlocks:
• Unlimited events (free tier limited to 1 event)
• Cloud sync across all devices via Firebase
• Event sharing with invite codes
• Real-time updates for all participants

All core features (expense tracking, Treasury donations, settlement calculations) work in both free and Pro tiers. Pro removes the 1-event limit and adds multi-device/sharing capabilities.
```

---

### Product 2: Pro Annual

**Reference Name (Internal):** Pro Annual

**Product ID:** `com.brownsterbits.theequalizer.pro.annual`
- ⚠️ **Cannot be changed after creation**

**Duration:** 1 Year

**Price:** $19.99 USD (17% savings vs monthly)

**Display Name:** Pro Annual

**Description:**
```
Unlimited events with real-time sync. Save 17% vs monthly!
```

**Review Screenshot:**
- Location: `Screenshots/pro-annual-review.png`
- Size: 1024x1024 pixels
- Includes green "SAVE 17%" badge
- Same requirements as monthly screenshot

**Review Notes:**
```
Pro Annual subscription unlocks:
• Unlimited events (free tier limited to 1 event)
• Cloud sync across all devices via Firebase
• Event sharing with invite codes
• Real-time updates for all participants

Annual subscription offers same features as monthly at discounted rate ($19.99/year vs $1.99/month = $23.88/year, saving $3.89 annually).

All core features work in both free and Pro tiers. Pro removes the 1-event limit and adds multi-device/sharing capabilities.
```

---

### Subscription Screenshots Requirements

**Apple Requirements:**
- **Dimensions:** 1024 x 1024 pixels (exactly)
- **Format:** PNG or JPG
- **DPI:** 72 dpi
- **Color Space:** RGB
- **Corners:** No rounded corners (flattened)
- **File Size:** No official limit, but keep under 5MB

**Current Screenshots:**
- `Screenshots/pro-monthly-review.png` - 495 KB
- `Screenshots/pro-annual-review.png` - 512 KB

Both screenshots use brand colors (#C026D3 magenta, #A855F7 purple) and show:
- App logo
- Pricing
- 4 Pro features with checkmarks
- Annual version includes "SAVE 17%" badge

**To Regenerate (if needed):**
```bash
cd /Users/chadbrown/projects/TheEqualizer/docs
qlmanage -t -s 1024 -o ../Screenshots pro-monthly-review.svg pro-annual-review.svg
cd ../Screenshots
mv pro-monthly-review.svg.png pro-monthly-review.png
mv pro-annual-review.svg.png pro-annual-review.png
```

---

### Optional: Introductory Offers

**Recommendation:** Add a 7-day free trial to increase conversions.

**Setup (Future Enhancement):**
1. In App Store Connect → Subscriptions → Select product
2. Click "Add Introductory Offer"
3. Select "Free" and "7 Days"
4. Save and submit for review

**Benefits:**
- Significantly increases conversion rates
- Industry standard (7 days for subscription apps)
- Users can try Pro features risk-free

---

## Export Compliance

**Required for all apps that use encryption (including HTTPS).**

### Question 1: Does your app use cryptography?

**Answer:** YES

**Explanation:** The app uses:
- HTTPS for Firebase communication
- Standard iOS networking encryption
- Apple Sign In (uses encryption)

---

### Question 2: Select encryption algorithms

**Answer:** ✅ **Standard encryption algorithms instead of, or in addition to, using or accessing the encryption within Apple's operating system**

**Do NOT select:** "Proprietary or non-standard algorithms"

**Explanation:** The app only uses standard encryption:
- HTTPS/TLS (Firebase)
- Standard iOS encryption APIs
- No custom or proprietary encryption

---

### Question 3: Distribution in France?

**Answer:** NO (for initial launch)

**Why:**
- Avoids French encryption approval paperwork
- Simplifies initial submission
- Can add France later if needed
- App still available in 170+ other countries

**If you want France:**
- Select YES
- Upload French encryption declaration approval form
- May delay app review

**To Add France Later:**
1. Go to App Store Connect → Pricing and Availability
2. Add France to territories
3. Complete French requirements at that time

---

### Alternative: Set in Info.plist (Future Builds)

To skip this questionnaire in future builds, add to your app's `Info.plist`:

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

This tells Apple you only use exempt encryption (standard HTTPS/TLS).

---

## App Review Information

### Demo Account

**Not Required** - App works without login.

Include this note in review instructions:
```
No demo account needed. App works completely offline in free mode without any login.
```

---

### Review Testing Instructions

**Copy this into "App Review Information → Notes" section:**

```
TESTING INSTRUCTIONS - NO LOGIN REQUIRED

The Equalizer works completely offline in free mode. No account or sign-in needed.

BASIC TEST PATH (2-3 minutes):

1. Launch app - it opens directly to Events screen
2. Tap "Create New Event" button
3. Enter event name (e.g., "Weekend Trip") and tap Create
4. Tap "Members" tab → tap + button
5. Add 2-3 members (e.g., "Alice", "Bob", "Carol")
6. Tap "Expenses" tab → tap + button
7. Add an expense:
   - Description: "Hotel"
   - Amount: 300
   - Paid By: Select "Alice"
   - Split Among: Leave all members checked
   - Tap Save
8. Tap "Summary" tab to see expense breakdown
9. Tap "Settlement" tab to see who owes what

EXPECTED RESULT:
Settlement should show Bob and Carol each owe Alice $100 (fair split of $300 hotel cost).

OPTIONAL - TEST TREASURY FEATURE:
From Expenses tab, tap "Treasury Donations" → add a donation from any member.
Check Settlement tab to see how donations reduce everyone's share.

FREE vs PRO:
- Free tier (being reviewed): 1 event, local storage, full functionality
- Pro tier: Unlimited events, cloud sync, event sharing (requires Apple Sign In)
- All core features work in free tier without any login

No demo account needed. App is ready to test immediately upon launch.
```

---

### Contact Information

**First Name:** Chad

**Last Name:** Brown

**Phone Number:** [Your phone number]

**Email:** bits@brownster.com

**Notes:** Available for follow-up questions during review process.

---

## Developer Name & Branding

### Current Status (as of 2025-01-16)

**Copyright Updated:** ✅ `© 2025 Brownster Bits`
- Updated in App Store Connect for all 3 apps:
  - Heart Safe Alerts
  - Loaner Pro
  - The Equalizer

**Developer Name Display:** ⚠️ Still shows personal name (needs update)

---

### Where Developer Name Appears

The "Developer" name shown on the App Store comes from:
1. **Apple Developer Account** → Membership → Account Holder name
2. **App Store Connect** → Account Settings → Legal Entity Name

**This is NOT set per-app - it's account-wide.**

---

### How to Check Current Developer Name

1. Go to **Apple Developer Portal**: https://developer.apple.com/account
2. Click **Membership** (left sidebar)
3. Look at **Account Holder** field
4. Also check **App Store Connect**: https://appstoreconnect.apple.com
5. Click your name (top right) → **View Account**
6. Check **Legal Entity Name**

**Whatever name shows here appears as "Developer" for all your apps.**

---

### How to Change to "Brownster Bits"

You have **3 options**:

#### Option 1: Update Individual Account Name (Easiest, Limited)

**Steps:**
1. Go to https://appleid.apple.com
2. Sign in with your Apple ID
3. Update name to "Brownster Bits"
4. Wait 24-48 hours for propagation

**⚠️ Limitation:** Apple may not accept business names for individual developer accounts. They may require proof it's your legal name.

**Best For:** If "Brownster Bits" is your legal DBA (Doing Business As) name.

---

#### Option 2: Enroll as Organization (Recommended for Business)

**Requirements:**
- D-U-N-S Number (free from Dun & Bradstreet)
- Legal business entity (LLC, Corporation, etc.)
- Business verification documents
- $99/year (separate from individual account)

**Steps:**
1. Register "Brownster Bits" as legal business entity (LLC, etc.)
2. Get D-U-N-S number: https://www.dnb.com/duns-number.html
3. Enroll new Apple Developer account as **Organization**
4. Transfer apps from individual to organization account

**Timeline:** 2-4 weeks (D-U-N-S + verification)

**Benefits:**
- Clean business branding
- Multiple team members
- Professional appearance
- Separate from personal identity

**Drawbacks:**
- Requires legal business entity
- Additional $99/year
- App transfer process required

---

#### Option 3: DBA/Doing Business As (Middle Ground)

**Requirements:**
- Register "Brownster Bits" as DBA in your state
- Costs vary by state ($10-100)
- Takes 1-2 weeks

**Steps:**
1. File DBA registration with your county/state
2. Receive DBA certificate
3. Update Apple Developer account with DBA name
4. Provide DBA documentation if requested

**Benefits:**
- Simpler than full business entity
- Lower cost than LLC
- Apple may accept DBA for individual accounts

**Best For:** Solo developers who want business branding without full LLC.

---

### Recommendation

**For Now:**
- Copyright is updated to "Brownster Bits" ✅
- This shows in app details and legal sections

**Next Step (When Ready):**
1. Check what name currently shows in Apple Developer account
2. If it's your personal name and you want to change it:
   - **Quick:** File DBA for "Brownster Bits" (1-2 weeks, ~$50)
   - **Proper:** Form LLC and enroll as organization (4-6 weeks, ~$500+)

**Priority:** Low - Copyright shows "Brownster Bits" which is most visible to users. Developer account name is less prominent.

---

## Common Issues & Solutions

### Issue: "Invalid character" in description

**Problem:** App Store Connect rejects description with special characters.

**Solution:** Use `APP_STORE_DESCRIPTION_CLEAN.txt` which has:
- Em dashes (—) → Regular hyphens (-)
- Bullet points (•) → Asterisks (*)
- Checkmarks (✓) → Removed
- Smart quotes (" ") → Straight quotes (" ")

---

### Issue: Subscription screenshot rejected

**Problem:** "Image does not meet requirements"

**Causes & Solutions:**
1. **Wrong dimensions:** Must be exactly 1024x1024 pixels
2. **Wrong DPI:** Must be 72 dpi (not 96 or 144)
3. **Wrong color space:** Must be RGB (not CMYK)
4. **Rounded corners:** Apple requires no rounded corners
5. **File too large:** Keep under 5MB

**Verify with:**
```bash
sips -g pixelWidth -g pixelHeight -g dpiWidth -g dpiHeight -g space /path/to/image.png
```

**Fix:**
- Use provided screenshots in `Screenshots/` folder
- Or regenerate from SVG files in `docs/` folder

---

### Issue: Export compliance questionnaire appears

**Problem:** Build shows "Missing export compliance information"

**Solution:** Complete questionnaire (see [Export Compliance](#export-compliance) section)

**Quick Answers:**
1. Uses encryption? → YES
2. Which type? → Standard encryption algorithms
3. France distribution? → NO (for simplicity)

---

### Issue: "No active account" or StoreKit errors in simulator

**Problem:** First interaction with app causes keyboard delay or "No active account" error.

**Cause:** StoreKit + keyboard initialization timing issue (simulator-specific).

**Solutions:**
- **Workaround:** Splash screen on first launch gives time for initialization
- **Testing:** Test on real device for accurate behavior
- **Not a blocker:** Apple reviewers test on real devices, won't encounter this

---

### Issue: App name already taken

**Problem:** "The app name you entered is already being used"

**Solutions:**
1. Add descriptor: "The Equalizer - Event Expenses"
2. Add company name: "The Equalizer by Brownster Bits"
3. Use subtitle to clarify: Keep name generic, use subtitle for differentiation

---

### Issue: App rejected for Guideline 4.2 (Minimum Functionality)

**Problem:** App seems too simple or similar to existing apps.

**Solutions:**
1. Emphasize unique Treasury feature in description
2. Provide detailed testing instructions showing full functionality
3. Include comparison showing how it differs from competitors
4. Highlight real-world use cases in app review notes

---

## Version History

### Version 1.3 (Build 3) - 2025-01-16
**Status:** Submitted, waiting for review

**Changes:**
- Added Help & FAQ page (https://brownsterbits.github.io/TheEqualizer/help.html)
- Fixed expense interaction bugs (edit/delete/add direct donations)
- Improved Picker validation timing
- Updated copyright to "© 2025 Brownster Bits"
- Created subscription review screenshots
- Initial App Store submission

**Submission Details:**
- App Price: $0.00 (Free)
- Subscriptions: Pro Monthly ($1.99), Pro Annual ($19.99)
- Export Compliance: Completed (standard encryption only)
- France Distribution: Excluded for initial launch

---

### Version 1.2 (Build 2) - 2025-01-15
**Status:** Internal testing

**Changes:**
- Previous version details...

---

## Future Enhancements

### For Next Submission:
- [ ] Add 7-day free trial for subscriptions
- [ ] Add France to distribution territories (if needed)
- [ ] Update screenshots if UI changes significantly
- [ ] Consider adding App Preview video
- [ ] Collect and add real user testimonials to description
- [ ] A/B test different promotional text variations
- [ ] Update keywords based on App Store Connect analytics

### Long-term:
- [ ] Localize for additional languages (Spanish, French, German)
- [ ] Add seasonal promotional text variations
- [ ] Monitor and optimize keyword performance
- [ ] Track conversion rates for different app store assets
- [ ] Consider adding more subscription tiers if needed

---

## Quick Reference

### Important Files

**App Store Materials:**
- `APP_STORE_LISTING.md` - Complete listing details
- `APP_STORE_DESCRIPTION_CLEAN.txt` - Description for copy/paste
- `Screenshots/pro-monthly-review.png` - Monthly subscription screenshot
- `Screenshots/pro-annual-review.png` - Annual subscription screenshot

**Documentation:**
- `APP_STORE_SUBMISSION_GUIDE.md` - This file
- `TESTING_GUIDE.md` - Testing procedures
- `FIREBASE_RULES.md` - Security rules documentation

**Web Assets:**
- `docs/index.html` - Marketing landing page
- `docs/help.html` - Help & FAQ page
- `docs/privacy.html` - Privacy policy
- `docs/terms.html` - Terms of service

---

### Key URLs

**App Store Connect:** https://appstoreconnect.apple.com

**Apple Developer:** https://developer.apple.com/account

**TestFlight:** https://appstoreconnect.apple.com/apps/[APP_ID]/testflight

**Marketing Page:** https://brownsterbits.github.io/TheEqualizer/

**Help Page:** https://brownsterbits.github.io/TheEqualizer/help.html

---

### Support Contacts

**Developer Email:** bits@brownster.com

**GitHub Issues:** https://github.com/brownsterbits/TheEqualizer/issues

**Apple Support:** https://developer.apple.com/contact/

---

## Notes for Future Submissions

### Before Each Update:
1. Increment version and build numbers
2. Update "What's New in This Version" text
3. Test thoroughly on multiple devices
4. Update copyright year if needed
5. Review and update keywords if analytics suggest changes
6. Check for seasonal promotional text opportunities

### After Approval:
1. Monitor crash reports in App Store Connect
2. Track download and conversion metrics
3. Respond to user reviews
4. Note any common feedback for next update
5. Update keywords based on search performance

---

**End of App Store Submission Guide**

For questions or issues during submission, contact: bits@brownster.com
