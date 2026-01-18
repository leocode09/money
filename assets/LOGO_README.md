# 💰 Money Tracker App Logo

## Quick Start Guide

This folder contains the logo design file for your Money Tracker app. Follow these steps to apply your new logo:

## 📋 Step-by-Step Instructions

### Step 1: View Logo Options
1. Open `logo_design.html` in your web browser
2. You'll see 4 professional logo designs
3. Choose your favorite (we recommend **Option 3**)

### Step 2: Download the Logo
1. Click the download button for your chosen design
2. The SVG file will be saved to your downloads folder

### Step 3: Convert to PNG
Convert the SVG to PNG format (1024x1024 pixels) using one of these methods:

**Online Tools (Easiest):**
- https://www.svgtopng.com
- https://cloudconvert.com/svg-to-png
- https://svgexport.com

**Design Software:**
- Figma (free): Import SVG, export as PNG
- Adobe Illustrator
- Inkscape (free)
- GIMP (free)

### Step 4: Save the Files
You need to create TWO versions:

1. **icon.png** - Full logo with gradient background (1024x1024px)
2. **icon_foreground.png** - Just the white icon part, transparent background (1024x1024px)

Save both files in this `assets/` folder.

### Step 5: Install Dependencies
Run this command in your terminal:
```bash
flutter pub get
```

### Step 6: Generate App Icons
Run this command:
```bash
flutter pub run flutter_launcher_icons
```

This will automatically create all the required icon sizes for Android.

### Step 7: Rebuild Your App
```bash
flutter clean
flutter run
```

Your new logo will now appear as the app icon! 🎉

---

## 🎨 Logo Design Details

### Color Scheme
- **Primary Gradient**: `#6366F1` → `#8B5CF6` (Indigo to Purple)
- **Background**: `#6366F1` (Indigo)
- **Accent**: White with opacity for depth

### Design Philosophy
- **Modern & Professional**: Clean lines and contemporary gradients
- **Trustworthy**: Financial app aesthetic
- **Memorable**: Unique wallet + growth symbolism
- **Scalable**: Looks great from 48px to 1024px

### Recommended Choice: Option 3 ⭐
**Why Option 3 is the best:**
- ✅ Perfect balance of detail and simplicity
- ✅ Matches your app's purple gradient theme
- ✅ Clearly communicates "money tracking + growth"
- ✅ Professional and trustworthy appearance
- ✅ Works beautifully on all backgrounds
- ✅ Recognizable at small sizes

---

## 🔧 Troubleshooting

### Icons not updating?
```bash
flutter clean
flutter pub get
flutter pub run flutter_launcher_icons
flutter run
```

### Need different sizes?
The flutter_launcher_icons package automatically generates:
- mipmap-mdpi (48x48)
- mipmap-hdpi (72x72)
- mipmap-xhdpi (96x96)
- mipmap-xxhdpi (144x144)
- mipmap-xxxhdpi (192x192)

### Want to customize?
Edit `pubspec.yaml` and change these values:
```yaml
flutter_launcher_icons:
  android: true
  ios: false
  image_path: "assets/icon.png"
  adaptive_icon_background: "#6366F1"  # Change this color
  adaptive_icon_foreground: "assets/icon_foreground.png"
```

---

## 📱 Where Your Logo Appears

After applying, your logo will show up in:
- App drawer/launcher
- Recent apps screen
- Settings → Apps
- Play Store (when published)
- Notifications
- App shortcuts

---

## 💡 Tips

1. **Always use PNG format** for the final icons (not SVG)
2. **Use transparent backgrounds** for the foreground icon
3. **Test on multiple devices** to ensure it looks good
4. **Keep it simple** - complex details don't show at small sizes
5. **High contrast** works best for visibility

---

## 📞 Need Help?

If you encounter any issues:
1. Make sure both `icon.png` and `icon_foreground.png` are in the `assets/` folder
2. Check that files are exactly 1024x1024 pixels
3. Ensure flutter_launcher_icons is in `dev_dependencies` in pubspec.yaml
4. Try `flutter clean` before regenerating icons

---

## 🎯 Current Configuration

Your `pubspec.yaml` is already configured with:
```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.13.1

flutter_launcher_icons:
  android: true
  ios: false
  image_path: "assets/icon.png"
  min_sdk_android: 21
  adaptive_icon_background: "#6366F1"
  adaptive_icon_foreground: "assets/icon_foreground.png"
```

All you need to do is add the PNG files and run the commands!

---

**Created for Money Tracker App** 📊💰
*A modern, beautiful transaction tracking application*